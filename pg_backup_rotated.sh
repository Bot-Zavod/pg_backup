#!/bin/bash

SCRIPTPATH=$(dirname $(stat -f $0))

###########################
########## LOGGER #########
###########################
# logging stdin to log file with time through pipe
function log {
	read -t 0.001 piped
	if [[ "${piped:-}" ]]; then
		log_msg="`date +"%b %d %H:%M:%S"` » $piped"
		echo -e $log_msg | tee -a $SCRIPTPATH/pg_backup.log
		if [ "$TELEGRAM_MODE" = "yes" ] ; then
			curl --globoff -i -X GET "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage?chat_id=${TELEGRAM_CHAT}&text=${log_msg}" > /dev/null
		fi
	fi
}


###########################
####### LOAD CONFIG #######
###########################

# we can pass custom config file for local tests to keep source file clean for git
if [ $# -gt 0 ]; then
	case $1 in
		-c)
			if [ -r "$2" ]; then
				source "$2"
			else
				${ECHO} "Unreadable config file \"$2\"" | log
				exit 1
			fi
			;;
		*)
			${ECHO} "Unknown Option \"$1\"" | log
			exit 2
			;;
	esac
else
	# if no options provided ussume that config in the same directoty with script
	source $SCRIPTPATH/pg_backup.config
fi


###########################
#### PRE-BACKUP CHECKS ####
###########################

# Make sure we're running as the required backup user
if [ "$BACKUP_USER" != "" -a "$(id -un)" != "$BACKUP_USER" ] ; then
	echo "This script must be run as $BACKUP_USER, but current user is $(id -un). Exiting." | log
	exit 1
fi


###########################
### INITIALISE DEFAULTS ###
###########################

if [ ! $DB_HOSTNAME ]; then
	DB_HOSTNAME="localhost"
fi;

if [ ! $DB_USERNAME ]; then
	DB_USERNAME="postgres"
fi;


###########################
#### START THE BACKUPS ####
###########################

function perform_backups()
{
	SUFFIX=$1
	FINAL_BACKUP_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%d`$SUFFIX/"

	echo "Making backup directory in $FINAL_BACKUP_DIR"

	if ! mkdir -p $FINAL_BACKUP_DIR; then
		echo "Cannot create backup directory in $FINAL_BACKUP_DIR. Go and fix it!" | log
		exit 1;
	fi;


	###########################
	###### FULL BACKUPS #######
	###########################

	echo -e "\n\nPerforming full backup on $DATABASE_PROD database"
	echo -e "--------------------------------------------\n"

	if ! pg_dump -b -Fc -h "$DB_HOSTNAME" -U "$DB_USERNAME" -d "$DATABASE_PROD" -f $FINAL_BACKUP_DIR"$DATABASE_PROD".custom.in_progress; then
		echo "[!!ERROR!!] Failed to produce custom backup database $DATABASE_PROD" | log
	else
		mv $FINAL_BACKUP_DIR"$DATABASE_PROD".custom.in_progress $FINAL_BACKUP_DIR"$DATABASE_PROD".custom
		if [ "$TELEGRAM_MODE" = "yes" ] ; then
			# docs https://core.telegram.org/bots/api#senddocument
			curl -s \
				-F "chat_id=${TELEGRAM_CHAT}" \
				-F document=@$FINAL_BACKUP_DIR"$DATABASE_PROD".custom \
				-F "caption=${FINAL_BACKUP_DIR}" \
				"https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" > /dev/null
		fi
	fi

	###########################
	## UPDATE DEV DATABASE ####
	###########################

	if [ "$RESTORE_DEV" = "yes" ]; then
		echo -e "\n\nPerforming pg_restore $DATABASE_PROD backup on $DATABASE_DEV database"
		echo -e "--------------------------------------------\n"
		if ! pg_restore --clean --no-privileges --no-owner -h "$DB_HOSTNAME" -U "$DB_USERNAME" -d "$DATABASE_DEV" < $FINAL_BACKUP_DIR"$DATABASE_PROD".custom; then
			echo "[!!ERROR!!] Failed to restore custom database $DATABASE_PROD backup on $DATABASE_DEV" | log
		else
			if ! psql -U "$DB_USERNAME" -d "$DATABASE_DEV" -h "$DB_HOSTNAME" -c "GRANT ALL PRIVILEGES ON DATABASE $DATABASE_DEV TO $DB_USERNAME_DEV" ; then
				echo "[!!ERROR!!] Failed to GRANT ALL PRIVILEGES ON DATABASE $DATABASE_DEV TO $DB_USERNAME_DEV" | log
			fi

			if ! psql -U "$DB_USERNAME" -d "$DATABASE_DEV" -h "$DB_HOSTNAME" -c "GRANT ALL PRIVILEGES ON DATABASE $DATABASE_DEV TO $DB_USERNAME_DEV" ; then
				echo "[!!ERROR!!] Failed to GRANT ALL PRIVILEGES ON DATABASE $DATABASE_DEV TO $DB_USERNAME_DEV" | log
			fi

			if ! psql -U "$DB_USERNAME" -d "$DATABASE_DEV" -h "$DB_HOSTNAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USERNAME_DEV" ; then
				echo "[!!ERROR!!] Failed to ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USERNAME_DEV" | log
			fi

			if ! psql -U "$DB_USERNAME" -d "$DATABASE_DEV" -h "$DB_HOSTNAME" -c "ALTER DEFAULT PRIVILEGES GRANT ALL ON TABLES TO $DB_USERNAME_DEV" ; then
				echo "[!!ERROR!!] Failed to ALTER DEFAULT PRIVILEGES GRANT ALL ON TABLES TO $DB_USERNAME_DEV" | log
			fi
		fi
	fi;

	echo -e "\nAll database backups complete!"
}

######################
### MONTHLY BACKUPS ##
######################

DAY_OF_MONTH=`date +%d`

if [ $DAY_OF_MONTH -eq 1 ];
then
	# Delete all expired monthly directories
	find $BACKUP_DIR -maxdepth 1 -name "*-monthly" -exec rm -rf '{}' ';'

	perform_backups "-monthly"

	exit 0;
fi

######################
### WEEKLY BACKUPS ###
######################

DAY_OF_WEEK=`date +%u` #1-7 (Monday-Sunday)
EXPIRED_DAYS=`expr $((($WEEKS_TO_KEEP * 7) + 1))`

if [ $DAY_OF_WEEK = $DAY_OF_WEEK_TO_KEEP ];
then
	# Delete all expired weekly directories
	find $BACKUP_DIR -maxdepth 1 -mtime +$EXPIRED_DAYS -name "*-weekly" -exec rm -rf '{}' ';'

	perform_backups "-weekly"

	exit 0;
fi

######################
### DAILY BACKUPS ####
######################

# Delete daily backups 7 days old or more
find $BACKUP_DIR -maxdepth 1 -mtime +$DAYS_TO_KEEP -name "*-daily" -exec rm -rf '{}' ';'

perform_backups "-daily"
