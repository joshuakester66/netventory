#!/bin/bash
#Filename: windows_info.sh
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

IPS=$1

SCRIPT_NAME="windows_info"
SCRIPT_CAT="netventory"

mkdir -p $HOME/scripts/logs &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/scripts/logs/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
OID_TABLE="oid"
SNMP_TABLE="snmp"
ARP_TABLE="arp"
ADDRESS_TABLE="ipv4_addresses"
SNMP_TIMEOUT="0.2"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"

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
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 30 DAY);"`
}

GET_DEVICE_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the device ID for $IP"${RESET} >> $LOG
DEVICE_ID=
DEVICE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
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
INSERT INTO $DEVICE_TABLE(ip,updated,added) VALUES('$IP',NOW(),NOW());
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

GET_INFO ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the necessary information for $IP"${RESET} >> $LOG
# Asset Tag:
ASSET_TAG=$(wmic --user "$DOMAIN\$WMIC_USERNAME" --password "$WMIC_PASSWORD" --delimiter='" "' //$ENDPOINT "SELECT serialnumber from Win32_bios" | sed '/CLASS: /d' | sed '/SerialNumber/d' | sed 's/^[^"]*" "//g' | sed 's/" .*$//g')
# Software:
wmic --user "$DOMAIN\$WMIC_USERNAME" --password "$WMIC_PASSWORD" --delimiter='" "' //$ENDPOINT "SELECT name,version,vendor FROM Win32_Product" | sed '/CLASS: /d' | sed '/Name\" \"Vendor/d' | sed 's/^/\"/g' | sed 's/$/\"/g' | sort --unique
# System:
wmic --user "$DOMAIN\$WMIC_USERNAME" --password "$WMIC_PASSWORD" --delimiter='" "' //$ENDPOINT "SELECT BuildNumber,Caption,CSDVersion,CSName,Description,InstallDate,LastBootUpTime,Manufacturer,Organization,OSArchitecture,RegisteredUser,Status,Version from Win32_operatingsystem"
# NIC:
wmic --user "$DOMAIN\$WMIC_USERNAME" --password "$WMIC_PASSWORD" --delimiter='" "' //$ENDPOINT "SELECT description,macaddress,netenabled,manufacturer,name FROM win32_networkadapter"
# OID_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $OID_TABLE.sysdescr,$OID_TABLE.sysname,$OID_TABLE.syslocation,$OID_TABLE.model,$OID_TABLE.firmware_p,$OID_TABLE.serial,$OID_TABLE.manufacturer,$OID_TABLE.rom,$OID_TABLE.mac,$OID_TABLE.alt_ip FROM $LOCAL_DATABASE.$OID_TABLE LEFT JOIN $LOCAL_DATABASE.$DEVICE_TABLE ON $LOCAL_DATABASE.$OID_TABLE.id=$DEVICE_TABLE.oid_id WHERE $DEVICE_TABLE.id='$DEVICE_ID';"`)
# OID_SYSDESCR=${OID_ARRAY[0]}
# OID_SYSNAME=${OID_ARRAY[1]}
# OID_SYSLOCATION=${OID_ARRAY[2]}
# OID_MODEL=${OID_ARRAY[3]}
# OID_FIRMWARE_P=${OID_ARRAY[4]}
# OID_SERIAL=${OID_ARRAY[5]}
# OID_MANUFACTURER=${OID_ARRAY[6]}
# OID_ROM=${OID_ARRAY[7]}
# OID_MAC=${OID_ARRAY[8]}
# OID_ALT_IP=${OID_ARRAY[9]}
# SYSDESCR=
# SYSDESCR=$(snmpget -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_SYSDESCR)
# SYSNAME=
# SYSNAME=$(snmpget -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_SYSNAME)
# SYSLOCATION=
# SYSLOCATION=$(snmpget -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_SYSLOCATION)
# MODEL=
# MODEL=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_MODEL | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g')
# if [[ -z "$MODEL" ]]
# 	then
# 		MODEL=$(echo "$SYSDESCR" | egrep --color=never -o '^[A-Za-z0-9-]+,?\s' | sed 's/\s//g' | sed 's/,//g')
# fi
# FIRMWARE_P=
# FIRMWARE_P=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_FIRMWARE_P | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g')
# SERIAL=
# SERIAL=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_SERIAL | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | sed 's/ //g')
# MANUFACTURER=
# MANUFACTURER=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_MANUFACTURER | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g')
# if [[ -z "$MANUFACTURER" ]]
# 	then
# 		MANUFACTURER=$(echo "$SYSDESCR" | egrep --color=never -o '^[A-Za-z0-9-]+,?\s' | sed 's/\s//g' | sed 's/,//g')
# fi
# if [[ "$MANUFACTURER" == "USW-48P-500" ]]
# 	then
# 		MANUFACTURER="Ubiquiti"
# fi
# ROM=
# ROM=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_ROM | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | sed 's/ //g')
# DNS_NAME=
# DNS_NAME=$(dig +short -x $IP)
# MAC=
# MAC=$(snmpwalk -O 0qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_MAC | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | sed 's/ /:/g' | sed 's/:$//g' | sed 's/^://g')
# MAC=${MAC,,}
# if [[ -z "$MAC" ]]
# 	then
# 		MAC=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT mac FROM $LOCAL_DATABASE.$ARP_TABLE WHERE ip='$IP' GROUP BY mac;"`
# 	elif [[ "$MAC" == "00:00:00:00:00:00" ]]
# 		then
# 			MAC=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT mac FROM $LOCAL_DATABASE.$ARP_TABLE WHERE ip='$IP' GROUP BY mac;"`
# fi		
# ALTERNATE_IPS=
# ALTERNATE_IPS=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_ALT_IP | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed '/^127\..*$/d' | sed "/$IP/d")
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Description: $SYSDESCR"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SysName: $SYSNAME"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Location: $SYSLOCATION"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Model: $MODEL"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Primary Firmware: $FIRMWARE_P"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Secondary Firmware: $FIRMWARE_S"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}ROM: $ROM"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Serial: $SERIAL"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Manufacturer: $MANUFACTURER"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}DNS Name: $DNS_NAME"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}MAC Address: $MAC"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Alternate IP Addresses: $ALTERNATE_IPS"${RESET} >> $LOG
}

