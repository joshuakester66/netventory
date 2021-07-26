#!/bin/bash
#Filename: netventory.network_discover.sh
#Description: 
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# ipcalc
# mariadb-server/mysqld
# net-snmp
# net-snmp-utils
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

IPS=$1

SCRIPT_NAME="netventory.network_discover"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | egrep ^mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | egrep ^mysql_password: | sed 's/mysql_password://g')
SNMP_TABLE="snmp"
SNMP_TIMEOUT="0.2"
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
NETWORK_TABLE="network"
CIDR_TABLE="cidr"
OID_TABLE="oid"
INTERFACE_TABLE="interface"
IP_COLUMN="ip"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
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
NUMBER_OF_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 30 DAY) AND ip NOT LIKE '169.%.%.%' ORDER BY network_check,ip;"`
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 30 DAY) AND ip NOT LIKE '169.%.%.%' ORDER BY network_check,ip LIMIT $DEVICES_PER_RUN;"`
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

GET_SNMP_CREDS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the SNMP credentials for $IP"${RESET} >> $LOG
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
}

GET_NETWORKS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the networks on this device via SNMP"${RESET} >> $LOG
OID_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $OID_TABLE.network,$OID_TABLE.network_int FROM $LOCAL_DATABASE.$OID_TABLE LEFT JOIN $LOCAL_DATABASE.$DEVICE_TABLE ON $LOCAL_DATABASE.$OID_TABLE.id=$DEVICE_TABLE.oid_id WHERE $DEVICE_TABLE.id='$DEVICE_ID';"`)
OID_NETWORK=${OID_ARRAY[0]}
OID_INTERFACE=${OID_ARRAY[1]}
NETWORK_SUBNETS=
NETWORK_SUBNETS=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -O q $IP $OID_NETWORK | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\s255\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | sed 's/ /\//g' | egrep --color=never --invert-match '^127.+' | egrep --color=never --invert-match '^169.+')
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
for NETWORK_SUBNET in $NETWORK_SUBNETS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on $NETWORK_SUBNET"${RESET} >> $LOG
		NETWORK=
		SUBNET_MASK=
		INT_ALIAS=
		NETWORK_NAME=
		VLAN=
		NETWORK=$(echo "$NETWORK_SUBNET" | egrep --color=never -o '^.+/' | sed 's/\///g')
		SUBNET_MASK=$(echo "$NETWORK_SUBNET" | egrep --color=never -o '/.+$' | sed 's/\///g')
		GET_USABLE_IPS
		INTERFACE=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -O qv $IP $OID_INTERFACE.$NETWORK)
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface: $INTERFACE"${RESET} >> $LOG
		NETWORK=$(ipcalc --network $NETWORK $SUBNET_MASK 2> /dev/null | sed 's/^NETWORK=//g' | sed '/Unknown option/d')
		if [[ -z "$NETWORK" ]]
			then
				NETWORK=$(echo "$NETWORK_SUBNET" | egrep --color=never -o '^.+/' | sed 's/\///g')
				NETWORK=$(ipcalc $NETWORK $SUBNET_MASK 2> /dev/null | grep --color=never "Network: " | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
		fi
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Network: $NETWORK"${RESET} >> $LOG
		LAN_TYPE=
		LAN_TYPE=$(echo "$NETWORK" | egrep --color=never '(^127\.)|(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.)')
		if [[ -z "$LAN_TYPE" ]]
			then
				LAN_TYPE='WAN'
			else
				LAN_TYPE='LAN'
		fi
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Lan Type: $LAN_TYPE"${RESET} >> $LOG
		UPDATE_DATABASE
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
done
}

