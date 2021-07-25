#!/bin/bash
#Filename: netventory.interfaces.endpoint.sh
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

SCRIPT_NAME="netventory.interfaces.endpoint"
SCRIPT_CAT="netventory"

IPS=$1

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
SNMP_TABLE="snmp"
SNMP_TIMEOUT="5"
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
OID_TABLE="oid"
INTERFACE_TABLE="interface"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
# ONE_DAY_AGO="1 days ago"
# ONE_DAY_AGO_EPOCH=$(date --date "$ONE_DAY_AGO" +'%s')
ENDPOINTS_PER_RUN="30"

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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint IPs"${RESET} >> $LOG
NUMBER_OF_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT 	COUNT(ip) FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 7 DAY) AND ip NOT LIKE '169.%.%.%' order by interface_check;"`
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 7 DAY) AND ip NOT LIKE '169.%.%.%' order by interface_check LIMIT $ENDPOINTS_PER_RUN;"`
}

GET_ENDPOINT_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint ID for $IP"${RESET} >> $LOG
ENDPOINT_ID=
ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
if [[ -z "$ENDPOINT_ID" ]]
	then
		DEVICE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
fi
if [[ -n "$DEVICE_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is a device. Moving on"${RESET} >> $LOG
		continue
fi
if [[ -z "$ENDPOINT_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP does not exist in the database yet. Moving on"${RESET} >> $LOG
		continue
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
}

GET_INTERFACE_DATE ()
{
INTERFACE_UPDATE=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT updated FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE endpoint_id='$ENDPOINT_ID' AND updated < (NOW() - INTERVAL 1 DAY) ORDER BY updated DESC LIMIT 1;"`
if [[ -z "$INTERFACE_UPDATE" ]]
	then
		NEW_ENDPOINT=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT updated FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE endpoint_id='$ENDPOINT_ID';"`
		if [[ -z "$NEW_ENDPOINT" ]]
			then
				INTERFACE_UPDATE="1"
		fi
fi		
# INTERFACE_UPDATE_EPOCH=$(date --date "$INTERFACE_UPDATE" +'%s')
}

GET_SNMP_CREDS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the SNMP credentials for $IP"${RESET} >> $LOG
# read -p "Press any key to continue. Endpoint ID: $ENDPOINT_ID " DEBUG
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
}

GET_DATA_1 ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the necessary variables"${RESET} >> $LOG
INT_DESCR=
OID_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $OID_TABLE.int_descr,$OID_TABLE.int_alias,$OID_TABLE.int_admin,$OID_TABLE.int_status,$OID_TABLE.int_status_change,$OID_TABLE.int_poe,$OID_TABLE.int_type FROM $LOCAL_DATABASE.$OID_TABLE LEFT JOIN $LOCAL_DATABASE.$ENDPOINT_TABLE ON $LOCAL_DATABASE.$OID_TABLE.id=$ENDPOINT_TABLE.oid_id WHERE $ENDPOINT_TABLE.id='$ENDPOINT_ID';"`)
OID_INT_DESCR=${OID_ARRAY[0]}
OID_INT_ALIAS=${OID_ARRAY[1]}
OID_INT_ADMIN=${OID_ARRAY[2]}
OID_INT_STATUS=${OID_ARRAY[3]}
OID_INT_STATUS_CHANGE=${OID_ARRAY[4]}
OID_INT_POE=${OID_ARRAY[5]}
OID_INT_TYPE=${OID_ARRAY[6]}
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the Interface variable"${RESET} >> $LOG
INT_DESCR=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_INT_DESCR | sed '/loopback/d' | sed '/oobm/d' | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*.*:\s*\(.*\)$/\1;;\2/g' | sed '/End of MIB/d')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface Description: $INT_DESCR"${RESET} >> $LOG
}

GET_DATA_2 ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the necessary variables"${RESET} >> $LOG
INT_DESCR=
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface Alias variable"${RESET} >> $LOG
INT_ALIAS=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_INT_ALIAS | sed '/loopback/d' | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*.*:\s*\(.*\)$/\1;;\2/g' | sed '/End of MIB/d')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface Admin Status variable"${RESET} >> $LOG
INT_ADMIN=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_INT_ADMIN | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*.*:\s*.*\([12]\))$/\1;;\2/g' | sed '/End of MIB/d')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface status variable"${RESET} >> $LOG
INT_STATUS=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_INT_STATUS | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*[A-Za-z]*\:\s*.*(\([0-9]*\)).*$/\1;;\2/g' | sed '/End of MIB/d')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface status changes variable"${RESET} >> $LOG
INT_STATUS_CHANGE=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_INT_STATUS_CHANGE | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*[A-Za-z]*\:\s*.*(\([0-9]*\)).*$/\1;;\2/g' | sed '/End of MIB/d')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface PoE variable"${RESET} >> $LOG
INT_POE=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_INT_POE | sed 's/^.*\.\([0-9]\{1,2\}\)\.\([0-9]\{1,6\}\)\s*=\s*.*:\s*\(.*\)$/\1;;\2;;\3/g' | sed '/End of MIB/d')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the interface type variable"${RESET} >> $LOG
INT_TYPE=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_INT_TYPE | sed 's/^.*\.\([0-9]\{1,6\}\)\s*=\s*[A-Za-z0-9]*\:\s*\(.*\)([0-9]*)$/\1;;\2/g' | sed '/End of MIB/d')
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface Alias: $INT_ALIAS"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface Admin Status: $INT_ADMIN"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface status: $INT_STATUS"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface status changes: $INT_STATUS_CHANGE"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface PoE: $INT_POE"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface type: $INT_TYPE"${RESET} >> $LOG
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
PORT=$INTERFACE
PORT_NAME=$(echo "$INT_DESCR" | egrep --color=never "^$PORT;;" | egrep --color=never -o ';;.+$' | sed 's/;//g')
PORT_ALIAS=$(echo "$INT_ALIAS" | egrep --color=never "^$PORT;;" | egrep --color=never -o ';;.+$' | sed 's/;//g')
if [[ -z "$PORT_ALIAS" ]]
	then
		PORT_ALIAS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT port_name FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE endpoint_id='$ENDPOINT_ID' and is_vlan='1' and port_name='$PORT_NAME';"`