UPDATE_MYSQL ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $DEVICE_TABLE for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DEVICE_TABLE SET description='$SYSDESCR',hostname='$SYSNAME',sysname='$SYSNAME',syslocation='$SYSLOCATION',model='$MODEL',firmware_p='$FIRMWARE_P',firmware_s='$FIRMWARE_S',serial='$SERIAL',manufacturer='$MANUFACTURER',rom='$ROM',updated=NOW(),dns_name='$DNS_NAME',mac='$MAC' WHERE id='$DEVICE_ID';
EOF
for ALT_IP in $ALTERNATE_IPS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Deleting $ALT_IP from the $DEVICE_TABLE table"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
DELETE FROM $DEVICE_TABLE WHERE ip='$ALT_IP';
EOF
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $ALT_IP to the $ADDRESS_TABLE table"${RESET} >> $LOG
		ALT_IP_ID=
		ALT_IP_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ADDRESS_TABLE WHERE ip='$ALT_IP';"`
		if [[ -z "$ALT_IP_ID" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$ALT_IP does not exist in the $ADDRESS_TABLE. Adding it"${RESET} >> $LOG
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $ADDRESS_TABLE(device_id,ip,updated) VALUES('$DEVICE_ID','$ALT_IP',NOW());
EOF
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$ALT_IP already exists in the $ADDRESS_TABLE"${RESET} >> $LOG
		fi
done
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
		echo -e ${REDF}"No IPs or Hostnames provided. This script is exiting"${RESET}
		EXIT_CODE="85"
		EXIT_FUNCTION
fi

DOMAIN=$2
WMIC_USERNAME=$3
WMIC_PASSWORD=$4
if [[ -z "$DOMAIN" ]]
        then
                read -p "What's the domain? " DOMAIN
fi
if [[ -z "$WMIC_USERNAME" ]]
        then
                read -p "What's the username? " WMIC_USERNAME
fi
if [[ -z "$WMIC_PASSWORD" ]]
        then
                read -p "What's the password? " WMIC_PASSWORD
fi

for IP in $IPS
	do
		if ping -c 1 -W 1 -i 0.2 $IP &> /dev/null
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
				# GET_DEVICE_ID
				# GET_SNMP_CREDS
				GET_INFO
				# UPDATE_MYSQL
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable"${RESET} >> $LOG
		fi
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
