#!/bin/bash
#Filename: netventory.get_services.sh
#Description: 
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
#Packages:

# read -p "Press enter to continue. " DEBUG #DEBUG

IPS=$1

SCRIPT_NAME="netventory.get_services"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
EXPECT_LOG="$HOME/scripts/tmp/$SCRIPT_NAME/logs/expect.log"
CREDENTIALS="$HOME/scripts/.credentials"
DATABASE_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
DATABASE_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
DEVICE_SERVICES_TABLE="device_services"
IP_COLUMN="ip"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
IP_FILE="$WORKING_DIR/ip_file"
RESULTS_FILE="$WORKING_DIR/results_file.gnmap"
SERVICE_PORTS="123,21,22,23,135,139,389,443,445,464,53,5722,5785,636,3389"
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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Script has been unlocked"${RESET} >> $LOG
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
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Script has been unlocked"${RESET} >> $LOG
echo ""
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}$SCRIPT_NAME.sh has exited for error $EXIT_CODE"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG
# reset
exit $EXIT_CODE
}

GET_DEVICE_IPS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the device IPs"${RESET} >> $LOG
DEVICES=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ping > (NOW() - INTERVAL 30 DAY) ORDER BY services_check;"`
COUNT_PER_RUN=$(expr $DEVICES / $COUNT_DIVISION)
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting up to $COUNT_PER_RUN device IPs"${RESET} >> $LOG
DEVICE_IPS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ping > (NOW() - INTERVAL 30 DAY) ORDER BY services_check LIMIT $COUNT_PER_RUN;"`
echo "$DEVICE_IPS" | tr "\n" " " > $IP_FILE
}

GET_ENDPOINT_IPS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint IPs"${RESET} >> $LOG
DEVICES=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT COUNT(ip) FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ping > (NOW() - INTERVAL 30 DAY) ORDER BY services_check;"`
COUNT_PER_RUN=$(expr $DEVICES / $COUNT_DIVISION)
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting up to $COUNT_PER_RUN endpoint IPs"${RESET} >> $LOG
ENDPOINT_IPS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ping > (NOW() - INTERVAL 30 DAY) ORDER BY services_check LIMIT $COUNT_PER_RUN;"`
echo "$ENDPOINT_IPS" | tr "\n" " " > $IP_FILE
}

CLEANUP_FILE ()
{
sed -i '/^#/d' $RESULTS_FILE &> /dev/null
sed -i '/Status:/d' $RESULTS_FILE &> /dev/null
sed -i 's/^Host: //g' $RESULTS_FILE &> /dev/null
sed -i 's/\s*()\s*Ports:\s*/::/g' $RESULTS_FILE &> /dev/null
sed -i 's/\([0-9]\{1,5\}\)\/\(open\|closed\|filtered\)\/[A-Za-z]*\/\/[A-Za-z0-9_ -]*[\/]*\(,\)\?\(\s*\)\?/\1_\2::/g' $RESULTS_FILE &> /dev/null
sed -i 's/::$//g' $RESULTS_FILE &> /dev/null
}

