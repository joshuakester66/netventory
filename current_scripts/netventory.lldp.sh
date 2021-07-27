#!/bin/bash
#Filename: netventory.lldp.sh
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

SCRIPT_NAME="netventory.lldp"
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
LLDP_TABLE="lldp"
OID_TABLE="oid"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
INTERFACE_TABLE="interface"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LLDP_INFO_FILE="$WORKING_DIR/lldp_file"
LLDP_ADDRESS_FILE="$WORKING_DIR/lldp_address_file"

LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"

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
NUMBER_OF_DEVICES=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping > (NOW() - INTERVAL 30 DAY) AND category='network' ORDER BY lldp_check,ip;"`
COUNT_PER_RUN=$(expr $NUMBER_OF_DEVICES / $COUNT_DIVISION)
if [[ "$COUNT_PER_RUN" == "0" ]]
	then
		COUNT_PER_RUN=$NUMBER_OF_DEVICES
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$NUMBER_OF_DEVICES total eligible devices found"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting up to $COUNT_PER_RUN device IPs"${RESET} >> $LOG
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping > (NOW() - INTERVAL 30 DAY) AND category='network' ORDER BY lldp_check,ip LIMIT $COUNT_PER_RUN;"`
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

GET_LLDP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the LLDP info"${RESET} >> $LOG
OID_ARRAY=(`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $OID_TABLE.lldp,$OID_TABLE.LLDP_ADDRESS FROM $LOCAL_DATABASE.$OID_TABLE LEFT JOIN $LOCAL_DATABASE.$DEVICE_TABLE ON $LOCAL_DATABASE.$OID_TABLE.id=$DEVICE_TABLE.oid_id WHERE $DEVICE_TABLE.id='$DEVICE_ID';"`)
OID_LLDP=${OID_ARRAY[0]}
OID_LLDP_ADDRESS=${OID_ARRAY[1]}
snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -O qn $IP $OID_LLDP > $LLDP_INFO_FILE.$IP
snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -O qn $IP $OID_LLDP_ADDRESS > $LLDP_ADDRESS_FILE.$IP
if [[ ! -s "$LLDP_ADDRESS_FILE.$IP" ]]
	then
		OID_LLDP_ADDRESS=$(echo "$OID_LLDP_ADDRESS" | sed 's/\.0$//g')
		snmpwalk -t $SNMP_TIMEOUT -v $SNMP_VERSION -c $SNMP_COMMUNITY -O qn $IP $OID_LLDP_ADDRESS > $LLDP_ADDRESS_FILE.$IP
fi
}

GET_INFO ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the necessary information for $IP"${RESET} >> $LOG
LOCAL_DEVICE=$IP
LOCAL_PORT=$(echo "$INTERFACE" | sed 's/\..*$//g')
DEVICE_NAME=
IP_ADDRESS=
MAC_ADDRESS=
DESCRIPTION=
REMOTE_PORT=
GET_INTERFACE
# DEVICE_NAME=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o "\.9\.0\.$INTERFACE\s.+$" | sed "s/^\.9\.0\.$INTERFACE\s//g" | sed 's/\"//g' | sed 's/ $//g')
DEVICE_NAME=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o "\.9\.[0-9]+\.$INTERFACE\s.+$" | sed "s/^\.9\.[0-9]*\.$INTERFACE\s//g" | sed 's/\"//g' | sed 's/ $//g')
# IP_ADDRESS=$(cat $LLDP_ADDRESS_FILE.$IP | egrep --color=never -o "\.$INTERFACE\.1\.4\..+\s" | sed "s/\.$INTERFACE\.1\.4\.//g" | sed 's/ //g')
IP_ADDRESS=$(cat $LLDP_ADDRESS_FILE.$IP | egrep --color=never -o "\.$INTERFACE\.1\.4\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\s" | sed "s/\.$INTERFACE\.1\.4\.//g")
# MAC_ADDRESS=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o "\.5\.0\.$INTERFACE\s.+$" | sed "s/^\.5\.0\.$INTERFACE\s//g" | sed 's/\"//g' | sed 's/ $//g' | sed 's/ /:/g' | egrep --color=never '[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}')
MAC_ADDRESS=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o "\.5\.[0-9]+\.$INTERFACE\s.+$" | sed "s/^\.5\.[0-9]*\.$INTERFACE\s//g" | sed 's/\"//g' | sed 's/ $//g' | sed 's/ /:/g' | egrep --color=never '[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}')
if [[ -z "$MAC_ADDRESS" ]]
	then
		# MAC_ADDRESS=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o "\.7\.0\.$INTERFACE\s.+$" | sed "s/^\.7\.0\.$INTERFACE\s//g" | sed 's/\"//g' | sed 's/ $//g' | sed 's/ /:/g' | egrep --color=never '[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}')
		MAC_ADDRESS=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o "\.7\.[0-9]+\.$INTERFACE\s.+$" | sed "s/^\.[0-9]*\.0\.$INTERFACE\s//g" | sed 's/\"//g' | sed 's/ $//g' | sed 's/ /:/g' | egrep --color=never '[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}')
