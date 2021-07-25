#!/bin/bash
#Filename: netventory.update_windows.sh
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

SCRIPT_NAME="netventory.update_windows"
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
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
OID_TABLE="oid"
SNMP_TABLE="snmp"
ARP_TABLE="arp"
ADDRESS_TABLE="ipv4_addresses"
INTERFACE_TABLE="interface"
OUI_TABLE="oui"
SNMP_TIMEOUT="0.2"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
COUNT_PER_RUN="50"
DATABASE_CATEGORY="pc"
DATABASE_TYPE="windows"

IP_SELECT="SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ((ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '10.%.101.%') AND (ping > (NOW() - INTERVAL 3 DAY) OR added > (NOW() - INTERVAL 1 DAY)) AND category='pc' ORDER BY windows_check LIMIT $COUNT_PER_RUN;"
IP_SELECT_COUNT="SELECT COUNT(ip) FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ((ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '10.%.101.%') AND (ping > (NOW() - INTERVAL 3 DAY) OR added > (NOW() - INTERVAL 1 DAY)) AND category='pc' ORDER BY windows_check;"

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
NUMBER_OF_ENDPOINTS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ((ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '10.%.101.%') AND (ping > (NOW() - INTERVAL 3 DAY) OR added > (NOW() - INTERVAL 1 DAY)) AND category='pc' ORDER BY windows_check;"`
COUNT_PER_RUN=$(expr $NUMBER_OF_ENDPOINTS / $COUNT_DIVISION)
if [[ "$COUNT_PER_RUN" == "0" ]]
	then
		COUNT_PER_RUN=$NUMBER_OF_ENDPOINTS
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$NUMBER_OF_ENDPOINTS total eligible endpoints found"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting up to $COUNT_PER_RUN endpoint IPs"${RESET} >> $LOG
ENDPOINT_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ((ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%') AND ip NOT LIKE '10.%.101.%') AND (ping > (NOW() - INTERVAL 3 DAY) OR added > (NOW() - INTERVAL 1 DAY)) AND category='pc' ORDER BY windows_check LIMIT $COUNT_PER_RUN;"`
}

GET_ENDPOINT_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint ID for $IP"${RESET} >> $LOG
ENDPOINT_ID=
DEVICE_ID=
ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
if [[ -z "$ENDPOINT_ID" ]]
	then
		DEVICE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
fi
if [[ -n "$DEVICE_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is a device. Moving on"${RESET} >> $LOG
		continue
fi
if [[ -z "$ENDPOINT_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP does not exist in the database yet. Adding it"${RESET} >> $LOG
		ADD_ENDPOINT
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the new endpoint ID"${RESET} >> $LOG
		ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Device ID: $ENDPOINT_ID"${RESET} >> $LOG
}

ADD_ENDPOINT ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the endpoint to the $ENDPOINT_TABLE table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $ENDPOINT_TABLE(ip,ping_check,updated,added) VALUES('$IP',CURDATE(),NOW(),NOW());
EOF
}

GET_HOSTNAME ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the Hostname for $IP"${RESET} >> $LOG
ENDPOINT_HOSTNAME=
ENDPOINT_HOSTNAME=$(winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$IP "hostname" 2> /dev/null | sed 's/\s*//g')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Hostname: $ENDPOINT_HOSTNAME"${RESET} >> $LOG
}

GET_DNS_NAME ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the DNS Name for $IP"${RESET} >> $LOG
DNS_NAME=
DNS_NAME=$(dig +short -x $IP | sed 's/\.$//g' | sed ':a;N;$!ba;s/\n/,/g')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}DNS Name: $DNS_NAME"${RESET} >> $LOG
}

GET_WINDOWS_INFO ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting windows information for $IP"${RESET} >> $LOG
ENDPOINT_MANUFACTURER=
ENDPOINT_MODEL=
ENDPOINT_MAC=
ENDPOINT_MANUFACTURER=$(winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$IP "wmic csproduct get vendor" 2> /dev/null | sed '/Vendor/d' | sed '/^[[:space:]]*$/d')
ENDPOINT_MODEL=$(winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$IP "wmic computersystem get model" 2> /dev/null | sed '/Model/d' | sed '/^[[:space:]]*$/d')
ENDPOINT_OS=$(winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$IP "wmic os get Caption,CSDVersion /value" 2> /dev/null | sed '/CSDVersion/d' | sed '/^[[:space:]]*$/d' | sed 's/Caption=//g')
ENDPOINT_SERIAL=$(winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$IP "wmic bios get serialnumber" 2> /dev/null | sed '/SerialNumber/d' | sed '/^[[:space:]]*$/d')
ENDPOINT_OS_VERSION=$(winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$IP "cmd /c ver" 2> /dev/null | sed 's/^.*Version //g' | sed '/^[[:space:]]*$/d' | sed 's/\]//g')
ENDPOINT_MAC=$(winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$IP "getmac" 2> /dev/null | egrep --color=never -A 1 "=====" | egrep --color=never -o '[0-9A-Fa-f]{2}\-[0-9A-Fa-f]{2}\-[0-9A-Fa-f]{2}\-[0-9A-Fa-f]{2}\-[0-9A-Fa-f]{2}\-[0-9A-Fa-f]{2}' | sed 's/-/:/g' | tr [:upper:] [:lower:])
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Manufacturer: $ENDPOINT_MANUFACTURER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Model: $ENDPOINT_MODEL"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}OS: $ENDPOINT_OS"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Serial: $ENDPOINT_SERIAL"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}OS Version: $ENDPOINT_OS_VERSION"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint MAC: $ENDPOINT_MAC"${RESET} >> $LOG
}

