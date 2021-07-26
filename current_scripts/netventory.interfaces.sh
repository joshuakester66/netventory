#!/bin/bash
#Filename: netventory.interfaces.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# net-snmp
# net-snmp-utils
# procmail (lockfile command)
## read -p "Press any key to continue. " DEBUG #DEBUG

SCRIPT_NAME="netventory.interfaces"
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
TABLE_ARRAY=($DEVICE_TABLE $ENDPOINT_TABLE)
OID_TABLE="oid"
INTERFACE_TABLE="interface"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
COUNT_PER_RUN="30"

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
NUMBER_OF_DEVICE_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 7 DAY) AND ip NOT LIKE '169.%.%.%' order by interface_check;"`
DEVICE_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 7 DAY) AND ip NOT LIKE '169.%.%.%' order by interface_check LIMIT $COUNT_PER_RUN;"`
NUMBER_OF_ENDPOINT_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 7 DAY) AND ip NOT LIKE '169.%.%.%' order by interface_check;"`
ENDPOINT_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 7 DAY) AND ip NOT LIKE '169.%.%.%' order by interface_check LIMIT $COUNT_PER_RUN;"`
}

INTERFACE_CHECK ()
{
for IP in $IPS
	do
		if [[ "$IGNORE_LIST" == *"$IP"* ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP has already been checked and is not reachable. Moving on"${RESET} >> $LOG
				continue
		fi
		if ping -c 1 -W 1 $IP &> /dev/null
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking IP $IP"${RESET} >> $LOG
				CURRENT_ID="${CURRENT_TABLE^^}"
				GET_${CURRENT_ID}_ID
				if [[ -z "$DEVICE_ID" ]]
					then
						DEVICE_ID=$ENDPOINT_ID
				fi
				UPDATE_DEVICE
				GET_SNMP_CREDS
				GET_DATA_1
				if [[ -n "$INT_DESCR" ]]
					then
# read -p "Press any key to continue. 904 " DEBUG #DEBUG
						GET_DATA_2
# read -p "Press any key to continue. 905 " DEBUG #DEBUG
						INTERFACES=
						INTERFACES=$(echo "$INT_DESCR" | egrep --color=never -o '^[0-9]{1,6};;' | sed 's/;//g')
						# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interfaces: $INTERFACES"${RESET} >> $LOG
						for INTERFACE in $INTERFACES
							do
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on interface $INTERFACE"${RESET} >> $LOG
# read -p "Press any key to continue. 906 " DEBUG #DEBUG
								GET_INFO
# read -p "Press any key to continue. 907 " DEBUG #DEBUG
								INTERFACE_ID=
# read -p "Press any key to continue. 903 " DEBUG #DEBUG
								INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE (device_id='$DEVICE_ID' OR endpoint_id='$DEVICE_ID') AND port='$PORT';"`
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface ID: $INTERFACE_ID"${RESET} >> $LOG
# read -p "Press any key to continue. 901 " DEBUG #DEBUG
								if [[ -z "$INTERFACE_ID" ]]
									then
										ADD_MYSQL_INTERFACE
									else
										UPDATE_MYSQL_INTERFACE
								fi
# read -p "Press any key to continue. 902 " DEBUG #DEBUG
						done
					else
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}No interfaces to update"${RESET} >> $LOG
				fi
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable. Moving on"${RESET} >> $LOG
				IGNORE_LIST="${IGNORE_LIST} $IP"
				UPDATE_DEVICE
				echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
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
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is an endpoint with Endpoint ID: $ENDPOINT_ID. Moving on"${RESET} >> $LOG
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
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is a device with Device ID: $DEVICE_ID. Moving on"${RESET} >> $LOG
		continue
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
}

GET_SNMP_CREDS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the SNMP credentials for $IP"${RESET} >> $LOG
# read -p "Press any key to continue. Device ID: $DEVICE_ID " DEBUG
SNMP_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $SNMP_TABLE.community,$SNMP_TABLE.authlevel,$SNMP_TABLE.authname,$SNMP_TABLE.authpass,$SNMP_TABLE.authalgo,$SNMP_TABLE.cryptopass,$SNMP_TABLE.cryptoalgo,$SNMP_TABLE.version,$SNMP_TABLE.port FROM $LOCAL_DATABASE.$SNMP_TABLE LEFT JOIN $LOCAL_DATABASE.$CURRENT_TABLE ON $SNMP_TABLE.id=$CURRENT_TABLE.snmp_id WHERE $CURRENT_TABLE.id='$DEVICE_ID';"`)
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

GET_DATA_1 ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the necessary variables"${RESET} >> $LOG
INT_DESCR=
OID_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $OID_TABLE.int_descr,$OID_TABLE.int_alias,$OID_TABLE.int_admin,$OID_TABLE.int_status,$OID_TABLE.int_status_change,$OID_TABLE.int_poe,$OID_TABLE.int_type FROM $LOCAL_DATABASE.$OID_TABLE LEFT JOIN $LOCAL_DATABASE.$CURRENT_TABLE ON $LOCAL_DATABASE.$OID_TABLE.id=$CURRENT_TABLE.oid_id WHERE $CURRENT_TABLE.id='$DEVICE_ID';"`)
OID_INT_DESCR=${OID_ARRAY[0]}
OID_INT_ALIAS=${OID_ARRAY[1]}
OID_INT_ADMIN=${OID_ARRAY[2]}
OID_INT_STATUS=${OID_ARRAY[3]}
OID_INT_STATUS_CHANGE=${OID_ARRAY[4]}
OID_INT_POE=${OID_ARRAY[5]}
OID_INT_TYPE=${OID_ARRAY[6]}
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the Interface variable"${RESET} >> $LOG
INT_DESCR=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -On $IP $OID_INT_DESCR 2> /dev/null | sed '/loopback/d' | sed '/oobm/d' | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*\(.*:\s*\)\?\(\"\)\?\(.*\)\(\"\)\?$/\1;;\4/g' | sed 's/\"//g' | sed '/End of MIB/d')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface Description: $INT_DESCR"${RESET} >> $LOG
}

GET_DATA_2 ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the necessary variables"${RESET} >> $LOG
#INT_DESCR=
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface Alias variable"${RESET} >> $LOG
INT_ALIAS=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -On $IP $OID_INT_ALIAS 2> /dev/null | sed '/loopback/d' | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*\(.*:\s*\)\?\(\"\)\?\(.*\)\(\"\)\?$/\1;;\4/g' | sed 's/\"//g' | sed '/End of MIB/d')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INT_ALIAS: $INT_ALIAS"${RESET} >> $LOG
# read -p "Press any key to continue. 910 " DEBUG #DEBUG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface Admin Status variable"${RESET} >> $LOG
INT_ADMIN=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -On $IP $OID_INT_ADMIN 2> /dev/null | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*\(.*:\s*\)\?\(\"\)\?\(.*\)\(\"\)\?$/\1;;\4/g' | sed 's/\"//g' | sed '/End of MIB/d')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INT_ADMIN: $INT_ADMIN"${RESET} >> $LOG
# read -p "Press any key to continue. 911 " DEBUG #DEBUG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface status variable"${RESET} >> $LOG
INT_STATUS=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -On $IP $OID_INT_STATUS 2> /dev/null | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*\(.*:\s*\)\?\(\"\)\?\(.*\)\(\"\)\?$/\1;;\4/g' | sed 's/\"//g' | sed '/End of MIB/d')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INT_STATUS: $INT_STATUS"${RESET} >> $LOG
# read -p "Press any key to continue. 912 " DEBUG #DEBUG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface status changes variable"${RESET} >> $LOG
INT_STATUS_CHANGE=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -On $IP $OID_INT_STATUS_CHANGE 2> /dev/null | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*\(.*:\s*\)\?\(\"\)\?\(.*\)\(\"\)\?$/\1;;\4/g' | sed 's/\"//g' | sed '/End of MIB/d')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INT_STATUS_CHANGE: $INT_STATUS_CHANGE"${RESET} >> $LOG
# read -p "Press any key to continue. 913 " DEBUG #DEBUG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface PoE variable"${RESET} >> $LOG
INT_POE=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -On $IP $OID_INT_POE 2> /dev/null | sed 's/^.*\.\([0-9]\{1,2\}\)\.\([0-9]\{1,6\}\)\s*=\s*.*:\s*\(.*\)$/\1;;\2;;\3/g' | sed '/End of MIB/d' | sed '/No Such Object/d')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INT_POE: $INT_POE"${RESET} >> $LOG
# read -p "Press any key to continue. 914 " DEBUG #DEBUG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface type variable"${RESET} >> $LOG
INT_TYPE=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -On $IP $OID_INT_TYPE 2> /dev/null | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*\(.*:\s*\)\?\(\"\)\?\(.*\)\(\"\)\?$/\1;;\4/g' | sed 's/\"//g' | sed '/End of MIB/d')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INT_TYPE: $INT_TYPE"${RESET} >> $LOG
# read -p "Press any key to continue. 915 " DEBUG #DEBUG
}

GET_INFO ()
{
PORT=
PORT_NAME=
PORT_ALIAS=
PORT_ADMIN=
PORT_STATUS=
PORT_STATUS_CHANGE=
PORT_POE=
PORT_TYPE=
MODULE=
VLAN=
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INT_DESCR: $INT_DESCR"${RESET} >> $LOG
PORT=$INTERFACE
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}PORT: $PORT"${RESET} >> $LOG
PORT_NAME=$(echo "$INT_DESCR" | egrep --color=never "^$PORT;;" | egrep --color=never -o ';;.+$' | sed 's/;//g')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}PORT_NAME: $PORT_NAME"${RESET} >> $LOG
PORT_ALIAS=$(echo "$INT_ALIAS" | egrep --color=never "^$PORT;;" | egrep --color=never -o ';;.+$' | sed 's/;//g')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}PORT_ALIAS: $PORT_ALIAS"${RESET} >> $LOG
# read -p "Press any key to continue. 908 " DEBUG #DEBUG
if [[ -z "$PORT_ALIAS" ]]
	then
		PORT_ALIAS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT port_name FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE (device_id='$DEVICE_ID' OR endpoint_id='$DEVICE_ID') and is_vlan='1' and port_name='$PORT_NAME';"`
fi
# read -p "Press any key to continue. 909 " DEBUG #DEBUG
PORT_ALIAS=$(echo "$PORT_ALIAS" | sed 's/[Vv][Ll][Aa][Nn]//g' | sed 's/_//g')
PORT_ADMIN=$(echo "$INT_ADMIN" | egrep --color=never "^$PORT;;" | egrep --color=never -o ';;.+$' | sed 's/;//g')
if [[ "$PORT_ADMIN" == "1" ]]
	then
		PORT_ADMIN="enable"
	else
		PORT_ADMIN="disable"
fi
PORT_STATUS=$(echo "$INT_STATUS" | egrep --color=never "^$PORT;;" | egrep --color=never -o ';;.+$' | sed 's/;//g')
if [[ "$PORT_STATUS" == "1" ]]
	then
		PORT_STATUS="up"
	else
		PORT_STATUS="down"
fi
PORT_STATUS_CHANGE=$(echo "$INT_STATUS_CHANGE" | egrep --color=never "^$PORT;;" | egrep --color=never -o ';;.+$' | sed 's/;//g' | sed 's/[0-9]\{2\}$//g')
if [[ -z "$PORT_STATUS_CHANGE" ]]
	then
		PORT_STATUS_CHANGE="0"
fi
PORT_POE=$(echo $INT_POE | egrep --color=never ";;$PORT;;" | egrep --color=never -o ';;[0-9]$' | sed 's/;//g')
if [[ "$PORT_POE" == "1" ]]
	then
		PORT_POE="enable"
	else
		PORT_POE="disable"
fi
PORT_TYPE=$(echo "$INT_TYPE" | egrep --color=never "^$PORT;;" | egrep --color=never -o ';;.+$' | sed 's/;//g' | sed 's/.*=\s*[A-Za-z0-9]*\:\s*\(.*\)([0-9]*)$/\1/g')
if [[ -z "$PORT_TYPE" ]]
	then
		PORT_TYPE="unknown"
fi
MODULE=$(echo $INT_POE | egrep --color=never ";;$PORT;;" | egrep --color=never -o '^[0-9]{1,2};;' | sed 's/;//g')
if [[ -z "$MODULE" ]]
	then
		MODULE="0"
		PORT_POE="none"
fi
VLAN=$(echo "$PORT_NAME" | egrep --color=never --ignore-case 'vlan' | sed 's/[Vv][Ll][Aa][Nn]//g' | sed 's/_//g' | egrep --color=never -o '[0-9]{1,4}')
if [[ -z "$VLAN" ]]
	then
		VLAN="0"
fi
case $PORT
	in
		"DEFAULT"*|"Default"|"default")
			VLAN="1";;
		"TRK"*|"Trk"*|"trk"*)
			VLAN="0";;
