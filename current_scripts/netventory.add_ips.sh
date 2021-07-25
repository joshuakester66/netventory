#!/bin/bash
#Filename: netventory.add_ips.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# nmap
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

NETWORKS=$1

SCRIPT_NAME="netventory.add_ips"
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
NETWORK_TABLE="network"
ADDRESS_TABLE="ipv4_addresses"
ARP_TABLE="arp"
ROUTE_TABLE="routes"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/ip_file"
NMAP_FILE="$WORKING_DIR/nmap_file"
TEMP_FILE="$WORKING_DIR/temp_file"
PING_DEVICE_FILE="$WORKING_DIR/device_ping_list"
PING_DEVICE_RESULT_FILE="$WORKING_DIR/device_ping_results"
COUNT_PER_RUN="50"

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

GET_NETWORKS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the networks"${RESET} >> $LOG
NETWORK_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE type!='wan' GROUP BY concat(network,'/',cidr_id) ORDER BY network_check,network LIMIT $COUNT_PER_RUN;"`
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $NETWORK_TABLE set network_check=NOW() WHERE type!='wan' ORDER BY network_check,network LIMIT $COUNT_PER_RUN;
EOF
}

GET_SINGLE_NETWORK ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the network ID for NETWORK $NETWORK"${RESET} >> $LOG
NETWORK_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE type!='wan' AND CONCAT(network,'/',cidr_id)='$NETWORKS';"`
}

SCAN_NETWORKS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Going through the network IDs"${RESET} >> $LOG
for NETWORK_ID in $NETWORK_IDS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Going through network ID: $NETWORK_ID"${RESET} >> $LOG
		NETWORK=
		CIDR=
		# CIDR=$(echo "$NETWORK" | egrep --color -o '\/[0-9]{1,2}' | sed 's/\///g')
		CIDR=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT cidr_id FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE id='$NETWORK_ID';"`
		NETWORK=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT network FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE id='$NETWORK_ID';"`
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the IPS for $NETWORK/$CIDR"${RESET} >> $LOG
		if [[ "$CIDR" -lt "16" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$NETWORK/$CIDR is too large. Moving on"${RESET} >> $LOG
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
				continue
		fi
		if [[ "$CIDR" -lt "22" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$NETWORK/$CIDR is too large. Only looking for the gateways"${RESET} >> $LOG
				nmap -sL -n $NETWORK/$CIDR | egrep --color=never -o "(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])" | egrep --color=never '\.1$|\.2$|\.254$' > $NMAP_FILE
				cat $NMAP_FILE >> $FILE
				# rm -Rf $NMAP_FILE &> /dev/null
				# NETWORK_SHORT=
				# NETWORK_FIRST=
				# NETWORK_LAST=
				# NETWORK_SHORT=$(echo "$NETWORK" | sed 's/\.[0-9]\{1,3\}$//g' | sed 's/\.[0-9]\{1,3\}$//g')
				# NETWORK_FIRST=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT first_usable FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE id='$NETWORK_ID';"`
				# NETWORK_FIRST=$(echo "$NETWORK_FIRST" | sed 's/\.[0-9]\{1,3\}$//g' | sed 's/^[0-9]\{1,3\}\.//g' | sed 's/^[0-9]\{1,3\}\.//g')
				# NETWORK_LAST=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT last_usable FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE id='$NETWORK_ID';"`
				# NETWORK_LAST=$(echo "$NETWORK_LAST" | sed 's/\.[0-9]\{1,3\}$//g' | sed 's/^[0-9]\{1,3\}\.//g' | sed 's/^[0-9]\{1,3\}\.//g')
				# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Network start: $NETWORK_FIRST"${RESET} >> $LOG
				# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Network end: $NETWORK_LAST"${RESET} >> $LOG
				# COUNTER=$NETWORK_FIRST
				# while [[ "$COUNTER" -le "$NETWORK_LAST" ]]
				# 	do
				# 		echo "$NETWORK_SHORT.$COUNTER.1" >> $NMAP_FILE
				# 		echo "$NETWORK_SHORT.$COUNTER.2" >> $NMAP_FILE
				# 		echo "$NETWORK_SHORT.$COUNTER.254" >> $NMAP_FILE
				# 		echo "$NETWORK_SHORT.$COUNTER.255" >> $NMAP_FILE
						# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Pinging $NETWORK_SHORT.$COUNTER.1"${RESET} >> $LOG
						# if ping -c 1 -W 1 -i 0.2 $NETWORK_SHORT.$COUNTER.1 &> /dev/null
						# 	then
						# 		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $NETWORK_SHORT.$COUNTER.1"${RESET} >> $LOG
						# 		$NETWORK_SHORT.$COUNTER.1 >> $FILE
						# fi
						# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Pinging $NETWORK_SHORT.$COUNTER.2"${RESET} >> $LOG
						# if ping -c 1 -W 1 -i 0.2 $NETWORK_SHORT.$COUNTER.2 &> /dev/null
						# 	then
						# 		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $NETWORK_SHORT.$COUNTER.2"${RESET} >> $LOG
						# 		$NETWORK_SHORT.$COUNTER.1 >> $FILE
						# fi
						# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Pinging $NETWORK_SHORT.$COUNTER.254"${RESET} >> $LOG
						# if ping -c 1 -W 1 -i 0.2 $NETWORK_SHORT.$COUNTER.254 &> /dev/null
						# 	then
						# 		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $NETWORK_SHORT.$COUNTER.254"${RESET} >> $LOG
						# 		$NETWORK_SHORT.$COUNTER.1 >> $FILE
						# fi
						# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Pinging $NETWORK_SHORT.$COUNTER.255"${RESET} >> $LOG
						# if ping -c 1 -W 1 -i 0.2 $NETWORK_SHORT.$COUNTER.255 &> /dev/null
						# 	then
						# 		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $NETWORK_SHORT.$COUNTER.255"${RESET} >> $LOG
						# 		$NETWORK_SHORT.$COUNTER.1 >> $FILE
						# fi
						# let COUNTER+=1
						# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Counter: $COUNTER"${RESET} >> $LOG
				# done
				# nmap -sn -iL $NMAP_FILE | egrep --color=never -o "(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])" >> $FILE


			else
				# nmap -sn $NETWORK/$CIDR | egrep --color=never -o "(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])" >> $FILE
				nmap -sL -n $NETWORK/$CIDR | egrep --color=never -o "(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])" > $NMAP_FILE
				cat $NMAP_FILE >> $FILE
		fi
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
done
}

GET_ARP_IPS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the IPs from the $ARP_TABLE table and adding them to the file"${RESET} >> $LOG
ARP_IPS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT DISTINCT ip FROM $LOCAL_DATABASE.$ARP_TABLE WHERE (updated > (NOW() - INTERVAL 7 DAY)) ORDER BY ip;"`
echo "$ARP_IPS" >> $FILE
}

CLEANUP_DUPLICATES ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Cleaning up possible duplicates in the file"${RESET} >> $LOG
sort --unique --output=$FILE $FILE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Removing any public IP addresses"${RESET} >> $LOG
egrep --color=never '10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' $FILE > $TEMP_FILE
egrep --color=never '192\.168\.[0-9]{1,3}\.[0-9]{1,3}' $FILE >> $TEMP_FILE
egrep --color=never '172\.16\.[0-9]{1,3}\.[0-9]{1,3}' $FILE >> $TEMP_FILE
mv $TEMP_FILE $FILE &> /dev/null
}

CHECK_ALTERNATE_ADDRESSES ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Verifying whether $IP is an alternate IP address for an existing device"${RESET} >> $LOG
PARENT_DEVICE_ID=
PARENT_DEVICE_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT device_id FROM $LOCAL_DATABASE.$ADDRESS_TABLE WHERE ip='$IP';"`
if [[ -n "$PARENT_DEVICE_ID" ]]
	then
		PARENT_DEVICE_IP=
		PARENT_DEVICE_IP=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE id='$PARENT_DEVICE_ID';"`
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP belongs to an existing device with Device ID: $PARENT_DEVICE_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Device Primary IP is: $PARENT_DEVICE_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Moving on to the next IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
		continue
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is a unique device"${RESET} >> $LOG
fi
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
		UPDATE_ENDPOINT
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is an endpoint with Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INSERT INTO $DEVICE_TABLE(id,ip,added) VALUES(NULL,'$IP',NOW());"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $DEVICE_TABLE(ip,updated,added) VALUES('$IP',NOW(),NOW());
EOF
}

