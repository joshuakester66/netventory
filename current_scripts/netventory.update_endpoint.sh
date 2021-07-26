#!/bin/bash
#Filename: netventory.update_endpoint.sh
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

SCRIPT_NAME="netventory.update_endpoint"
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
# ONE_DAY_AGO="1 days ago"
# ONE_DAY_AGO_EPOCH=$(date --date "$ONE_DAY_AGO" +'%s')

IP_SELECT_SNMP="SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE (snmp_enabled='1' AND (ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%')) AND (ping_check > (NOW() - INTERVAL 7 DAY) OR added > (NOW() - INTERVAL 1 DAY)) ORDER BY updated;"
IP_SELECT_NO_SNMP="SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE (snmp_enabled='0' AND (ip LIKE '10.%' OR ip LIKE '172.1_.%' OR ip LIKE '172.2_.%' OR ip LIKE '172.30.%' OR ip LIKE '172.31.%' OR ip LIKE '192.168.%')) AND (ping_check > (NOW() - INTERVAL 7 DAY) OR added > (NOW() - INTERVAL 1 DAY)) ORDER BY updated LIMIT 20;"

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
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "$IP_SELECT"`
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

GET_SNMP_STATUS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the SNMP status from the database"${RESET} >> $LOG
SNMP_ENABLED=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT snmp_enabled FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE $ENDPOINT_TABLE.id='$ENDPOINT_ID';"`
}

GET_SNMP_CREDS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the SNMP credentials for $IP"${RESET} >> $LOG
# read -p "Press any key to continue. Device ID: $ENDPOINT_ID " DEBUG
SNMP_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $SNMP_TABLE.community,$SNMP_TABLE.authlevel,$SNMP_TABLE.authname,$SNMP_TABLE.authpass,$SNMP_TABLE.authalgo,$SNMP_TABLE.cryptopass,$SNMP_TABLE.cryptoalgo,$SNMP_TABLE.version,$SNMP_TABLE.port FROM $LOCAL_DATABASE.$SNMP_TABLE LEFT JOIN $LOCAL_DATABASE.$ENDPOINT_TABLE ON $SNMP_TABLE.id=$ENDPOINT_TABLE.snmp_id WHERE $ENDPOINT_TABLE.id='$ENDPOINT_ID';"`)
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
OID_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $OID_TABLE.sysdescr,$OID_TABLE.sysname,$OID_TABLE.syslocation,$OID_TABLE.model,$OID_TABLE.firmware_p,$OID_TABLE.serial,$OID_TABLE.manufacturer,$OID_TABLE.rom,$OID_TABLE.mac,$OID_TABLE.mac_alt,$OID_TABLE.alt_ip,$OID_TABLE.network_int FROM $LOCAL_DATABASE.$OID_TABLE LEFT JOIN $LOCAL_DATABASE.$ENDPOINT_TABLE ON $LOCAL_DATABASE.$OID_TABLE.id=$ENDPOINT_TABLE.oid_id WHERE $ENDPOINT_TABLE.id='$ENDPOINT_ID';"`)
OID_SYSDESCR=${OID_ARRAY[0]}
OID_SYSNAME=${OID_ARRAY[1]}
OID_SYSLOCATION=${OID_ARRAY[2]}
OID_MODEL=${OID_ARRAY[3]}
OID_FIRMWARE_P=${OID_ARRAY[4]}
OID_SERIAL=${OID_ARRAY[5]}
OID_MANUFACTURER=${OID_ARRAY[6]}
OID_ROM=${OID_ARRAY[7]}
OID_MAC=${OID_ARRAY[8]}
OID_MAC_ALT=${OID_ARRAY[9]}
OID_ALT_IP=${OID_ARRAY[10]}
OID_NETWORK_INT=${OID_ARRAY[11]}
SYSDESCR=
SYSDESCR=$(snmpget -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_SYSDESCR 2> /dev/null)
SYSNAME=
SYSNAME=$(snmpget -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_SYSNAME 2> /dev/null | sed "s/'//g")
SYSLOCATION=
SYSLOCATION=$(snmpget -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_SYSLOCATION 2> /dev/null | sed 's/.*Unknown.*/Unknown/g')
MODEL=
MODEL=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_MODEL 2> /dev/null | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | egrep --color=never --invert-match '[Mm][Ii][Bb]')
if [[ -z "$MODEL" ]]
	then
		MODEL=$(echo "$SYSDESCR" | egrep --color=never -o '^[A-Za-z0-9-]+,?\s' | sed 's/\s//g' | sed 's/,//g')