GET_USABLE_IPS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the usable IPs"${RESET} >> $LOG
BROADCAST=$(ipcalc --broadcast $NETWORK $SUBNET_MASK 2> /dev/null | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sed '/Unknown option/d')
if [[ -z "$BROADCAST" ]]
	then
		BROADCAST=$(ipcalc $NETWORK $SUBNET_MASK 2> /dev/null | grep --color=never "Broadcast:" | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sed '/Unknown option/d')
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Broadcast: $BROADCAST"${RESET} >> $LOG
NETWORK_ID=$(ipcalc --network $NETWORK $SUBNET_MASK 2> /dev/null | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sed '/Unknown option/d')
if [[ -z "$NETWORK_ID" ]]
	then
		NETWORK_ID=$(ipcalc $NETWORK $SUBNET_MASK 2> /dev/null | grep --color=never "Network:" | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sed '/Unknown option/d')
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Network ID: $NETWORK_ID"${RESET} >> $LOG
SUBNET_SHORT=$(echo "$NETWORK_ID" | egrep --color=never -o '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.' | sed 's/\.$//g')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Subnet Short: $SUBNET_SHORT"${RESET} >> $LOG
LAST_OCTET=$(echo "$NETWORK_ID" | egrep --color=never -o '\.[0-9]{1,3}$' | sed 's/\.//g')
let LAST_OCTET+=1
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Last Octet: $LAST_OCTET"${RESET} >> $LOG
FIRST_USABLE=$SUBNET_SHORT.$LAST_OCTET
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}First Usable: $FIRST_USABLE"${RESET} >> $LOG
SUBNET_SHORT=$(echo "$BROADCAST" | egrep --color=never -o '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.' | sed 's/\.$//g')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Subnet Short: $SUBNET_SHORT"${RESET} >> $LOG
LAST_OCTET=$(echo "$BROADCAST" | egrep --color=never -o '\.[0-9]{1,3}$' | sed 's/\.//g')
let LAST_OCTET-=1
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Last Octet: $LAST_OCTET"${RESET} >> $LOG
LAST_USABLE=$SUBNET_SHORT.$LAST_OCTET
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Last Usable: $LAST_USABLE"${RESET} >> $LOG
}

GET_ROUTES ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the routes on this device via SNMP"${RESET} >> $LOG
OID_ROUTE=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $OID_TABLE.route FROM $LOCAL_DATABASE.$OID_TABLE LEFT JOIN $LOCAL_DATABASE.$DEVICE_TABLE ON $LOCAL_DATABASE.$OID_TABLE.id=$DEVICE_TABLE.oid_id WHERE $DEVICE_TABLE.id='$DEVICE_ID';"`
NETWORK_SUBNETS=
NETWORK_SUBNETS=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -O q $IP $OID_ROUTE.11 | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\s255\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | sed 's/ /\//g' | egrep --color=never -E '(^10\.|^192\.168\.|^172\.[123][0-9]\.)' | egrep --color=never --invert-match '255.255.255.255')
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
for NETWORK_SUBNET in $NETWORK_SUBNETS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on $NETWORK_SUBNET"${RESET} >> $LOG
		NETWORK=
		SUBNET_MASK=
		VLAN=
		INTERFACE=
		NETWORK=$(echo "$NETWORK_SUBNET" | egrep --color=never -o '^.+/' | sed 's/\///g')
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Network: $NETWORK"${RESET} >> $LOG
		SUBNET_MASK=$(echo "$NETWORK_SUBNET" | egrep --color=never -o '/.+$' | sed 's/\///g')
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Subnet Mask: $SUBNET_MASK"${RESET} >> $LOG
		GET_USABLE_IPS
		NETWORK=$(ipcalc --network $NETWORK $SUBNET_MASK 2> /dev/null | sed 's/^NETWORK=//g' | sed '/Unknown option/d')
		if [[ -z "$NETWORK" ]]
			then
				NETWORK=$(echo "$NETWORK_SUBNET" | egrep --color=never -o '^.+/' | sed 's/\///g')
				NETWORK=$(ipcalc $NETWORK $SUBNET_MASK 2> /dev/null | grep --color=never "Network: " | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
		fi
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Network: $NETWORK"${RESET} >> $LOG
		INTERFACE=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -O qv $IP $OID_ROUTE.2.$NETWORK)
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface: $INTERFACE"${RESET} >> $LOG
		LAN_TYPE="route"
		UPDATE_DATABASE
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
done
}

