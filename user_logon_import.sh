#!/bin/bash
#Filename: user_logon_import.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="user_logon_import"
SCRIPT_CAT="netventory"

mkdir -p $HOME/scripts/logs &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
CURRENT_HOUR=`date +%Y-%m-%d\ %H:`
LOG="$HOME/scripts/logs/$SCRIPT_NAME.log"
EXPECT_LOG="$HOME/scripts/tmp/$SCRIPT_NAME/logs/expect.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
LOCAL_DATABASE="netventory"
USERS_TABLE="users"
ENDPOINTS_TABLE="endpoints"
LOGONS_TABLE="logons"
DHCP_TABLE="dhcp"
ODBC_SERVER="librenms.netventory"
REMOTE_DATABASE="netventory"
REMOTE_TABLE="logons"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
SQL_COMMAND="SELECT id,timestamp,domain_controller,username,domain,hostname,ip FROM $REMOTE_DATABASE.$REMOTE_TABLE WHERE timestamp LIKE '$CURRENT_HOUR%';"

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

SELECT_MYSQL ()
{
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$LOCAL_TABLE;"`
}

ADD_MYSQL ()
{
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $LOCAL_TABLE(test_id,column1,column2,date,time) VALUES(NULL,'$COLUMN1_VAR','$COLUMN2_VAR','$TODAY','$NOW');
EOF
}

UPDATE_MYSQL ()
{
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $LOCAL_TABLE SET date='$TODAY',time='$NOW' WHERE test_id='$TEST_ID_VAR';
EOF
}

DB_TO_FILE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting user logon logs from LibreNMS"${RESET} >> $LOG
MYSQL_RESULTS=`echo "$SQL_COMMAND" | isql $ODBC_SERVER -b -d,`
echo "$MYSQL_RESULTS" | sed 's/^/\"/g' | sed 's/$/\"/g' | sed 's/,/;/g' | sed 's/ /_/g' > $FILE
}

GET_INFO ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Parsing the line for variables"${RESET} >> $LOG
LINE=$(echo "$LINE" | sed 's/\"//g')
LOGON_ID=
TIMESTAMP=
DOMAIN_CONTROLLER=
USERNAME=
DOMAIN=
IP=
HOSTNAME=
LOGON_ID=$(echo "$LINE" | sed 's/;.*$//g')
TIMESTAMP=$(echo "$LINE" | sed 's/^[^;]*;//g' | sed 's/;.*$//g' | sed 's/_/ /g')
DOMAIN_CONTROLLER=$(echo "$LINE" | sed 's/^[^;]*;[^;]*;//g' | sed 's/;.*$//g')
DOMAIN_CONTROLLER="${DOMAIN_CONTROLLER,,}"
USERNAME=$(echo "$LINE" | sed 's/^[^;]*;[^;]*;[^;]*;//g' | sed 's/;.*$//g')
USERNAME="${USERNAME,,}"
DOMAIN=$(echo "$LINE" | sed 's/;[^;]*;[^;]*$//g' | sed 's/^.*;//g')
DOMAIN="${DOMAIN,,}"
HOSTNAME=$(echo "$LINE" | sed 's/;[^;]*$//g' | sed 's/^.*;//g')
HOSTNAME="${HOSTNAME,,}"
IP=$(echo "$LINE" | sed 's/^.*;//g')
if [[ -z "$USERNAME" ]]
	then
		continue
fi
if [[ -z "$HOSTNAME" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the IP and Hostname to the $ENDPOINTS_TABLE table"${RESET} >> $LOG
		HOSTNAME=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT hostname FROM $LOCAL_DATABASE.$DHCP_TABLE where ip='$IP';"`
fi
ENDPOINTS_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINTS_TABLE where ip='$IP';"`
USERS_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$USERS_TABLE where username='$USERNAME';"`
if [[ -z "$ENDPOINTS_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the username to the $USERS_TABLE table"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $ENDPOINTS_TABLE(hostname,ip,added,updated) VALUES('$HOSTNAME','$IP','$NOW','$NOW');
EOF
fi
if [[ -z "$USERS_ID" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $USERS_TABLE(username,added,updated) VALUES('$USERNAME','$NOW','$NOW');
EOF
fi
ENDPOINTS_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINTS_TABLE where ip='$IP';"`
USERS_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$USERS_TABLE where username='$USERNAME';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Working with the following information:"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Timestamp: $TIMESTAMP"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain Controller: $DOMAIN_CONTROLLER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Username: $USERNAME"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain: $DOMAIN"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP Address: $IP"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Hostname: $HOSTNAME"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Logon ID: $LOGON_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoints ID: $ENDPOINTS_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Users ID: $USERS_ID"${RESET} >> $LOG
}

UPDATE_DATABASE ()
{
DATABASE_EXIST=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$LOGONS_TABLE WHERE id='$LOGON_ID';"`
if [[ -z "$DATABASE_EXIST" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $LOGONS_TABLE(id,timestamp,domain_controller,domain,users_id,endpoints_id,added,updated) VALUES('$LOGON_ID','$TIMESTAMP','$DOMAIN_CONTROLLER','$DOMAIN','$USERS_ID','$ENDPOINTS_ID','$TODAY','$TODAY');
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $LOGONS_TABLE SET updated='$TODAY' WHERE id='$LOGON_ID';
EOF
fi
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked"${RESET} >> $LOG

DB_TO_FILE
for LINE in `cat $FILE`
	do
		GET_INFO
		UPDATE_DATABASE
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