fi
FIRMWARE_P=
FIRMWARE_P=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_FIRMWARE_P 2> /dev/null | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | egrep --color=never --invert-match '[Mm][Ii][Bb]')
SERIAL=
SERIAL=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_SERIAL 2> /dev/null | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | sed 's/ //g' | egrep --color=never --invert-match '[Mm][Ii][Bb]')
MANUFACTURER=
MANUFACTURER=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_MANUFACTURER 2> /dev/null | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | egrep --color=never --invert-match '[Mm][Ii][Bb]')
if [[ -z "$MANUFACTURER" ]]
	then
		MANUFACTURER=$(echo "$SYSDESCR" | egrep --color=never -o '^[A-Za-z0-9-]+,?\s' | sed 's/\s//g' | sed 's/,//g')
fi
ROM=
ROM=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_ROM 2> /dev/null | grep --color=never --invert-match '""' | head -n 1 | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | sed 's/ //g' | egrep --color=never --invert-match '[Mm][Ii][Bb]')
DNS_NAME=
DNS_NAME=$(dig +short -x $IP | sed s'/\.$//g' | sort --unique | sed ':a;N;$!ba;s/\n/,/g')
MAC=
MAC=$(snmpwalk -O 0qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_MAC 2> /dev/null | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | sed 's/ /:/g' | sed 's/:$//g' | sed 's/^://g' | egrep --color=never --invert-match '[Mm][Ii][Bb]')
if [[ -z "$MAC" ]]
	then
		MAC=$(snmpwalk -O 0qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_MAC_ALT 2> /dev/null | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed 's/\"//g' | sed 's/ /:/g' | sed 's/:$//g' | sed 's/^://g' | egrep --color=never --invert-match '[Mm][Ii][Bb]')
fi
if [[ -z "$MAC" ]]
	then
		MAC=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT mac FROM $LOCAL_DATABASE.$ARP_TABLE WHERE ip='$IP' GROUP BY mac LIMIT 1;"`
	elif [[ "$MAC" == "00:00:00:00:00:00" ]]
		then
			MAC=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT mac FROM $LOCAL_DATABASE.$ARP_TABLE WHERE ip='$IP' AND mac!='00:00:00:00:00:00' GROUP BY mac LIMIT 1;"`
fi		
MAC=${MAC,,}
if [[ -n "$MAC" ]]
	then
		GET_MAC_OUI
fi
ALTERNATE_IPS=
ALTERNATE_IPS=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_ALT_IP 2> /dev/null | grep --color=never --invert-match "No Such" | grep --color=never --invert-match "no:such" | sed '/^127\..*$/d' | sed "/$IP/d" | egrep --color=never --invert-match '[Mm][Ii][Bb]' | sed '/0.0.0.0/d')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Description: $SYSDESCR"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SysName: $SYSNAME"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Location: $SYSLOCATION"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Model: $MODEL"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Primary Firmware: $FIRMWARE_P"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Secondary Firmware: $FIRMWARE_S"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}ROM: $ROM"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Serial: $SERIAL"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Manufacturer: $MANUFACTURER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}DNS Name: $DNS_NAME"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}MAC Address: $MAC"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}OUI: $OUI"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Alternate IP Addresses: $ALTERNATE_IPS"${RESET} >> $LOG
}

GET_MAC_OUI ()
{
OUI=
MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{1}')
# OUI=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT description FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI' LIMIT 1;"`
OUI=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI';"`
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}')
		OUI=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI';"`
fi
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{1}')
		OUI=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI';"`
fi
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}')
		OUI=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI';"`
fi
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{1}')
		OUI=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI';"`
fi
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}')
		OUI=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI' LIMIT 1;"`
fi
}