UPDATE_DATABASE ()
{
CIDR_ID=
NETWORK_ID=
SUBNET_NAME=
CIDR_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$CIDR_TABLE WHERE subnet_mask='$SUBNET_MASK';"`
NETWORK_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE network='$NETWORK' AND device_id='$DEVICE_ID' AND cidr_id='$CIDR_ID' AND type='$LAN_TYPE';"`
SUBNET_NAME=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT port_alias FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE port='$INTERFACE' AND device_id='$DEVICE_ID';"`
if [[ -z "$SUBNET_NAME" ]]
	then
		SUBNET_NAME=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT subnet_name FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE network='$NETWORK' AND cidr_id='$CIDR_ID' ORDER BY updated DESC LIMIT 1;"`
fi
if [[ -z "$NETWORK_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $NETWORK/$CIDR_ID to the database"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $NETWORK_TABLE(network,device_id,cidr_id,type,location_id,interface_id,subnet_name,first_usable,last_usable,updated,added) VALUES('$NETWORK','$DEVICE_ID','$CIDR_ID','$LAN_TYPE',(SELECT location_id FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT id FROM $INTERFACE_TABLE WHERE port='$INTERFACE' AND device_id='$DEVICE_ID'),'$SUBNET_NAME','$FIRST_USABLE','$LAST_USABLE',NOW(),NOW());
EOF
# INSERT INTO $NETWORK_TABLE(network,device_id,cidr_id,type,location_id,interface_id,subnet_name,first_usable,last_usable,updated,added) VALUES('$NETWORK','$DEVICE_ID','$CIDR_ID','$LAN_TYPE',(SELECT location_id FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT id FROM $INTERFACE_TABLE WHERE port='$INTERFACE' AND device_id='$DEVICE_ID'),(SELECT port_alias FROM $INTERFACE_TABLE WHERE port='$INTERFACE' AND device_id='$DEVICE_ID'),'$FIRST_USABLE','$LAST_USABLE',NOW(),NOW());
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating $NETWORK/$CIDR_ID in the database"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $NETWORK_TABLE SET device_id='$DEVICE_ID',cidr_id='$CIDR_ID',type='$LAN_TYPE',location_id=(SELECT location_id FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),interface_id=(SELECT id FROM $INTERFACE_TABLE WHERE port='$INTERFACE' AND device_id='$DEVICE_ID'),subnet_name='$SUBNET_NAME',first_usable='$FIRST_USABLE',last_usable='$LAST_USABLE',updated='$TODAY' WHERE id='$NETWORK_ID';
EOF
fi
# UPDATE $NETWORK_TABLE SET device_id='$DEVICE_ID',cidr_id='$CIDR_ID',type='$LAN_TYPE',location_id=(SELECT location_id FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),interface_id=(SELECT id FROM $INTERFACE_TABLE WHERE port='$INTERFACE' AND device_id='$DEVICE_ID'),subnet_name=(SELECT port_alias FROM $INTERFACE_TABLE WHERE port='$INTERFACE' AND device_id='$DEVICE_ID'),first_usable='$FIRST_USABLE',last_usable='$LAST_USABLE',updated='$TODAY' WHERE id='$NETWORK_ID';
}

UPDATE_DEVICE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $DEVICE_TABLE for $IP"${RESET} >> $LOG
SYSNAME=$(echo "$SYSNAME" | sed "s/'//g")
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DEVICE_TABLE SET ping_check=NOW(),network_check=NOW(),updated=NOW() WHERE id='$DEVICE_ID';
EOF
}

UPDATE_DEVICE_NO_PING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $DEVICE_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DEVICE_TABLE SET network_check=NOW(),updated=NOW() WHERE ip='$IP';
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
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking $DEVICES_PER_RUN devices out of $NUMBER_OF_IPS"${RESET} >> $LOG
fi

for IP in $IPS
	do
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking $IP"${RESET} >> $LOG
		if ping -c 1 -W 1 -i 0.2 $IP &> /dev/null
			then
				GET_DEVICE_ID
				GET_SNMP_CREDS
				GET_NETWORKS
				GET_ROUTES
				UPDATE_DEVICE
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable"${RESET} >> $LOG
				UPDATE_DEVICE_NO_PING
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
		fi
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
