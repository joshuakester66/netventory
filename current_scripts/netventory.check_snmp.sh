#!/bin/bash
#Filename: netventory.check_snmp.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# net-snmp
# net-snmp-utils
# procmail (lockfile command)
# netcat

# read -p "Press any key to continue. " DEBUG #DEUBG

IPS=$1

SCRIPT_NAME="netventory.check_snmp"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | egrep ^mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | egrep ^mysql_password: | sed 's/mysql_password://g')
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
TABLE_ARRAY=($DEVICE_TABLE $ENDPOINT_TABLE)
OID_TABLE="oid"
SNMP_TABLE="snmp"
ARP_TABLE="arp"
ADDRESS_TABLE="ipv4_addresses"
SNMP_TIMEOUT="0.2"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
COUNT_PER_RUN="50"
SNMP_PORT="161"

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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the device IPs"${RESET} >> $LOG
NUMBER_OF_DEVICE_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE (ping_check > (NOW() - INTERVAL 7 DAY)) AND (ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '169.%.%.%' ORDER BY snmp_check,ip;"`
DEVICE_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE (ping_check > (NOW() - INTERVAL 7 DAY)) AND (ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '169.%.%.%' ORDER BY snmp_check,ip LIMIT $COUNT_PER_RUN;"`
NUMBER_OF_ENDPOINT_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE (ping_check > (NOW() - INTERVAL 7 DAY)) AND (ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '169.%.%.%' ORDER BY snmp_check,ip;"`
ENDPOINT_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE (ping_check > (NOW() - INTERVAL 7 DAY)) AND (ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '169.%.%.%' ORDER BY snmp_check,ip LIMIT $COUNT_PER_RUN;"`
}

SNMP_CHECK ()
{
for IP in $IPS
	do
		if ping -c 1 -W 1 -i 0.2 $IP &> /dev/null
			then
				CURRENT_ID="${CURRENT_TABLE^^}"
				GET_${CURRENT_ID}_ID
				if [[ -z "$DEVICE_ID" ]]
					then
						DEVICE_ID=$ENDPOINT_ID
				fi
				GET_INFO
				if [[ "$SNMP_ENABLED" == "1" ]]
					then
						GET_SNMP_CREDS
						CHECK_SNMP
						if [[ -n "$SYSNAME" ]]
							then
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SNMP credentials were successful"${RESET} >> $LOG
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Sysname: $SYSNAME"${RESET} >> $LOG
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
								UPDATE_DATABASE
							else
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SNMP credentials failed"${RESET} >> $LOG
								SNMP_IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$SNMP_TABLE WHERE id!='$SNMP_ID';"`
								ITERATE_SNMP
								UPDATE_DATABASE
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
						fi
					else
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}testing $IP for SNMP"${RESET} >> $LOG
						# TEST_SNMP_PORT=$(nc -vz -u $IP $SNMP_PORT | grep --color=never "succ")
						# if [[ -n "$TEST_SNMP_PORT" ]]
						# 	then
								# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is listening for SNMP"${RESET} >> $LOG
								SNMP_IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$SNMP_TABLE;"`
								ITERATE_SNMP
								UPDATE_DATABASE
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
						# 	else
						# 		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is not listening for SNMP"${RESET} >> $LOG
						# 		UPDATE_DATABASE_NO_PING
						# 		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
						# fi
				fi
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable"${RESET} >> $LOG
				UPDATE_DATABASE_NO_PING
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
		fi
done
}

GET_DEVICE_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the device ID for $IP"${RESET} >> $LOG
DEVICE_ID=
DEVICE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
if [[ -z "$DEVICE_ID" ]]
	then
		ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
fi
if [[ -n "$ENDPOINT_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is an endpoint. Moving on"${RESET} >> $LOG
		continue
fi
if [[ -z "$DEVICE_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP does not exist in the database yet. Adding it"${RESET} >> $LOG
		ADD_DEVICE
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the new device ID"${RESET} >> $LOG
		DEVICE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Device ID: $DEVICE_ID"${RESET} >> $LOG
}

ADD_DEVICE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the device to the $DEVICE_TABLE table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $DEVICE_TABLE(ip,ping_check,updated,added) VALUES('$IP',CURDATE(),NOW(),NOW());
EOF
}

GET_ENDPOINT_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint ID for $IP"${RESET} >> $LOG
ENDPOINT_ID=
ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
if [[ -z "$ENDPOINT_ID" ]]
	then
		DEVICE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
fi
if [[ -n "$DEVICE_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is a device. Moving on"${RESET} >> $LOG
		continue
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
}

GET_INFO ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the $CURRENT_TABLE info for $IP"${RESET} >> $LOG
INFO_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT snmp_id,snmp_enabled FROM $LOCAL_DATABASE.$CURRENT_TABLE WHERE ip='$IP';"`)
SNMP_ID=${INFO_ARRAY[0]}
SNMP_ENABLED=${INFO_ARRAY[1]}
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$CURRENT_TABLE ID: $DEVICE_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SNMP ID: $SNMP_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SNMP Enabled: $SNMP_ENABLED"${RESET} >> $LOG
}

GET_SNMP_CREDS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the SNMP credentials for SNMP ID: $SNMP_ID"${RESET} >> $LOG
# read -p "Press any key to continue. Device ID: $DEVICE_ID " DEBUG
SNMP_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $SNMP_TABLE.community,$SNMP_TABLE.authlevel,$SNMP_TABLE.authname,$SNMP_TABLE.authpass,$SNMP_TABLE.authalgo,$SNMP_TABLE.cryptopass,$SNMP_TABLE.cryptoalgo,$SNMP_TABLE.version,$SNMP_TABLE.port FROM $LOCAL_DATABASE.$SNMP_TABLE WHERE $SNMP_TABLE.id='$SNMP_ID';"`)
SNMP_COMMUNITY=${SNMP_ARRAY[0]}
SNMP_AUTHLEVEL=${SNMP_ARRAY[1]}
SNMP_AUTHNAME=${SNMP_ARRAY[2]}
SNMP_AUTHPASS=${SNMP_ARRAY[3]}
SNMP_AUTHALGO=${SNMP_ARRAY[4]}
SNMP_CRYPTOPASS=${SNMP_ARRAY[5]}
SNMP_CRYPTOALGO=${SNMP_ARRAY[6]}
SNMP_VERSION=${SNMP_ARRAY[7]}
SNMP_PORT=${SNMP_ARRAY[8]}
if [[ "$SNMP_VERSION" == "3" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}SNMP Version 3 needs to be fixed"${RESET} >> $LOG
fi
# read -p "Press any key to continue. IP: $IP " DEBUG
}

CHECK_SNMP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking SNMP ID $SNMP_ID on $IP"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SNMP Version: $SNMP_VERSION"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SNMP community: $SNMP_COMMUNITY"${RESET} >> $LOG
OID_SYSNAME=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT sysname FROM $LOCAL_DATABASE.$OID_TABLE LIMIT 1;"`
SYSNAME=
SYSNAME=$(snmpget -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_SYSNAME 2> /dev/null)
}

ITERATE_SNMP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
for SNMP_ID in $SNMP_IDS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Testing SNMP ID $SNMP_ID"${RESET} >> $LOG
		GET_SNMP_CREDS
		CHECK_SNMP
		if [[ -n "$SYSNAME" ]]
			then
				SNMP_ENABLED="1"
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SNMP credentials successful"${RESET} >> $LOG
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Sysname: $SYSNAME"${RESET} >> $LOG
				break
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SNMP credentials failed"${RESET} >> $LOG
		fi
done
if [[ -z "$SYSNAME" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Could not connect to $IP via SNMP"${RESET} >> $LOG
		SNMP_ENABLED="0"
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
}

UPDATE_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE for $IP"${RESET} >> $LOG
SYSNAME=$(echo "$SYSNAME" | sed "s/'//g")
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE SET sysname='$SYSNAME',snmp_id='$SNMP_ID',snmp_enabled='$SNMP_ENABLED',ping_check=NOW(),snmp_check=NOW(),updated=NOW() WHERE id='$DEVICE_ID';
EOF
}

UPDATE_DATABASE_NO_PING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE SET snmp_check=NOW(),updated=NOW() WHERE ip='$IP';
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked"${RESET} >> $LOG

MANUAL_RUN=

if [[ -z "$IPS" ]]
	then
		GET_IPS
	else
		MANUAL_RUN="1"
fi
if [[ -z "$IPS" ]]
	then
		if [[ -n "$DEVICE_IPS" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking $COUNT_PER_RUN devices out of $NUMBER_OF_DEVICE_IPS"${RESET} >> $LOG
				if [[ -n "$ENDPOINT_IPS" ]]
					then
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking $COUNT_PER_RUN endpoints out of $NUMBER_OF_ENDPOINT_IPS"${RESET} >> $LOG
				fi
			else
				if [[ -n "$ENDPOINT_IPS" ]]
					then
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking $COUNT_PER_RUN endpoints out of $NUMBER_OF_ENDPOINT_IPS"${RESET} >> $LOG
					else
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs or Hostnames provided"${RESET} >> $LOG
						echo
						EXIT_CODE="85"
						EXIT_FUNCTION
				fi
		fi
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Script has been manually run"${RESET} >> $LOG
fi

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG

if [[ -z "$MANUAL_RUN" ]]
	then
		IPS=$DEVICE_IPS
fi
CURRENT_TABLE=$DEVICE_TABLE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on Devices"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
SNMP_CHECK

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG

if [[ -z "$MANUAL_RUN" ]]
	then
		IPS=$ENDPOINT_IPS
fi
CURRENT_TABLE=$ENDPOINT_TABLE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on Endpoints"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
SNMP_CHECK

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