UPDATE_MYSQL_NO_PING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $ENDPOINT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET updated=NOW(),windows_check=NOW(),ping_check=NOW() WHERE ip='$IP';
EOF
}

UPDATE_MYSQL_WINDOWS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $ENDPOINT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET hostname='$ENDPOINT_HOSTNAME',manufacturer='$ENDPOINT_MANUFACTURER',model='$ENDPOINT_MODEL',mac='$ENDPOINT_MAC',os='$ENDPOINT_OS',serial='$ENDPOINT_SERIAL',os_version='$ENDPOINT_OS_VERSION',dns_name='$DNS_NAME',category='$DATABASE_CATEGORY',type='$DATABASE_TYPE',updated=NOW(),ping_check=NOW(),windows_check=NOW(),ping_check=NOW(),ping=NOW() WHERE id='$ENDPOINT_ID';
EOF
}

UPDATE_MYSQL_WINDOWS_NO_DATA ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $ENDPOINT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET updated=NOW(),dns_name='$DNS_NAME',windows_check=NOW(),ping_check=NOW(),ping=NOW() WHERE id='$ENDPOINT_ID';
EOF
}

UPDATE_MAC ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the mac addresses for endpoints without SNMP"${RESET} >> $LOG
ENDPOINT_IDS=
ENDPOINT_IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE (mac IS NULL OR mac='') AND ping_check > (NOW() - INTERVAL 7 DAY) ORDER BY updated DESC LIMIT 50;"`
for ENDPOINT_ID in $ENDPOINT_IDS
	do
		IP=
		IP=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE id='$ENDPOINT_ID';"`
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE set mac=(SELECT mac FROM $ARP_TABLE WHERE ip='$IP' AND mac!='ff:ff:ff:ff:ff:ff' ORDER BY updated DESC LIMIT 1) WHERE id='$ENDPOINT_ID';
EOF
done
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE set mac=NULL WHERE mac='00:00:00:00:00:00';
UPDATE $ENDPOINT_TABLE set mac=NULL WHERE mac='ff:ff:ff:ff:ff:ff';
EOF
}

UPDATE_OUI ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the oui for endpoints that haven't been updated yet"${RESET} >> $LOG
ENDPOINT_IDS=
ENDPOINT_IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE (oui IS NULL AND mac IS NOT NULL) AND ((ping_check > (NOW() - INTERVAL 7 DAY) AND updated < (NOW() - INTERVAL 1 DAY)) OR added > (NOW() - INTERVAL 1 DAY)) ORDER BY updated LIMIT 50;"`
for ENDPOINT_ID in $ENDPOINT_IDS
	do
		# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updatine Device ID: $ENDPOINT_ID"${RESET} >> $LOG
		MAC=
		MAC=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT mac FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE id='$ENDPOINT_ID';"`
		GET_MAC_OUI
		# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}OUI: $OUI"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE set oui="$OUI" WHERE id='$ENDPOINT_ID';
EOF
done
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
				GET_HOSTNAME
				if [[ -n "$ENDPOINT_HOSTNAME" ]]
					then
						GET_WINDOWS_INFO
						GET_DNS_NAME
						UPDATE_MYSQL_WINDOWS
					else
						GET_DNS_NAME
						UPDATE_MYSQL_WINDOWS_NO_DATA
				fi
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
