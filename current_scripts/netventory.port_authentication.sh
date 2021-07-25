#!/bin/bash
#Filename: netventory.port_authentication.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# expect-tcl
# mariadb-server/mysqld
# net-snmp
# net-snmp-utils
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="netventory.port_authentication"
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
SNMP_TIMEOUT="0.2"
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
PORT_AUTH_TABLE="port_auth"
INTERFACE_TABLE="interface"
OID_TABLE="oid"
USER_TABLE="user"
ENDPOINT_TABLE="endpoint"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
PORT_AUTH_FILE="$WORKING_DIR/port_auth"
PORT_AUTH_MAC_FILE="$WORKING_DIR/port_auth_mac"
DOMAIN="wvcmsdom"
DOMAIN_UPPER=${DOMAIN^^}
DOMAIN_LOWER=${DOMAIN,,}

LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"

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
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND (manufacturer='hp' OR manufacturer LIKE '%hew%pac%') AND ping_check > (NOW() - INTERVAL 30 DAY) AND ip NOT LIKE '169.%.%.%';"`
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
}

GET_INFO ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the necessary information for $IP"${RESET} >> $LOG
OID_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $OID_TABLE.dot1x_auth_method,$OID_TABLE.dot1x_session_time,$OID_TABLE.dot1x_term_cause,$OID_TABLE.dot1x_username,$OID_TABLE.dot1x_mac,$OID_TABLE.int_alias FROM $LOCAL_DATABASE.$OID_TABLE LEFT JOIN $LOCAL_DATABASE.$DEVICE_TABLE ON $LOCAL_DATABASE.$OID_TABLE.id=$DEVICE_TABLE.oid_id WHERE $DEVICE_TABLE.id='$DEVICE_ID';"`)
OID_AUTH_METHOD=${OID_ARRAY[0]}
OID_SESSION_TIME=${OID_ARRAY[1]}
OID_TERM_CAUSE=${OID_ARRAY[2]}
OID_USERNAME=${OID_ARRAY[3]}
OID_MAC=${OID_ARRAY[4]}
OID_INT_ALIAS=${OID_ARRAY[5]}
OID_PORT_AUTH=$(echo "$OID_AUTH_METHOD" | sed 's/\.[0-9]$//g')
PORT_AUTH=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -O nt $IP $OID_PORT_AUTH)
PORT_AUTH_MAC=$(snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -O n0 $IP $OID_MAC | grep --color=never --invert-match "No Such")
}

GET_CLIENT_INFO ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the client info for port $PORT"${RESET} >> $LOG
INTERFACE_ID=
USER_ID=
ENDPOINT_ID=
AUTH_METHOD=
SESSION_TIME=
TERM_CAUSE=
CLIENT_NAME=
MAC_ADDRESS=
FULL_NAME=
INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE device_id='$DEVICE_ID' AND port='$PORT';"`
if [[ -z "$INTERFACE_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Could not find an Interface ID. Moving on"${RESET} >> $LOG
		continue
fi
AUTH_METHOD=$(echo "$PORT_AUTH" | grep --color=never "$OID_AUTH_METHOD.$PORT =" | egrep --color=never -o '\:\s.+$' | sed 's/^\:\s//g' | sed 's/"//g')
case $AUTH_METHOD
	in
		"1")
			AUTH_METHOD="Remote Server";;
		"2")
			AUTH_METHOD="Local Server";;
esac
SESSION_TIME=$(echo "$PORT_AUTH" | grep --color=never "$OID_SESSION_TIME.$PORT =" | egrep --color=never -o '\=\s.+$' | sed 's/^\=\s//g' | sed 's/"//g' | sed 's/[0]\{1,2\}$//g')
TERM_CAUSE=$(echo "$PORT_AUTH" | grep --color=never "$OID_TERM_CAUSE.$PORT =" | egrep --color=never -o '\:\s.+$' | sed 's/^\:\s//g' | sed 's/"//g')
case $TERM_CAUSE
	in
		"1")
			TERM_CAUSE="Supplicant Logoff";;
		"2")
			TERM_CAUSE="Port Failure";;
		"3")
			TERM_CAUSE="Supplicant Restart";;
		"4")
			TERM_CAUSE="Reauth Failed";;
		"5")
			TERM_CAUSE="Auth Control Force Unauth";;
		"6")
			TERM_CAUSE="Port Reinit";;
		"7")
			TERM_CAUSE="Port Admin Disabled";;
		"999")
			TERM_CAUSE="Not Terminated Yet";;