esac
if [[ "$PORT" -ge "1000" ]]
	then
		VLAN=$(echo "$PORT_NAME" | sed 's/[Vv][Ll][Aa][Nn]//g' | sed 's/_//g')
fi
if [[ -z "$VLAN" ]]
	then
		VLAN="0"
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP Address: $IP"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Device ID: $DEVICE_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port: $PORT"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port Admin Status: $PORT_ADMIN"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port Status: $PORT_STATUS"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Last port status change in seconds: $PORT_STATUS_CHANGE"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port PoE: $PORT_POE"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port Type: $PORT_TYPE"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Module ID: $MODULE"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port name: $PORT_NAME"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port alias: $PORT_ALIAS"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}VLAN: $VLAN"${RESET} >> $LOG
}

ADD_MYSQL_INTERFACE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the interace to the $INTERFACE_TABLE table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $INTERFACE_TABLE(device_id,endpoint_id,port,port_admin,port_status,port_status_change,port_poe,module,port_name,port_alias,port_type,vlan,updated,added) VALUES('$DEVICE_ID','$DEVICE_ID','$PORT','$PORT_ADMIN','$PORT_STATUS','$PORT_STATUS_CHANGE','$PORT_POE','$MODULE','$PORT_NAME',"$PORT_ALIAS",'$PORT_TYPE','$VLAN',NOW(),NOW());
EOF
# read -p "Press any key to continue. 916 " DEBUG #DEBUG
}