UPDATE_DEVICE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DEVICE_TABLE SET ping=NOW(),ping_check=NOW(),updated=NOW() WHERE id='$DEVICE_ID';
EOF
}

UPDATE_ENDPOINT ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET ping=NOW(),ping_check=NOW(),updated=NOW() WHERE id='$ENDPOINT_ID';
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the script for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}script has been locked"${RESET} >> $LOG

rm -Rf $FILE &> /dev/null

if [[ -z "$NETWORKS" ]]
	then
		SINGLE_NETWORK='0'
		GET_NETWORKS
		NETWORKS=$NETWORK_IDS
	else
		SINGLE_NETWORK='1'
		GET_SINGLE_NETWORK
fi

if [[ -z "$NETWORKS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No networks provided"${RESET} >> $LOG
		echo
		# echo -e ${REDF}"No NETWORKS provided. This script is exiting"${RESET}
		EXIT_CODE="85"
		EXIT_FUNCTION
fi

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
SCAN_NETWORKS
if [[ "$SINGLE_NETWORK" == "0" ]]
	then
		GET_ARP_IPS
fi
CLEANUP_DUPLICATES
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking for connectivity on devices"${RESET} >> $LOG
fping -Ar 1 -f $FILE | sed 's/ /_/g' > $PING_DEVICE_RESULT_FILE
for LINE in `cat $PING_DEVICE_RESULT_FILE`
	do
		IP=$(echo "$LINE" | egrep --color=never -o '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
		PING_STATUS=$(echo "$LINE" | egrep --color=never -o '[a-zA-Z]+$')
		if [[ "$PING_STATUS" == "alive" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is reachable"${RESET} >> $LOG
				CHECK_ALTERNATE_ADDRESSES
				GET_DEVICE_ID
				UPDATE_DEVICE
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable"${RESET} >> $LOG
		fi
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the script"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