fi		
MAC_ADDRESS=${MAC_ADDRESS,,}
# DESCRIPTION=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o "\.10\.[0-9]+\.$INTERFACE\s.+$" | sed "s/^\.10\.[0-9]*\.$INTERFACE\s//g" | sed 's/\"//g' | sed 's/ $//g')
DESCRIPTION=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o "\.10\.[0-9]+\.$INTERFACE\s.+$" | sed "s/^\.10\.[0-9]*\.$INTERFACE\s//g" | sed 's/\"//g' | sed 's/\s*$//g' | sed 's/^\s*//g')
REMOTE_PORT=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o "\.8\.[0-9]+\.$INTERFACE\s.+$" | sed "s/^\.8\.[0-9]*\.$INTERFACE\s//g" | sed 's/\"//g' | sed 's/ $//g')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Local Device: $LOCAL_DEVICE"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Device ID: $DEVICE_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Local Port: $LOCAL_PORT"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface ID: $INTERFACE_ID"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Device Name: $DEVICE_NAME"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP address: $IP_ADDRESS"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}MAC address: $MAC_ADDRESS"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Description: $DESCRIPTION"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote Port: $REMOTE_PORT"${RESET} >> $LOG
}

GET_INTERFACE ()
{
INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE device_id='$DEVICE_ID' AND port='$LOCAL_PORT';"`
if [[ -z "$INTERFACE_ID" ]]
	then
		ADD_DATABASE_INTERFACE
		INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$INTERFACE_TABLE WHERE device_id='$DEVICE_ID' AND port='$LOCAL_PORT';"`
fi
}

ADD_DATABASE_INTERFACE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the interface to the interface table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $INTERFACE_TABLE(device_id,port,updated,added) VALUES('$DEVICE_ID','$LOCAL_PORT',NOW(),NOW());
EOF
}

ADD_DATABASE_LLDP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the device to the $LLDP_TABLE table on interface $INTERFACE to the database"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $LLDP_TABLE(interface_id,name,ip_address,mac_address,description,remote_port,updated,added) VALUES('$INTERFACE_ID','$DEVICE_NAME','$IP_ADDRESS','$MAC_ADDRESS','$DESCRIPTION','$REMOTE_PORT',NOW(),NOW());
EOF
}

UPDATE_DATABASE_LLDP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $LLDP_TABLE table for device on interface $INTERFACE in the database"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $LLDP_TABLE SET name='$DEVICE_NAME',ip_address='$IP_ADDRESS',mac_address='$MAC_ADDRESS',description='$DESCRIPTION',remote_port='$REMOTE_PORT',updated=NOW() WHERE id='$DATABASE_EXIST';
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
fi

for IP in $IPS
	do
		if ping -c 1 -W 1 $IP &> /dev/null
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking IP $IP"${RESET} >> $LOG
				GET_DEVICE_ID
				GET_SNMP_CREDS
				GET_LLDP
				# INTERFACES=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o '\.4\.0\.[0-9]+\.[0-9]+\s' | sed 's/\s$//g' | sed 's/^\.4\.0\.//g')
				INTERFACES=$(cat $LLDP_INFO_FILE.$IP | egrep --color=never -o '\.[0-9]+\.[0-9]+\s+"' | sed 's/\s*"//g' | sed 's/^\.//g' | sort --unique)
				for INTERFACE in $INTERFACES
					do
						echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on interface $INTERFACE"${RESET} >> $LOG
						GET_INFO
						DATABASE_EXIST=
						DATABASE_EXIST=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$LLDP_TABLE WHERE interface_id='$INTERFACE_ID' AND (ip_address='$IP_ADDRESS' OR mac_address='$MAC_ADDRESS');"`
						if [[ -z "$DATABASE_EXIST" ]]
							then
								ADD_DATABASE_LLDP
							else
								UPDATE_DATABASE_LLDP
						fi
				done
				UPDATE_DEVICE
				echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is not reachable. Moving on"${RESET} >> $LOG
				UPDATE_DEVICE_NO_PING
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		fi
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file."${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
