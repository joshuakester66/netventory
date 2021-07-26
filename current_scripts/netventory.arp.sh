#!/bin/bash
#Filename: netventory.arp.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# net-snmp
# net-snmp-utils
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="netventory.arp"
SCRIPT_CAT="netventory"

IPS=$1

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | egrep ^mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | egrep ^mysql_password: | sed 's/mysql_password://g')
OID_TABLE="oid"
SNMP_TABLE="snmp"
SNMP_TIMEOUT="5"
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
ARP_TABLE="arp"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
ARP_FILE_BASE="$WORKING_DIR/arp"

LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
DEVICES_PER_RUN="50"

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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been unlocked."${RESET} >> $LOG
echo ""
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}$SCRIPT_NAME.sh was cancelled."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG
# reset
exit 99
}

SCRIPT_RUNNING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Script is currently running. Exiting."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG
exit 95
}

EXIT_FUNCTION ()
{
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been unlocked."${RESET} >> $LOG
echo ""
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}$SCRIPT_NAME.sh has exited for error $EXIT_CODE."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG
# reset
exit $EXIT_CODE
}

GET_IPS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the device IPs"${RESET} >> $LOG
NUMBER_OF_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping > (NOW() - INTERVAL 7 DAY) AND (ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') ORDER BY arp_check,ip;"`
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping > (NOW() - INTERVAL 7 DAY) AND (ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') ORDER BY arp_check,ip LIMIT $DEVICES_PER_RUN;"`
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
INSERT INTO $DEVICE_TABLE(ip,added) VALUES('$IP',NOW());
EOF
}

GET_SNMP_CREDS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the SNMP credentials for $IP"${RESET} >> $LOG
# read -p "Press any key to continue. Device ID: $DEVICE_ID " DEBUG
SNMP_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $SNMP_TABLE.community,$SNMP_TABLE.authlevel,$SNMP_TABLE.authname,$SNMP_TABLE.authpass,$SNMP_TABLE.authalgo,$SNMP_TABLE.cryptopass,$SNMP_TABLE.cryptoalgo,$SNMP_TABLE.version,$SNMP_TABLE.port FROM $LOCAL_DATABASE.$SNMP_TABLE LEFT JOIN $LOCAL_DATABASE.$DEVICE_TABLE ON $SNMP_TABLE.id=$DEVICE_TABLE.snmp_id WHERE $DEVICE_TABLE.id='$DEVICE_ID';"`)
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

GET_ARP ()
{
ARP_FILE=
ARP_FILE=$ARP_FILE_BASE.$IP
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the necessary information for $IP"${RESET} >> $LOG
OID_ARP=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $OID_TABLE.arp FROM $LOCAL_DATABASE.$OID_TABLE LEFT JOIN $LOCAL_DATABASE.$DEVICE_TABLE ON $LOCAL_DATABASE.$OID_TABLE.id=$DEVICE_TABLE.oid_id WHERE $DEVICE_TABLE.id='$DEVICE_ID';"`
# ARP=
# ARP=$(snmpwalk -O q -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_ARP | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\s[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}$' | sed 's/ /;;/g' | sed 's/;;\([0-9a-fA-F]\)\:/;;0\1:/g' | sed 's/\:\([0-9a-fA-F]\)$/:0\1/g' | sed 's/\:\([0-9a-fA-F]\)\:/:0\1:/g' | sed 's/\:\([0-9a-fA-F]\)\:/:0\1:/g')
snmpwalk -O qn -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_ARP | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\s(\")?[0-9a-fA-F]{1,2}[\: ][0-9a-fA-F]{1,2}[\: ][0-9a-fA-F]{1,2}[\: ][0-9a-fA-F]{1,2}[\: ][0-9a-fA-F]{1,2}[\: ][0-9a-fA-F]{1,2}' | sed "s/\([0-9]\) \(\"\)/\1;;\2/g" | sed 's/"//g' | sed 's/\(\.[0-9]\{1,3\}\)\s\([A-Fa-f0-9]\)/\1;;\2/g' | sed 's/ /:/g' | sed "s/\([0-9A-Fa-f]\) \([0-9A-Fa-f]\)/\1:\2/g" | sed 's/;;\([0-9a-fA-F]\)\:/;;0\1:/g' | sed 's/\:\([0-9a-fA-F]\)$/:0\1/g' | sed 's/\:\([0-9a-fA-F]\)\:/:0\1:/g' | sed 's/\:\([0-9a-fA-F]\)\:/:0\1:/g' | tr [:upper:] [:lower:] > $ARP_FILE
for LINE in `cat $ARP_FILE`
	do
		CLIENT_IP=
		CLIENT_IP=$(echo "$LINE" | egrep --color=never -o '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3};;' | sed 's/;;//g')
		CLIENT_MAC=
		CLIENT_MAC=$(echo "$LINE" | egrep --color=never -o ';;[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}$' | sed 's/;;//g')
		UPDATE_DATABASE_ARP
done
UPDATE_DEVICE
}

UPDATE_DATABASE_ARP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking for IP/MAC existing"${RESET} >> $LOG
ARP_ID=
ARP_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $ARP_TABLE.id FROM $LOCAL_DATABASE.$ARP_TABLE WHERE device_id='$DEVICE_ID' AND mac='$CLIENT_MAC';"`
if [[ -z "$ARP_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $CLIENT_IP and $CLIENT_MAC to the database"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $ARP_TABLE(device_id,ip,mac,updated,added) VALUES('$DEVICE_ID','$CLIENT_IP','$CLIENT_MAC',NOW(),NOW());
EOF
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating $CLIENT_IP and $CLIENT_MAC in the database"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ARP_TABLE SET ip='$CLIENT_IP',updated=NOW() WHERE id='$ARP_ID';
EOF
fi
}

UPDATE_DEVICE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the interface with ID $INTERFACE_ID"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DEVICE_TABLE SET ping=NOW(),ping_check=NOW(),arp_check=NOW() WHERE id='$DEVICE_ID';
EOF
}

UPDATE_DEVICE_NO_PING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $DEVICE_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DEVICE_TABLE SET arp_check=NOW(),ping_check=NOW(),updated=NOW() WHERE ip='$IP';
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started."${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution."${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked."${RESET} >> $LOG

if [[ -z "$IPS" ]]
	then
		GET_IPS
fi
if [[ -z "$IPS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs or Hostnames provided"${RESET} >> $LOG
		echo
		# echo -e ${REDF}"No IPs or Hostnames provided. This script is exiting."${RESET}
		EXIT_CODE="85"
		EXIT_FUNCTION
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking $DEVICES_PER_RUN devices out of $NUMBER_OF_IPS"${RESET} >> $LOG
fi

echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
for IP in $IPS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking IP $IP"${RESET} >> $LOG
		if ping -c 1 -W 1 $IP &> /dev/null
			then
				GET_DEVICE_ID
				GET_SNMP_CREDS
				GET_ARP
				echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is not reachable. Moving on"${RESET} >> $LOG
				UPDATE_DEVICE_NO_PING
				echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		fi
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file."${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
