#!/bin/bash
#Filename: netventory.update_dhcp_network.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="netventory.update_dhcp_network"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | egrep ^mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | egrep ^mysql_password: | sed 's/mysql_password://g')
LOCAL_DATABASE="netventory"
NETWORK_TABLE="network"
CIDR_TABLE="cidr"
DHCP_TABLE="dhcp"
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

SUBNET_16_TO_24 ()
{
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Looking for subnets with a CIDR of /$CIDR"${RESET} >> $LOG
SELECT_IDS
if [[ -n "$IDS" ]]
	then
		for ID in $IDS
			do
				GET_INFO
				COUNTER=$COUNTER_START
				while [[ "$COUNTER" > "0" ]]
					do
						FULL_SUBNET=$NETWORK_OCT_1.$NETWORK_OCT_2.$NETWORK_OCT_3.$NETWORK_OCT_4/$CIDR
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Working on Network: $FULL_SUBNET"${RESET} >> $LOG
						echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Network ID: $ID"${RESET} >> $LOG
						UPDATE_LARGE_SUBNET
						NETWORK_OCT_3=$((NETWORK_OCT_3+1))
						COUNTER=$((COUNTER-1))
						# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
				done
		done
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}No networks found in the network table for /$CIDR"${RESET} >> $LOG
fi
}

SUBNET_25_TO_30 ()
{
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Looking for subnets with a CIDR of /$CIDR"${RESET} >> $LOG
SELECT_IDS
if [[ -n "$IDS" ]]
	then
		for ID in $IDS
			do
				GET_INFO
				FULL_SUBNET=$NETWORK_OCT_1.$NETWORK_OCT_2.$NETWORK_OCT_3.$NETWORK_OCT_4/$CIDR
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Working on Network: $FULL_SUBNET"${RESET} >> $LOG
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Network ID: $ID"${RESET} >> $LOG
				TOTAL_IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT usable_ips FROM $LOCAL_DATABASE.$CIDR_TABLE WHERE cidr='$CIDR';"`
				HIGHEST_USABLE_IP=$((NETWORK_OCT_4+TOTAL_IPS))
				UPDATE_SMALL_SUBNET
		done
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}No networks found in the network table for /$CIDR"${RESET} >> $LOG
fi
}

SELECT_IDS ()
{
IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE cidr_id='$CIDR' AND TYPE='LAN' GROUP BY network;"`
}

GET_INFO ()
{
NETWORK=
NETWORK=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT network FROM $LOCAL_DATABASE.$NETWORK_TABLE WHERE id='$ID';"`
NETWORK_OCT_1=$(echo "$NETWORK" | egrep --color=never -o '^[0-9]{1,3}\.' | sed 's/\.//g')
NETWORK_OCT_2=$(echo "$NETWORK" | egrep --color=never -o '^[0-9]{1,3}\.[0-9]{1,3}' | sed 's/^[0-9]\{1,3\}\.//g')
NETWORK_OCT_3=$(echo "$NETWORK" | egrep --color=never -o '[0-9]{1,3}\.[0-9]{1,3}$' | sed 's/\.[0-9]\{1,3\}$//g')
NETWORK_OCT_4=$(echo "$NETWORK" | egrep --color=never -o '\.[0-9]{1,3}$' | sed 's/\.//g')
}

UPDATE_LARGE_SUBNET ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating IPs with the network of $FULL_SUBNET"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DHCP_TABLE SET network_id='$ID' WHERE ip LIKE '$NETWORK_OCT_1.$NETWORK_OCT_2.$NETWORK_OCT_3.%' AND (updated >= (CURDATE() - interval 7 day));
EOF
}

UPDATE_SMALL_SUBNET ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating IPs with the network of $FULL_SUBNET"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $DHCP_TABLE SET network_id='$ID' WHERE ip > '$NETWORK_OCT_1.$NETWORK_OCT_2.$NETWORK_OCT_3.$NETWORK_OCT_4' AND ip < '$NETWORK_OCT_1.$NETWORK_OCT_2.$NETWORK_OCT_3.$HIGHEST_USABLE_IP' AND (updated >= (CURDATE() - interval 7 day));
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started."${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution."${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked."${RESET} >> $LOG

# Subnet with a CIDR of /17 through /24
CIDR="24"
COUNTER_START="1"
while [[ "$CIDR" > "16" ]]
	do
		SUBNET_16_TO_24
		CIDR=$((CIDR-1))
		COUNTER_START=$(($COUNTER_START * 2))
done

# Subnet with a CIDR of /25 through /30
CIDR="30"
while [[ "$CIDR" > "24" ]]
	do
		SUBNET_25_TO_30
		CIDR=$((CIDR-1))
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file."${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
