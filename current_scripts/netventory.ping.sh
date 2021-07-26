#!/bin/bash
#Filename: netventory.ping.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# nmap
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

IPS=$1

SCRIPT_NAME="netventory.ping"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
DATABASE_USERNAME=$(cat $CREDENTIALS | egrep ^mysql_username: | sed 's/mysql_username://g')
DATABASE_PASSWORD=$(cat $CREDENTIALS | egrep ^mysql_password: | sed 's/mysql_password://g')
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
TABLE_ARRAY=($DEVICE_TABLE $ENDPOINT_TABLE)
NETWORK_TABLE="network"
ADDRESS_TABLE="ipv4_addresses"
ARP_TABLE="arp"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
PING_DEVICE_FILE="$WORKING_DIR/device_ping_list"
PING_ENDPOINT_FILE="$WORKING_DIR/endpoint_ping_list"
PING_DEVICE_RESULT_FILE="$WORKING_DIR/device_ping_results"
PING_ENDPOINT_RESULT_FILE="$WORKING_DIR/endpoint_ping_results"
# COUNT_PER_RUN="50"
COUNT_DIVISION="12"

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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}script has been unlocked"${RESET} >> $LOG
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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}script has been unlocked"${RESET} >> $LOG
echo ""
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}$SCRIPT_NAME.sh has exited for error $EXIT_CODE"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG
# reset
exit $EXIT_CODE
}

GET_IPS ()
{
NUMBER_OF_DEVICES=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%' ORDER BY ping_check;"`
COUNT_PER_RUN=$(expr $NUMBER_OF_DEVICES / $COUNT_DIVISION)
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$NUMBER_OF_DEVICES total eligible devices found"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting up to $COUNT_PER_RUN device IPs"${RESET} >> $LOG
DEVICE_IPS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%' ORDER BY ping_check LIMIT $COUNT_PER_RUN;"`
echo "$DEVICE_IPS" > $PING_DEVICE_FILE
NUMBER_OF_ENDPOINTS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%' ORDER BY ping_check;"`
COUNT_PER_RUN=$(expr $NUMBER_OF_ENDPOINTS / $COUNT_DIVISION)
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$NUMBER_OF_ENDPOINTS total eligible endpoints found"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting up to $COUNT_PER_RUN endpoint IPs"${RESET} >> $LOG
ENDPOINT_IPS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%' ORDER BY ping_check LIMIT $COUNT_PER_RUN;"`
echo "$ENDPOINT_IPS" > $PING_ENDPOINT_FILE
}

PING_TIME_DEVICE ()
{
CURRENT_ID="${CURRENT_TABLE^^}"
fping -Ar 1 -f $PING_DEVICE_FILE | sed 's/ /_/g' > $PING_DEVICE_RESULT_FILE
for LINE in `cat $PING_DEVICE_RESULT_FILE`
	do
		ENDPOINT_ID=
		DEVICE_ID=
		IP=$(echo "$LINE" | egrep --color=never -o '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
		PING_STATUS=$(echo "$LINE" | egrep --color=never -o '[a-zA-Z]+$')
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		if [[ "$PING_STATUS" == "alive" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is reachable"${RESET} >> $LOG
				GET_${CURRENT_ID}_ID
				if [[ -z "$DEVICE_ID" ]]
					then
						DEVICE_ID=$ENDPOINT_ID
				fi
				UPDATE_DATABASE
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable"${RESET} >> $LOG
				UPDATE_DATABASE_NO_PING
		fi
done
}

PING_TIME_ENDPOINT ()
{
CURRENT_ID="${CURRENT_TABLE^^}"
fping -Ar 1 -f $PING_ENDPOINT_FILE |sed 's/ /_/g' > $PING_ENDPOINT_RESULT_FILE
for LINE in `cat $PING_ENDPOINT_RESULT_FILE`
	do
		ENDPOINT_ID=
		DEVICE_ID=
		IP=$(echo "$LINE" | egrep --color=never -o '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
		PING_STATUS=$(echo "$LINE" | egrep --color=never -o '[a-zA-Z]+$')
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on $IP"${RESET} >> $LOG
		if [[ "$PING_STATUS" == "alive" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is reachable"${RESET} >> $LOG
				GET_${CURRENT_ID}_ID
				if [[ -z "$DEVICE_ID" ]]
					then
						DEVICE_ID=$ENDPOINT_ID
				fi
				UPDATE_DATABASE
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable"${RESET} >> $LOG
				UPDATE_DATABASE_NO_PING
		fi
done
}

GET_DEVICE_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the device ID for $IP"${RESET} >> $LOG
DEVICE_ID=
ENDPOINT_ID=
DEVICE_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
if [[ -z "$DEVICE_ID" ]]
	then
		ENDPOINT_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
fi
if [[ -n "$ENDPOINT_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is an endpoint with Endpoint ID: $ENDPOINT_ID. Moving on"${RESET} >> $LOG
		continue
fi
if [[ -z "$DEVICE_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP does not exist in the database yet. Adding it"${RESET} >> $LOG
		ADD_DEVICE
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the new device ID"${RESET} >> $LOG
		DEVICE_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Device ID: $DEVICE_ID"${RESET} >> $LOG
}

ADD_DEVICE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the device to the $DEVICE_TABLE table"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $DEVICE_TABLE(ip,updated,added) VALUES('$IP',NOW(),NOW());
EOF
}

GET_ENDPOINT_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint ID for $IP"${RESET} >> $LOG
ENDPOINT_ID=
ENDPOINT_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
if [[ -z "$ENDPOINT_ID" ]]
	then
		DEVICE_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
		if [[ -z "$DEVICE_ID" ]]
			then
				ADD_DEVICE
				DEVICE_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is a device with Device ID: $DEVICE_ID. Moving on"${RESET} >> $LOG
				continue
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is a device with Device ID: $DEVICE_ID. Moving on"${RESET} >> $LOG
				continue
		fi
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
}

UPDATE_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE table for $IP with ID $DEVICE_ID"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE SET ping=NOW(),ping_check=NOW(),updated=NOW() WHERE id='$DEVICE_ID';
EOF
}

UPDATE_DATABASE_NO_PING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE SET ping_check=NOW(),updated=NOW() WHERE ip='$IP';
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the script for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}script has been locked"${RESET} >> $LOG

MANUAL_RUN=

if [[ -z "$IPS" ]]
	then
		GET_IPS
	else
		MANUAL_RUN="1"
		echo "$IPS" | tr ' ' '\n' > $PING_DEVICE_FILE
		echo "$IPS" | tr ' ' '\n' > $PING_ENDPOINT_FILE
fi
if [[ -z "$IPS" ]]
	then
		if [[ -z "$DEVICE_IPS" ]]
			then
				if [[ -z "$ENDPOINT_IPS" ]]
					then
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs or Hostnames provided"${RESET} >> $LOG
						echo
						EXIT_CODE="85"
						EXIT_FUNCTION
				fi
		fi
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Script has been manually run"${RESET} >> $LOG
fi

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG

# if [[ -z "$MANUAL_RUN" ]]
# 	then
# 		IPS=$DEVICE_IPS
# fi
CURRENT_TABLE=$DEVICE_TABLE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on Devices"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
PING_TIME_DEVICE

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG

# if [[ -z "$MANUAL_RUN" ]]
# 	then
# 		IPS=$ENDPOINT_IPS
# fi
CURRENT_TABLE=$ENDPOINT_TABLE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on Endpoints"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
PING_TIME_ENDPOINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the script"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