UPDATE_MYSQL_INTERFACE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $INTERFACE_TABLE with ID $INTERFACE_ID"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $INTERFACE_TABLE SET port_name='$PORT_NAME',port_admin='$PORT_ADMIN',port_status='$PORT_STATUS',port_status_change='$PORT_STATUS_CHANGE',port_poe='$PORT_POE',module='$MODULE',port_alias="$PORT_ALIAS",port_type='$PORT_TYPE',vlan='$VLAN',updated=NOW() WHERE id='$INTERFACE_ID';
EOF
# read -p "Press any key to continue. 917 " DEBUG #DEBUG
}

UPDATE_DEVICE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the interface check for device with ID $DEVICE_ID"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE SET interface_check=NOW(),ping_check=NOW() WHERE ip='$IP';
EOF
}

CLEANUP_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Cleaning up the interface types"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $INTERFACE_TABLE set port_type='vlan',is_vlan='1' WHERE port_type LIKE '%propvirtual%' OR port_type LIKE '%vlan%';
UPDATE $INTERFACE_TABLE set port_type='vlan',is_vlan='1',vlan=REPLACE(port_name,'eth0.','') WHERE port_name LIKE 'eth%.%';
UPDATE $INTERFACE_TABLE set port_type='bridge' WHERE port_name LIKE 'br%.%';
UPDATE $INTERFACE_TABLE set port_type='loopback' WHERE port_type LIKE '%loopback%';
UPDATE $INTERFACE_TABLE set port_type='lag' WHERE port_type LIKE '%8023ad%';
UPDATE $INTERFACE_TABLE set port_type='ethernet' WHERE port_type LIKE '%ethernet%';
UPDATE $INTERFACE_TABLE SET port_alias=port_name WHERE port_alias='';
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started."${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution."${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked."${RESET} >> $LOG

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

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG

if [[ -z "$MANUAL_RUN" ]]
	then
		IPS=$DEVICE_IPS
fi
CURRENT_TABLE=$DEVICE_TABLE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on Devices"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
INTERFACE_CHECK

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG

if [[ -z "$MANUAL_RUN" ]]
	then
		IPS=$ENDPOINT_IPS
fi
CURRENT_TABLE=$ENDPOINT_TABLE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on Endpoints"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}========="${RESET} >> $LOG
INTERFACE_CHECK

CLEANUP_DATABASE

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file."${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