GET_INFO ()
{
CURRENT_ID="${CURRENT_TABLE^^}"
for LINE in `cat $RESULTS_FILE`
	do
		DEVICE_ID=
		LINE_ARRAY=($(echo $LINE | sed 's/\:/ /g'))
		ARRAY_LENGTH=${#LINE_ARRAY[@]}
		IP=${LINE_ARRAY[0]}
		ARRAY_COUNTER="1"
		GET_${CURRENT_ID}_ID
		if [[ -z "$DEVICE_ID" ]]
			then
				DEVICE_ID=$ENDPOINT_ID
		fi
		GET_DEVICE_SERVICES_ID
		UPDATE_DEVICE_TABLE
		DATABASE_UPDATE_VAR="UPDATE $DEVICE_SERVICES_TABLE SET "
		let ARRAY_LENGTH-=1
		while [[ "$ARRAY_COUNTER" -le "$ARRAY_LENGTH" ]]
			do
				VAR_UPDATE_PORT=$(echo "${LINE_ARRAY[$ARRAY_COUNTER]}" | sed 's/_.*$//g')
				VAR_UPDATE_STATUS=$(echo "${LINE_ARRAY[$ARRAY_COUNTER]}" | sed 's/^.*_//g')
				if [[ "$ARRAY_COUNTER" == "$ARRAY_LENGTH" ]]
					then
						DATABASE_UPDATE_VAR=${DATABASE_UPDATE_VAR}"port_${VAR_UPDATE_PORT}='$VAR_UPDATE_STATUS'"
					else
						DATABASE_UPDATE_VAR=${DATABASE_UPDATE_VAR}"port_${VAR_UPDATE_PORT}='$VAR_UPDATE_STATUS',"		
				fi
				let ARRAY_COUNTER+=1
		done
		DATABASE_UPDATE_VAR=${DATABASE_UPDATE_VAR}" WHERE device_id='$DEVICE_ID';"
		UPDATE_DATABASE
done
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
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is an endpoint with Endpoint ID: $ENDPOINT_ID. Moving on"${RESET} >> $LOG
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
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $DEVICE_TABLE(ip,updated,added) VALUES('$IP',NOW(),NOW());
EOF
}

GET_ENDPOINT_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint ID for $IP"${RESET} >> $LOG
ENDPOINT_ID=
ENDPOINT_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
if [[ -z "$ENDPOINT_ID" ]]
	then
		DEVICE_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
		if [[ -z "$DEVICE_ID" ]]
			then
				ADD_DEVICE
				DEVICE_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is a device with Device ID: $DEVICE_ID. Moving on"${RESET} >> $LOG
				continue
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$IP is a device with Device ID: $DEVICE_ID. Moving on"${RESET} >> $LOG
				continue
		fi
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
}

GET_DEVICE_SERVICES_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the Device Services ID for Device ID: $DEVICE_ID"${RESET} >> $LOG
DEVICE_SERVICES_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_SERVICES_TABLE WHERE device_id='$DEVICE_ID';"`
if [[ -z "$DEVICE_SERVICES_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP does not exist in the table $DEVICE_SERVICES_TABLE yet. Adding it"${RESET} >> $LOG
		ADD_DEVICE_TO_DEVICE_SERVICES
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the new device services ID"${RESET} >> $LOG
		DEVICE_SERVICES_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_SERVICES_TABLE WHERE device_id='$DEVICE_ID';"`
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Device Services ID: $DEVICE_SERVICES_ID"${RESET} >> $LOG
}

ADD_DEVICE_TO_DEVICE_SERVICES ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the device to the $DEVICE_SERVICES_TABLE table"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $DEVICE_SERVICES_TABLE(device_id,added) VALUES('$DEVICE_ID',NOW());
EOF
}

UPDATE_DEVICE_TABLE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE table for $IP"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE SET services_check=NOW(),updated=NOW() WHERE id='$DEVICE_ID';
EOF
}

UPDATE_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $DEVICE_SERVICES_TABLE table for $IP"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Update Line: $DATABASE_UPDATE_VAR"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
$DATABASE_UPDATE_VAR
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the script for execution"${RESET} >> $LOG
if [[ -f "$LOCK_FILE" ]]
	then
		SCRIPT_RUNNING
	else
		touch $LOCK_FILE
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Script has been locked"${RESET} >> $LOG

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on Devices"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
if [[ -z "$IPS" ]]
	then
		GET_DEVICE_IPS
	else
		IPS=$(echo "$IPS")
		echo "$IPS" > $IP_FILE
fi
CURRENT_TABLE=$DEVICE_TABLE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Running nmap with the command"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}nmap -Pn -n -p $SERVICE_PORTS -iL $IP_FILE -oG $RESULTS_FILE &> /dev/null"${RESET} >> $LOG
nmap -Pn -n -p $SERVICE_PORTS -iL $IP_FILE -oG $RESULTS_FILE &> /dev/null
CLEANUP_FILE
GET_INFO
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on Endpoints"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
if [[ -z "$IPS" ]]
	then
		GET_ENDPOINT_IPS
	else
		IPS=$(echo "$IPS")
		echo "$IPS" > $IP_FILE
fi
CURRENT_TABLE=$ENDPOINT_TABLE
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Running nmap with the command"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}nmap -Pn -n -p $SERVICE_PORTS -iL $IP_FILE -oG $RESULTS_FILE &> /dev/null"${RESET} >> $LOG
nmap -Pn -n -p $SERVICE_PORTS -iL $IP_FILE -oG $RESULTS_FILE &> /dev/null
CLEANUP_FILE
GET_INFO

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the script"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
