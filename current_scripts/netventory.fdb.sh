#!/bin/bash
#Filename: netventory.fdb.sh
#Description: 
# This script gets the fdb table or mac address table for the given IP addresses via SNMP
# it then updates the database
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# net-snmp
# net-snmp-utils
# procmail (lockfile command)
# bc

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="netventory.fdb"
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
SNMP_TABLE="snmp"
SNMP_TIMEOUT="5"
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
FDB_TABLE="fdb"
OID_TABLE="oid"
INTERFACE_TABLE="interface"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
FDB_FILE="$WORKING_DIR/fdb"
DEVICES_PER_RUN="20"
COUNT_DIVISION="12"
MACS_PER_PORT="5"

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
NUMBER_OF_DEVICES=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping > (NOW() - INTERVAL 30 DAY) AND category='network' ORDER BY fdb_check,ip;"`
COUNT_PER_RUN=$(expr $NUMBER_OF_DEVICES / $COUNT_DIVISION)
if [[ "$COUNT_PER_RUN" == "0" ]]
	then
		COUNT_PER_RUN=$NUMBER_OF_DEVICES
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$NUMBER_OF_DEVICES total eligible devices found"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting up to $COUNT_PER_RUN device IPs"${RESET} >> $LOG
# IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping > (NOW() - INTERVAL 30 DAY) AND category='network' AND (type='switch' OR type='firewall' OR type='router') ORDER BY vlan_check LIMIT $COUNT_PER_RUN;"`
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping > (NOW() - INTERVAL 30 DAY) AND category='network' ORDER BY fdb_check,ip LIMIT $COUNT_PER_RUN;"`
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the device IPs"${RESET} >> $LOG
# NUMBER_OF_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping > (NOW() - INTERVAL 30 DAY) AND category='network' ORDER BY fdb_check,ip;"`
# IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping > (NOW() - INTERVAL 30 DAY) AND category='network' ORDER BY fdb_check,ip LIMIT $DEVICES_PER_RUN;"`
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
INSERT INTO $DEVICE_TABLE(ip,ping_check,ping,updated,added) VALUES('$IP',NOW(),NOW(),NOW(),NOW());
EOF
}

GET_IDS ()
{
OID_ID=
OID_FDB=
OID_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT oid_id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE id='$DEVICE_ID';"`
OID_FDB=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT fdb FROM $LOCAL_DATABASE.$OID_TABLE WHERE id='$OID_ID';"`
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

GET_FILE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the fdb file"${RESET} >> $LOG
snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_FDB | egrep --color -o '\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s=\s.+$' | sed 's/\s=\sINTEGER: /;;/g' | sed 's/^\.//g' > $FDB_FILE.$IP
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking for uplinks"${RESET} >> $LOG
PORTS=$(cat $FDB_FILE.$IP | sed 's/^.*;;//g' | sort --unique)
	for PORT in $PORTS
		do
			PORT_COUNT=$(cat $FDB_FILE.$IP | egrep --color=never ";;$PORT$" | wc -l)
			if [[ "$PORT_COUNT" -gt "$MACS_PER_PORT" ]]
				then
					echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Removing Port $PORT from the file since it has $PORT_COUNT macs and only $MACS_PER_PORT are allowed"${RESET} >> $LOG
					sed -i "/;;$PORT\$/d" $FDB_FILE.$IP
					INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE device_id='$DEVICE_ID' AND port='$PORT';"`
					if [[ -n "$INTERFACE_ID" ]]
						then
							echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating $INTERFACE_ID in the $INTERFACE_TABLE table as an uplink"${RESET} >> $LOG
							mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $INTERFACE_TABLE SET uplink='Y',updated=NOW() WHERE id='$INTERFACE_ID';
EOF
					fi
			fi
done
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Removing port 0 since that is the system MAC address for the device"${RESET} >> $LOG
sed -i '/;;0$/d' $FDB_FILE.$IP
}

