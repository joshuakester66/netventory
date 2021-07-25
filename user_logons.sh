#!/bin/bash
#Filename: user_logons.sh
#Description: 
# This script assumes that your domain controllers are pushing event logs to librenms
# This will pull syslog data from librenms based on the domain controllers specifed below
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# procmail (lockfile command)
# mysql-connector-odbc
# mariadb-server/mysqld

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="user_logons"
SCRIPT_CAT="netventory"

mkdir -p $HOME/scripts/logs &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
CURRENT_HOUR=`date +%Y-%m-%d\ %H:`
LOG="$HOME/scripts/logs/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
DOMAIN_CONTROLLERS="acwsdc1 chwsdc2 chwsdc3 MCWV-DC1 chwsdns2 chwsdc1 chwsdns1-r2"
LIBRENMS_DATABASE="librenms"
NETVENTORY_DATABASE="netventory"
DEVICE_TABLE="devices"
SYSLOG_TABLE="syslog"
LOGON_TABLE="logons"
IP_COLUMN="ip"
ODBC_SERVER="librenms"
REMOTE_DATABASE="librenms"
REMOTE_TABLE="syslog"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
SYSLOG_FILE="$WORKING_DIR/syslog_file"
TEST_FILE="$WORKING_DIR/test_file"
DAYS_EXPIRED="90"

#################################################
# COLORS
#################################################
Colors() {
ESCAPE="\033";
BLACKF="${ESCAPE}[30m";
REDF="${ESCAPE}[31m";
GREENF="${ESCAPE}[32m";
YELLOWF="${ESCAPE}[33m";
BLUEF="${ESCAPE}[34m";
PURPLEF="${ESCAPE}[35m";
CYANF="${ESCAPE}[36m";
WHITEF="${ESCAPE}[37m";
RESET="${ESCAPE}[0m";
}
Colors;
#################################################

CTRL_C ()
{
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been unlocked"${RESET} >> $LOG
echo ""
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}$SCRIPT_NAME.sh was cancelled"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG
# reset
exit 99
}

SCRIPT_RUNNING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Script is currently running. Exiting"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG
exit 95
}

EXIT_FUNCTION ()
{
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been unlocked"${RESET} >> $LOG
echo ""
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}$SCRIPT_NAME.sh has exited for error $EXIT_CODE"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG
# reset
exit $EXIT_CODE
}

GET_DEVICE_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the Device ID for $DOMAIN_CONTROLLER"${RESET} >> $LOG
DEVICE_ID=
DEVICE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT device_id FROM $LIBRENMS_DATABASE.$DEVICE_TABLE WHERE hostname LIKE '%$DOMAIN_CONTROLLER%';"`
}

GET_SYSLOG ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the messages for Device ID $DEVICE_ID"${RESET} >> $LOG
SYSLOG_MESSAGE=
SYSLOG_MESSAGE=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT * FROM $LIBRENMS_DATABASE.$SYSLOG_TABLE WHERE device_id='$DEVICE_ID' AND timestamp LIKE '$CURRENT_HOUR%';"`
}

OUTPUT_TO_FILE ()
{
# echo "$SYSLOG_MESSAGE" >> $TEST_FILE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Pushing the syslog messages to a file"${RESET} >> $LOG
echo "$SYSLOG_MESSAGE" | sed '/\$Account Domain/d' | sed 's/^.*05\s*\([0-9]\{4\}\-[0-9]\{2\}\-[0-9]\{2\}\s[0-9]\{2\}\:[0-9]\{2\}\:[0-9]\{2\}\).*Audit\sSuccess\([0-9A-Za-z\._-]*\)\.wvcmsdom.*Account\sName\:\([0-9A-Za-z\._-]*\)\$\?Account\sDomain\:\([0-9A-Za-z\._-]*\)Logon\sID.*Source\sNetwork\sAddress\:\([A-Fa-f0-9\:\.-]*\)Source\sPort.*$/\1;\2;\3;\4;\5/g' | sed 's/ /_/g' | sort --unique >> $SYSLOG_FILE
}