esac
CLIENT_NAME=$(echo "$PORT_AUTH" | grep --color=never "$OID_USERNAME.$PORT =" | egrep --color=never -o '\:\s.+$' | sed 's/^\:\s//g' | sed 's/"//g' | sed 's/host//g'  | sed "s/$DOMAIN//g"  | sed "s/$DOMAIN_UPPER//g"  | sed "s/$DOMAIN_LOWER//g" | sed 's/\\//g' | sed 's/\///g' | sed 's/\.$//g' | sed 's/^\.//g')
MAC_ADDRESS=$(echo "$PORT_AUTH_MAC" | grep --color=never "$OID_MAC.$PORT =" | egrep --color=never -o '\:\s.+$' | sed 's/^\:\s//g' | sed 's/"//g' | sed 's/\([A-Fa-f0-9]\)\s\([A-Fa-f0-9]\)/\1\:\2/g' | sed 's/ //g')
MAC_ADDRESS=${MAC_ADDRESS,,}
USER_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$USER_TABLE WHERE username='$CLIENT_NAME';"`
if [[ -z "$USER_ID" ]]
	then
		USER_ID="NULL"
	else
		FULL_NAME=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT concat(first_name,' ',last_name) FROM $LOCAL_DATABASE.$USER_TABLE WHERE id='$USER_ID';"`
fi
if [[ -n "$CLIENT_NAME" ]]
	then
		ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE hostname='$CLIENT_NAME' ORDER BY updated DESC LIMIT 1;"`
		if [[ -z "$ENDPOINT_ID" ]]
			then
				ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE mac='$MAC_ADDRESS';"`
		fi
		if [[ -z "$ENDPOINT_ID" ]]
			then
				ENDPOINT_ID="NULL"
		fi
	else
		ENDPOINT_ID="NULL"
fi		
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface ID: $INTERFACE_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User ID: $USER_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Auth Method: $AUTH_METHOD"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Session Time in seconds: $SESSION_TIME"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Termination Cause: $TERM_CAUSE"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Client Name: $CLIENT_NAME"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}MAC_Address: $MAC_ADDRESS"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Full Name: $FULL_NAME"${RESET} >> $LOG
}

UPDATE_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
PORT_AUTH_ID=
PORT_AUTH_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$PORT_AUTH_TABLE WHERE device_id='$DEVICE_ID' AND interface_id='$INTERFACE_ID' AND mac='$MAC_ADDRESS';"`
if [[ -z "$PORT_AUTH_ID" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $PORT_AUTH_TABLE(device_id,interface_id,users_id,endpoint_id,auth_method,session_time,term_cause,client_name,mac,updated,added) VALUES('$DEVICE_ID','$INTERFACE_ID',$USER_ID,$ENDPOINT_ID,'$AUTH_METHOD','$SESSION_TIME','$TERM_CAUSE','$CLIENT_NAME','$MAC_ADDRESS',NOW(),NOW());
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $PORT_AUTH_TABLE SET users_id=$USER_ID,endpoint_id=$ENDPOINT_ID,auth_method='$AUTH_METHOD',session_time='$SESSION_TIME',term_cause='$TERM_CAUSE',client_name='$CLIENT_NAME',mac='$MAC_ADDRESS',updated=NOW() WHERE id='$PORT_AUTH_ID';
EOF
fi
}

UPDATE_SWITCHPORT ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the name on the switch port"${RESET} >> $LOG
snmpset -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $OID_INT_ALIAS.$PORT s "$FULL_NAME" &> /dev/null
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
fi
for IP in $IPS
	do
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ====================" >> $LOG
		if ping -c 1 -W 1 $IP &> /dev/null
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking IP $IP"${RESET} >> $LOG
				rm -Rf $FILE &> /dev/null
				GET_DEVICE_ID
				GET_SNMP_CREDS
				GET_INFO
				if [[ -n "$PORT_AUTH_MAC" ]]
					then
						PORTS=$(echo $PORT_AUTH_MAC | egrep --color=never -o '\.[0-9]{1,4}\s\=' | sed 's/ \=//g' | sed 's/\.//g' | sort -u)
						for PORT in $PORTS
							do
								echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
								GET_CLIENT_INFO
								UPDATE_DATABASE
								if [[ -n "$FULL_NAME" ]]
									then
										UPDATE_SWITCHPORT
									elif [[ -n "$CLIENT_NAME" ]]
										then
											if [[ "$CLIENT_NAME" == *"PRINTER"* ]]
												then
													FULL_NAME="Printer"
												else
													FULL_NAME=$CLIENT_NAME
											fi
											UPDATE_SWITCHPORT
								fi
								# read -p "Press any key to continue" DEBUG
						done
						echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
					else
						# echo -e ${YELLOWF}"Could not find any results for $IP"${RESET}
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}No results on this switch"${RESET} >> $LOG
				fi
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is not reachable. Moving on"${RESET} >> $LOG
		fi
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