UPDATE_MYSQL ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $ENDPOINT_TABLE table for $IP"${RESET} >> $LOG
if [[ -z "$OUI" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET description='$SYSDESCR',hostname='$SYSNAME',sysname='$SYSNAME',syslocation='$SYSLOCATION',model='$MODEL',firmware_p='$FIRMWARE_P',firmware_s='$FIRMWARE_S',serial='$SERIAL',manufacturer='$MANUFACTURER',rom='$ROM',updated=NOW(),dns_name='$DNS_NAME',mac='$MAC',ping_check=NOW() WHERE id='$ENDPOINT_ID';
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET description='$SYSDESCR',hostname='$SYSNAME',sysname='$SYSNAME',syslocation='$SYSLOCATION',model='$MODEL',firmware_p='$FIRMWARE_P',firmware_s='$FIRMWARE_S',serial='$SERIAL',manufacturer='$MANUFACTURER',rom='$ROM',updated=NOW(),dns_name='$DNS_NAME',mac='$MAC',oui='$OUI',ping_check=NOW() WHERE id='$ENDPOINT_ID';
EOF
fi
for ALT_IP in $ALTERNATE_IPS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Deleting alternate ip $ALT_IP from the $ENDPOINT_TABLE table"${RESET} >> $LOG
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
DELETE FROM $ENDPOINT_TABLE WHERE ip='$ALT_IP';
EOF
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking for $ALT_IP in the $ADDRESS_TABLE table"${RESET} >> $LOG
		INTERFACE=
		INTERFACE_ID=
		INTERFACE=$(snmpwalk -O qv -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_NETWORK_INT.$ALT_IP 2> /dev/null | egrep --color=never -o '[0-9]+')
		if [[ -n "$INTERFACE" ]]
			then
				INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE endpoint_id='$ENDPOINT_ID' AND port='$INTERFACE';"`
		fi
		if [[ -z "$INTERFACE_ID" ]]
			then
				INTERFACE_ID="0"
		fi
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP $ALT_IP is interface index $INTERFACE"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP $ALT_IP is interface_id $INTERFACE_ID"${RESET} >> $LOG
		ALT_IP_ID=
		ALT_IP_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ADDRESS_TABLE WHERE ip='$ALT_IP' AND endpoint_id='$ENDPOINT_ID';"`
		if [[ -z "$ALT_IP_ID" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$ALT_IP does not exist in the $ADDRESS_TABLE. Adding it"${RESET} >> $LOG
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $ADDRESS_TABLE(device_id,endpoint_id,interface_id,ip,updated) VALUES('$ENDPOINT_ID','$ENDPOINT_ID','$INTERFACE_ID','$ALT_IP',NOW());
EOF
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$ALT_IP already exists in the $ADDRESS_TABLE. Updating it"${RESET} >> $LOG
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ADDRESS_TABLE set device_id='$ENDPOINT_ID',endpoint_id='$ENDPOINT_ID',interface_id='$INTERFACE_ID',ip='$ALT_IP',updated=NOW() WHERE id='$ALT_IP_ID';
EOF
		fi
done
}

GET_NAME ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the DNS Name for $IP"${RESET} >> $LOG
DNS_NAME=
DNS_NAME=$(dig +short -x $IP | sed 's/\.$//g' | sed ':a;N;$!ba;s/\n/,/g')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}DNS Name: $DNS_NAME"${RESET} >> $LOG
}

UPDATE_MYSQL_NO_SNMP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $ENDPOINT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET updated=NOW(),dns_name='$DNS_NAME',ping_check=NOW() WHERE id='$ENDPOINT_ID';
EOF
}

UPDATE_MYSQL_NO_PING ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $ENDPOINT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET updated=NOW(),windows_check=NOW() WHERE ip='$IP';
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

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking endpoints with SNMP access"${RESET} >> $LOG
PRIORITY_IPS=
if [[ -z "$IPS" ]]
	then
		IP_SELECT=$IP_SELECT_SNMP
		GET_IPS
	else
		PRIORITY_IPS="1"
fi

if [[ -z "$IPS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs or Hostnames found"${RESET} >> $LOG
		echo
		EXIT_CODE="85"
		EXIT_FUNCTION
fi

for IP in $IPS
	do
		if ping -c 1 -W 1 -i 0.2 $IP &> /dev/null
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
				GET_ENDPOINT_ID
				GET_SNMP_STATUS
				if [[ "$SNMP_ENABLED" == "0" ]]
					then
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SNMP is not availabe on this endpoint. Moving on"${RESET} >> $LOG
						continue
				fi
				GET_SNMP_CREDS
				GET_INFO
				UPDATE_MYSQL
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable"${RESET} >> $LOG
				UPDATE_MYSQL_NO_PING
		fi
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking endpoints without SNMP access"${RESET} >> $LOG
if [[ -z "$PRIORITY_IPS" ]]
	then
		IP_SELECT=$IP_SELECT_NO_SNMP
		GET_IPS
fi
if [[ -z "$IPS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs or Hostnames found without SNMP"${RESET} >> $LOG
	else
		for IP in $IPS
			do
				if ping -c 1 -W 1 -i 0.2 $IP &> /dev/null
					then
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
						GET_ENDPOINT_ID
						GET_NAME
						UPDATE_MYSQL_NO_SNMP
					else
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable"${RESET} >> $LOG
						UPDATE_MYSQL_NO_PING
				fi
		done
fi

UPDATE_MAC
UPDATE_OUI

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
