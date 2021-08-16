# pg_backup
Automated postgreSQL backup on Linux

Based on postgresql source code [Automated Backup on Linux](https://wiki.postgresql.org/wiki/Automated_Backup_on_Linux), I have build my own backup automation script

It can:

- create daily / weekly / daily backups
- define backup location on darwin (mac) and linux system
- write logs journal
- send logs to telegram
- send dump files to telegram
- delete old backups

## Configuration
* `cd pg_backup`
* Create copy of configuretion file to keep example clean for git
	* `cp pg_backup.config pg_backup.local.config`
	* Fill in necessary fields. In case you want to use telegram for logs and saving backup files, write chat id and bot token, because script is not validating this fields.

* Create `.pgpass` file to automate password login to databases provided in config
* test run:
	* `bash pg_backup_rotated.sh`
	* `-c pg_backup.local.config` - provide custom config file with -c option
* set up the daily cronjob
	* `crontab -e`
	* we need to specifically write file locations
	* `* 4 * * *  /bin/bash /home/username/pg_backup/pg_backup_rotated.sh -c /home/username/pg_backup/pg_backup.local.config`
		* will run backup script with custom config daily at 4 A.M.