fi
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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the interace to the interface table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $INTERFACE_TABLE(endpoint_id,port,port_admin,port_status,port_status_change,port_poe,module,port_name,port_alias,port_type,vlan,updated,added) VALUES('$ENDPOINT_ID','$PORT','$PORT_ADMIN','$PORT_STATUS','$PORT_STATUS_CHANGE','$PORT_POE','$MODULE','$PORT_NAME',"$PORT_ALIAS",'$PORT_TYPE','$VLAN',NOW(),NOW());
EOF
}

UPDATE_MYSQL_INTERFACE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the interface with ID $INTERFACE_ID"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $INTERFACE_TABLE SET port_name='$PORT_NAME',port_admin='$PORT_ADMIN',port_status='$PORT_STATUS',port_status_change='$PORT_STATUS_CHANGE',port_poe='$PORT_POE',module='$MODULE',port_alias="$PORT_ALIAS",port_type='$PORT_TYPE',vlan='$VLAN',updated=NOW() WHERE id='$INTERFACE_ID';
EOF
}

UPDATE_ENDPOINT ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the interface with ID $INTERFACE_ID"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $ENDPOINT_TABLE SET interface_check=NOW() WHERE id='$ENDPOINT_ID';
EOF
}

CLEANUP_DATABASE ()
{
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Setting the VLAN flag in the database"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
# UPDATE $INTERFACE_TABLE SET is_vlan=1 WHERE port_type LIKE '%Virtual%' OR port_type='vlan';
# EOF
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Setting the VLAN id in the database"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
# UPDATE $INTERFACE_TABLE SET vlan='$VLAN' WHERE port_name LIKE '%vlan%';
# EOF
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Removing the word vlan from the port alias name"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
# UPDATE $INTERFACE_TABLE set port_alias=REPLACE(port_alias,'_VLAN','') WHERE port_alias LIKE '%_vlan%';
# EOF
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

if [[ -z "$IPS" ]]
	then
		GET_IPS
	else
		INTERFACE_UPDATE="2"
fi
if [[ -z "$IPS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs or Hostnames provided"${RESET} >> $LOG
		echo
		# echo -e ${REDF}"No IPs or Hostnames provided. This script is exiting."${RESET}
		EXIT_CODE="85"
		EXIT_FUNCTION
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking $ENDPOINTS_PER_RUN endpoints out of $NUMBER_OF_IPS"${RESET} >> $LOG
fi

for IP in $IPS
	do
		if ping -c 1 -W 1 $IP &> /dev/null
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking IP $IP"${RESET} >> $LOG
				GET_ENDPOINT_ID
				UPDATE_ENDPOINT
				GET_SNMP_CREDS
				GET_DATA_1
				# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interfaces Description: $INT_DESCR"${RESET} >> $LOG
				if [[ -n "$INT_DESCR" ]]
					then
						GET_DATA_2
						INTERFACES=
						INTERFACES=$(echo "$INT_DESCR" | egrep --color=never -o '^[0-9]{1,6};;' | sed 's/;//g')
						for INTERFACE in $INTERFACES
							do
								echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on interface $INTERFACE"${RESET} >> $LOG
								GET_INFO
								INTERFACE_ID=
								INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE endpoint_id='$ENDPOINT_ID' AND port='$PORT';"`
								echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface ID: $INTERFACE_ID"${RESET} >> $LOG
								if [[ -z "$INTERFACE_ID" ]]
									then
										ADD_MYSQL_INTERFACE
									else
										UPDATE_MYSQL_INTERFACE
								fi
						done
					else
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}No interfaces to update"${RESET} >> $LOG
				fi
				echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		fi
done

CLEANUP_DATABASE

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file."${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