GET_INFO_UPDATE ()
{
MAC_DECIMAL=
MAC_DECIMALS=$(cat $FDB_FILE.$IP | egrep --color -o '.+;;' | sed 's/;//g')
for MAC_DECIMAL in $MAC_DECIMALS
	do
		PORT=
		INTERFACE_ID=
		MAC=
		MAC_TEMP=
		MAC_DECIMAL_TEMP=
		PORT=$(cat $FDB_FILE.$IP | egrep --color=never "^$MAC_DECIMAL;;" | egrep --color=never -o ';;.+$' | sed 's/;//g')
		INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE device_id='$DEVICE_ID' AND port='$PORT';"`
		if [[ -z "$INTERFACE_ID" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Skipping $PORT since there is no matching interface in the database"${RESET} >> $LOG
				continue
		fi
		MAC_DECIMAL_TEMP=$(echo $MAC_DECIMAL | sed 's/\./ /g')
		for MAC_TEMP in $MAC_DECIMAL_TEMP
			do
				MAC_TEMP=$(echo "obase=16; $MAC_TEMP" | bc)
				MAC_TEMP_COUNT=$(echo -n "$MAC_TEMP" | wc -c)
				if [[ "$MAC_TEMP_COUNT" -le "1" ]]
					then
						MAC_TEMP="0$MAC_TEMP"
				fi
				if [[ -z "$MAC" ]]
					then
						MAC="$MAC_TEMP"
					else
						MAC="$MAC:$MAC_TEMP"
				fi
		done
		MAC="${MAC,,}"
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP: $IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port: $PORT"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Device ID: $DEVICE_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface ID: $INTERFACE_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}MAC Address: $MAC"${RESET} >> $LOG
		UPDATE_MYSQL
done
}

UPDATE_MYSQL ()
{
FDB_ID=
FDB_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$FDB_TABLE WHERE device_id='$DEVICE_ID' AND interface_id='$INTERFACE_ID' AND mac='$MAC';"`
if [[ -z "$FDB_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $MAC to the database"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $FDB_TABLE(device_id,interface_id,mac,updated,added) VALUES('$DEVICE_ID','$INTERFACE_ID','$MAC',NOW(),NOW());
EOF
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating $MAC in the database"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $FDB_TABLE SET updated=NOW() WHERE id='$FDB_ID';
EOF
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating $INTERFACE_ID in the $INTERFACE_TABLE table as a non-uplink"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $INTERFACE_TABLE SET uplink='N',updated=NOW() WHERE id='$INTERFACE_ID';
EOF
}

UPDATE_DEVICE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $DEVICE_TABLE table with ID $DEVICE_ID"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DEVICE_TABLE SET fdb_check=NOW(),ping_check=NOW(),ping=NOW() WHERE id='$DEVICE_ID';
EOF
}

UPDATE_DEVICE_NO_PING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $DEVICE_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DEVICE_TABLE SET fdb_check=NOW(),updated=NOW(),ping_check=NOW() WHERE ip='$IP';
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked"${RESET} >> $LOG

if [[ -z "$IPS" ]]
	then
		GET_IPS
fi
if [[ -z "$IPS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs or Hostnames provided"${RESET} >> $LOG
		echo
		# echo -e ${REDF}"No IPs or Hostnames provided. This script is exiting"${RESET}
		EXIT_CODE="85"
		EXIT_FUNCTION
	# else
	# 	echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking $DEVICES_PER_RUN devices out of $NUMBER_OF_IPS"${RESET} >> $LOG
fi

for IP in $IPS
	do
		if ping -c 1 -W 1 -i 0.2 $IP &> /dev/null
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Working on $IP"${RESET} >> $LOG
				GET_DEVICE_ID
				GET_IDS
				GET_SNMP_CREDS
				GET_FILE
				GET_INFO_UPDATE
				UPDATE_DEVICE
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is not reachable. Moving on"${RESET} >> $LOG
				UPDATE_DEVICE_NO_PING
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		fi
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
done


echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
