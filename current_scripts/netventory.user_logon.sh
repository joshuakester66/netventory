#!/bin/bash
#Filename: netventory.user_logon.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# net-snmp
# net-snmp-utils
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEBUG

IPS=$1

SCRIPT_NAME="netventory.user_logon"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
WINEXE_CREDENTIALS="$HOME/scripts/.winexe_credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | egrep ^mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | egrep ^mysql_password: | sed 's/mysql_password://g')
LOCAL_DATABASE="netventory"
ENDPOINT_TABLE="endpoint"
OID_TABLE="oid"
SNMP_TABLE="snmp"
ARP_TABLE="arp"
ADDRESS_TABLE="ipv4_addresses"
INTERFACE_TABLE="interface"
OUI_TABLE="oui"
LOGON_TABLE="logon"
USER_TABLE="user"
SNMP_TIMEOUT="0.2"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
COUNT_PER_RUN="50"

IP_SELECT="SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ((ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '10.%.101.%') AND (ping_check > (NOW() - INTERVAL 7 DAY) OR added > (NOW() - INTERVAL 1 DAY)) AND os IS NOT NULL ORDER BY logon_check LIMIT $COUNT_PER_RUN;"
IP_SELECT_COUNT="SELECT COUNT(ip) FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ((ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '10.%.101.%') AND (ping_check > (NOW() - INTERVAL 7 DAY) OR added > (NOW() - INTERVAL 1 DAY)) AND os IS NOT NULL ORDER BY logon_check;"

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

GET_IPS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint IPs"${RESET} >> $LOG
NUMBER_OF_ENDPOINT_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "$IP_SELECT_COUNT"`
ENDPOINT_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "$IP_SELECT"`
}

GET_ENDPOINT_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint ID for $IP"${RESET} >> $LOG
ENDPOINT_ID=
ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
}

GET_LOGONS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the logon information for $IP"${RESET} >> $LOG
USER_LOGON=
USERNAMES=
USER_LOGON=$(winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$IP "query user" 2> /dev/null | sed '/USERNAME/d')
USERNAMES=$(echo "$USER_LOGON" | egrep --color=never -o '^(\s+)?[0-9A-Za-z\.]+' | sed 's/\s//g')
}

LOGON_TIME ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User: $USERNAME"${RESET} >> $LOG
LAST_LOGON=
LAST_LOGON=$(echo "$USER_LOGON" | egrep --color=never "\s$USERNAME\s" | egrep --color=never -o '[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{4}\s[0-9]{1,2}\:[0-9]{1,2}')
LAST_LOGON=`date -d "$LAST_LOGON" +%Y-%m-%d\ %H:%M:%S`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Time: $LAST_LOGON"${RESET} >> $LOG
}

GET_USER_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the User ID for $USERNAME"${RESET} >> $LOG
USER_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$USER_TABLE WHERE username='$USERNAME';"`
if [[ -z "$USER_ID" ]]
	then
		ADD_USERNAME_TO_DATABASE
fi
USER_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$USER_TABLE WHERE username='$USERNAME';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User ID: $USER_ID"${RESET} >> $LOG
}

ADD_USERNAME_TO_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $USERNAME to the $USER_TABLE table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT IGNORE INTO $USER_TABLE(username,updated,added) values('$USERNAME',NOW(),NOW()) ON DUPLICATE KEY UPDATE UPDATED=NOW();
EOF
}

UPDATE_ENDPOINT ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $ENDPOINT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET updated=NOW(),logon_check=NOW() WHERE id='$ENDPOINT_ID';
EOF
}

UPDATE_MYSQL_NO_PING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $ENDPOINT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET updated=NOW(),logon_check=NOW() WHERE ip='$IP';
EOF
}

UPDATE_MYSQL_WINDOWS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $LOGON_TABLE table"${RESET} >> $LOG
MYSQL_EXIST=
MYSQL_EXIST=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$LOGON_TABLE WHERE user_id='$USER_ID' AND endpoint_id='$ENDPOINT_ID';"`
if [[ -n "$MYSQL_EXIST" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating ID $MYSQL_EXIST in the $LOGON_TABLE table"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}UPDATE $LOGON_TABLE SET logon_time='$LAST_LOGON',updated=NOW() WHERE id='$MYSQL_EXIST';"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $LOGON_TABLE SET logon_time='$LAST_LOGON',updated=NOW() WHERE id='$MYSQL_EXIST';
EOF
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $IP to the $LOGON_TABLE table"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INSERT INTO $LOGON_TABLE(logon_time,user_id,endpoint_id,added,updated) VALUES('$LAST_LOGON','$USER_ID','$ENDPOINT_ID',NOW(),NOW());"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $LOGON_TABLE(logon_time,user_id,endpoint_id,added,updated) VALUES('$LAST_LOGON','$USER_ID','$ENDPOINT_ID',NOW(),NOW());
EOF
fi
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked"${RESET} >> $LOG

MANUAL_RUN=

if [[ -z "$IPS" ]]
	then
		IP_SELECT=$IP_SELECT
		GET_IPS
	else
		MANUAL_RUN="1"
fi
if [[ -z "$IPS" ]]
	then
		if [[ -n "$ENDPOINT_IPS" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking $COUNT_PER_RUN endpoints out of $NUMBER_OF_ENDPOINT_IPS"${RESET} >> $LOG
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs or Hostnames provided"${RESET} >> $LOG
				echo
				EXIT_CODE="85"
				EXIT_FUNCTION
		fi
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Script has been manually run"${RESET} >> $LOG
fi

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking windows endpoints"${RESET} >> $LOG
if [[ -z "$MANUAL_RUN" ]]
	then
		IPS=$ENDPOINT_IPS
fi
for IP in $IPS
	do
		if ping -c 1 -W 1 -i 0.2 $IP &> /dev/null
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
				GET_ENDPOINT_ID
				if [[ -z "$ENDPOINT_ID" ]]
					then
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP does not exist in the database"${RESET} >> $LOG
						continue
				fi
				UPDATE_ENDPOINT
				GET_LOGONS
				for USERNAME in $USERNAMES		
					do
						LOGON_TIME
						if [[ -n "$USERNAME" ]]
							then
								GET_USER_ID
								UPDATE_MYSQL_WINDOWS
						fi
				done
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable"${RESET} >> $LOG
				UPDATE_MYSQL_NO_PING
		fi
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