GET_INFO ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Parsing the line for variables"${RESET} >> $LOG
LOGON_ID=
TIMESTAMP=
DOMAIN_CONTROLLER=
AD_USER=
DOMAIN=
IP=
DNS_HOSTNAME=
TIMESTAMP=$(echo "$LINE" | sed 's/_/ /g' | sed 's/;.*$//g')
DOMAIN_CONTROLLER=$(echo "$LINE" | sed 's/_/ /g' | sed 's/^[0-9 _:-]*;//g' | sed 's/;.*$//g')
AD_USER=$(echo "$LINE" | sed 's/_/ /g' | sed 's/^[0-9 :-]*;[A-Za-z0-9\._-]*;//g' | sed 's/;.*$//g')
DOMAIN=$(echo "$LINE" | sed 's/_/ /g' | sed 's/;[0-9\.]*$//g' | sed s'/^.*;//g')
DOMAIN="${DOMAIN,,}"
IP=$(echo "$LINE" | sed 's/_/ /g' | sed 's/^.*;//g')
DNS_HOSTNAME=$(dig +short -x $IP | head -n 1 | sed 's/\..*\.wvc-ut\.gov//g' | sed 's/\.wvcmsdom//g' | sed 's/\.$//g')
LOGON_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$LOGON_TABLE WHERE timestamp='$TIMESTAMP' AND domain_controller='$DOMAIN_CONTROLLER' AND username='$AD_USER' AND domain='$DOMAIN' AND hostname='$DNS_HOSTNAME' AND ip='$IP';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Working with the following information:"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Timestamp: $TIMESTAMP"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain Controller: $DOMAIN_CONTROLLER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Username: $AD_USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain: $DOMAIN"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP Address: $IP"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Hostname: $DNS_HOSTNAME"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Logon ID: $LOGON_ID"${RESET} >> $LOG
EXCEPTIONS
}

EXCEPTIONS ()
{
case $USERNAME
	in
		"-")			echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Username: $USERNAME does not meet the criteria. Moving on"${RESET} >> $LOG
						continue;;
		# "*iosk*")		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Username: $USERNAME does not meet the criteria. Moving on"${RESET} >> $LOG
		# 				continue;;
		# *service*)		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Username: $USERNAME does not meet the criteria. Moving on"${RESET} >> $LOG
		# 				continue;;
esac
case $DNS_HOSTNAME
	in
		*unknown*)		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Hostname: $DNS_HOSTNAME does not meet the criteria. Moving on"${RESET} >> $LOG
						continue;;
esac
case $IP
	in
		"-")		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}IP: $IP does not meet the criteria. Moving on"${RESET} >> $LOG
					continue;;
		"::1")		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}IP: $IP does not meet the criteria. Moving on"${RESET} >> $LOG
					continue;;
esac
}

IMPORT_TO_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding or updating the data in the database"${RESET} >> $LOG
if [[ -z "$LOGON_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}An entry for the previous information did not exist"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding it to the database"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
INSERT INTO $LOGON_TABLE(id,timestamp,domain_controller,username,domain,hostname,ip,added,updated) VALUES(NULL,'$TIMESTAMP','$DOMAIN_CONTROLLER','$AD_USER','$DOMAIN','$DNS_HOSTNAME','$IP','$TODAY','$TODAY');
EOF
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}An entry for the previous information did exist"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $LOGON_TABLE SET updated='$TODAY' WHERE timestamp='$TIMESTAMP' AND domain_controller='$DOMAIN_CONTROLLER' AND username='$AD_USER' AND domain='$DOMAIN' AND hostname='$DNS_HOSTNAME' AND ip='$IP';
EOF
fi
}

CLEANUP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Performing cleanup on the database"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Setting entries to null that have a -"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
# UPDATE FROM $NETVENTORY_DATABASE.$LOGON_TABLE SET domain=null WHERE domain='-';
# EOF
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
# UPDATE FROM $NETVENTORY_DATABASE.$LOGON_TABLE SET ip=null WHERE ip='-';
# EOF
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Setting entries to null that are blank"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
# UPDATE FROM $NETVENTORY_DATABASE.$LOGON_TABLE SET hostname=null WHERE hostname='';
# EOF
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Deleting all entries where the username is only a dash"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
DELETE FROM $NETVENTORY_DATABASE.$LOGON_TABLE WHERE username LIKE '% %';
EOF
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Deleting all entries where the username has a space in it"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
# DELETE FROM $NETVENTORY_DATABASE.$LOGON_TABLE WHERE username LIKE '% %';
# EOF
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Deleting all entries that only have a 3 letter hostname"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
# DELETE FROM $NETVENTORY_DATABASE.$LOGON_TABLE WHERE username REGEXP '^...$';
# EOF
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Deleting all entries older than $DAYS_EXPIRED"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
DELETE FROM $NETVENTORY_DATABASE.$LOGON_TABLE WHERE updated < NOW() - INTERVAL $DAYS_EXPIRED DAY;
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked"${RESET} >> $LOG

rm -Rf $SYSLOG_FILE &> /dev/null
# rm -Rf $TEST_FILE &> /dev/null
for DOMAIN_CONTROLLER in $DOMAIN_CONTROLLERS
	do
		GET_DEVICE_ID
		if [[ -n "$DEVICE_ID" ]]
			then
#				read -p "Working on Device ID: $DEVICE_ID" DEBUG
				GET_SYSLOG
				OUTPUT_TO_FILE
			else
				continue
		fi
done
for LINE in `cat $SYSLOG_FILE`
	do
		GET_INFO
		IMPORT_TO_DATABASE
done
CLEANUP

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
