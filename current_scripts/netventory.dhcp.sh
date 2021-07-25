#!/bin/bash
#Filename: netventory.dhcp.sh
#Description: 
#Requirements:
# This will require that whatever device this is being run on is set as an IP Helper address by the router
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# procmail (lockfile command)
#
#Command to run tcpdump in rotation in a cron entry in root's crons:
# @reboot /usr/sbin/tcpdump -ne -i eth0 port 67 or 68 -w /tmp/dhcp/%H00/dhcp.%H%M.log -G 60 &
#That command needs to be run as root
#Cron entry for current user
# 3-59/1 * * * * /bin/bash $HOME/scripts/netventory/dhcp.sh
# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="netventory.dhcp"
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
LOCAL_TABLE="dhcp"
IP_COLUMN="ip"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
DHCP_DIRS="/tmp/dhcp/`date +%H00 --date '-1 hour'`
/tmp/dhcp/`date +%H00`"
#DHCP_FILE="/tmp/dhcp/`date +%H00`/dhcp.`date +%H%M --date '-2 min'`.log"
# DHCP_FILE="/tmp/dhcp.`date +%H%M --date '-2 min'`.log"
TEMP_FILE="$WORKING_DIR/dhcp.log.temp"
FILE="$WORKING_DIR/dhcp.log"
FILE2="$WORKING_DIR/file2"
IP_FILE="$WORKING_DIR/dhcp.ip.log"
MAC_FILE="$WORKING_DIR/dhcp.mac.log"
TCPDUMP_COMMAND="/usr/sbin/tcpdump -ne -i eth0 port 67 or 68 -w /tmp/dhcp/%H00/dhcp.%H%M.log -G 60 &"

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

CHECK_TCPDUMP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking if tcpdump is running"${RESET} >> $LOG
TCPDUMP_RUNNING=$(ps aux | grep --color=never tcpdump | grep --color=never --invert-match grep)
if [[ -z "$TCPDUMP_RUNNING" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}tcpdump is not running. This script cannot continue"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}As root try running $TCPDUMP_COMMAND"${RESET} >> $LOG
		EXIT_CODE="65"
		EXIT_FUNCTION
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}tcpdump is running"${RESET} >> $LOG
fi
}

COPY_FILE ()
{
rm $TEMP_FILE &> /dev/null
for DHCP_DIR in $DHCP_DIRS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}converting the dhcp files in $DHCP_DIR to text"${RESET} >> $LOG
		for DHCP_FILE in `ls --color=never $DHCP_DIR`
		    do
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}converting $DHCP_DIR/$DHCP_FILE"${RESET} >> $LOG
		        /usr/sbin/tcpdump -vnes0 -r $DHCP_DIR/$DHCP_FILE &> /dev/null >> $TEMP_FILE
		done
done
# cat $TEMP_FILE | grep --color=never -A 3 "Option 61" | grep --color=never "Option 61\|Option 12\|Option 50" | sed '/length 0ERROR/d' | sed '/0\.0\.0\.0/d' | sed 's/\(Option 61, length [0-9]\{1,2\}:\) ".*:\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)"$/\1 ether \2:\3:\4:\5:\6:\7/g' | sed '/Option 61,.*hardware-type 255/d' | tr -d "\n" | sed 's/$/"/g' | sed 's/""/"/g' | sed 's/\(\s*\)\?[A-Za-z-]* Option 61, length [0-9]\{1,2\}: ether /\n===\n"/g' | tr [:upper:] [:lower:] > $FILE2
# cat $TEMP_FILE | grep --color=never -A 3 "Option 61" | grep --color=never "Option 61\|Option 12\|Option 50" | sed '/length 0ERROR/d' | sed '/0\.0\.0\.0/d' | sed 's/\(Option 61, length [0-9]\{1,2\}:\) ".*:\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)\([A-Za-z0-9]\{2\}\)"$/\1 ether \2:\3:\4:\5:\6:\7/g' | sed '/Option 61,.*hardware-type 255/d' | tr -d "\n" | sed 's/$/"/g' | sed 's/""/"/g' | sed 's/\(\s*\)\?[A-Za-z-]* Option 61, length [0-9]\{1,2\}: ether /\n"/g' | sed 's/\s*[A-Za-z-]* Option 12, length [0-9]\{1,2\}: /;;/g' | sed 's/\s*[A-Za-z-]* Option 50, length [0-9]\{1,2\}: /;;/g' | sed 's/\([A-Za-z0-9]\);;/\1";;/g' | sed 's/;;\([A-Za-z0-9]\)/;;"\1/g' | sed 's/$/"/g' | sed 's/""$/"/g' | sed 's/;;\("\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}"\);;\(.*\)$/;;\3;;\1/g' | sed 's/^\("\([A-Za-z0-9]\{2\}\:\)\{5\}[A-Za-z0-9]\{2\}"\)$/\1;;"";;""/g' | sed 's/^\("\([A-Za-z0-9]\{2\}\:\)\{5\}[A-Za-z0-9]\{2\}"\);;\("\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}"\)$/\1;;"";;\3/g' | sed 's/^\("\([A-Za-z0-9]\{2\}\:\)\{5\}[A-Za-z0-9]\{2\}"\);;\("[^\.][^\.]*"\)$/\1;;\3;;""/g' | sed 's/;;"";;"";;""/;;"";;""/g' | sed '/^"$/d' | tr [:upper:] [:lower:] | sort --unique > $FILE
cat $TEMP_FILE | egrep --color=never -A 3 'Option 61, length [0-9]{1,2}: ether' | grep --color=never "Option 61\|Option 12\|Option 50" | sed '/0\.0\.0\.0/d' | tr -d "\n" | sed 's/$/"/g' | sed 's/""/"/g' | sed 's/\(\s*\)\?[A-Za-z-]* Option 61, length [0-9]\{1,2\}: ether /\n"/g' | sed 's/\s*[A-Za-z-]* Option 12, length [0-9]\{1,2\}: /;;/g' | sed 's/\s*[A-Za-z-]* Option 50, length [0-9]\{1,2\}: /;;/g' | sed 's/\([A-Za-z0-9]\);;/\1";;/g' | sed 's/;;\([A-Za-z0-9]\)/;;"\1/g' | sed 's/$/"/g' | sed 's/""$/"/g' | sed 's/;;\("\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}"\);;\(.*\)$/;;\3;;\1/g' | sed 's/^\("\([A-Za-z0-9]\{2\}\:\)\{5\}[A-Za-z0-9]\{2\}"\)$/\1;;"";;""/g' | sed 's/^\("\([A-Za-z0-9]\{2\}\:\)\{5\}[A-Za-z0-9]\{2\}"\);;\("\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}"\)$/\1;;"";;\3/g' | sed 's/^\("\([A-Za-z0-9]\{2\}\:\)\{5\}[A-Za-z0-9]\{2\}"\);;\("[^\.][^\.]*"\)$/\1;;\3;;""/g' | sed 's/;;"";;"";;""/;;"";;""/g' | sed '/^"$/d' | tr [:upper:] [:lower:] | sort --unique > $FILE
# cat $TEMP_FILE | grep --color=never -B 5 -A 8 -i ': Request\|: Inform' | sed '/ > /d' | sed '/Option 51/d' | sed '/Option 53/d' | sed '/Option 54/d' | sed '/Option 55/d' | sed '/Option 57/d' | sed '/Option 60/d' | sed '/Option 61/d' | sed '/Option 77/d' | sed '/Option 81/d' | sed '/Option 82/d' | sed '/Option 119/d' | sed '/Option 145/d' | sed '/Option 252/d' | sed '/Subnet-Mask, /d' | sed '/Classless-/d' | sed '/-Server/d' | sed '/, Lease-Time/d' | sed '/, RB/d' | sed '/^\s*RB/d' | sed '/Vendor-/d' | sed '/Magic Cookie/d' | sed '/Netbios/d' | sed '/Domain-Name/d' | sed '/Gateway-IP/d' | sed '/NTP/d' | sed 's/^.*Option 61.*ether //g' | sed 's/^.*Option 50.*: //g' | sed 's/^.*Option 12.*: //g' | sed '/^.*Circuit-ID SubOption 1.*: /d' | sed 's/^.*Client-Ethernet-Address //g' | sed 's/^.*Client-IP //g' > $IP_FILE
# cat $TEMP_FILE | grep --color=never -A 3 "Option 61" | grep --color=never "Option 61\|Option 12" | sed '/length 0ERROR/d' | sed '/Option 61,.*hardware-type 255/d' | sed 's/^.*length [0-9]*\: //g' | sed 's/^ether //g' > $MAC_FILE
}

UPDATE_DATA_BY_MAC ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}adding missing macs into the database"${RESET} >> $LOG
for MAC in $MACS
	do
		HOSTNAME=
		HOSTNAME=$(cat $MAC_FILE | grep --color=never -A 1 "$MAC" | egrep --color=never -o '\".+\"' | sed 's/"//g' | sort --unique | tail -n 1)
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}MAC: $MAC"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Hostname: $HOSTNAME"${RESET} >> $LOG
		MYSQL_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$LOCAL_TABLE WHERE mac='$MAC';"`
		if [[ -z "$MYSQL_ID" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $MAC to the database"${RESET} >> $LOG
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $LOCAL_TABLE(mac,hostname,updated) VALUES('$MAC','$HOSTNAME','$NOW');
EOF
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating $MAC in the database"${RESET} >> $LOG
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $LOCAL_TABLE SET hostname='$HOSTNAME',updated='$NOW' WHERE id='$MYSQL_ID';
EOF
		fi
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
}

UPDATE_DATA_BY_IP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}updating or adding the data into the database"${RESET} >> $LOG
for IP in $IPS
	do
		MAC=
		HOSTNAME=
		MAC=$(cat $IP_FILE | grep --color=never -B 1 -A 1 "$IP" | egrep --color=never -o '[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}\:[0-9a-fA-F]{1,2}' | sort --unique | tail -n 1)
		HOSTNAME=$(cat $IP_FILE | grep --color=never -A 2 "$IP" | egrep --color=never -o '\".+\"' | sed 's/"//g' | sort --unique | tail -n 1)
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP: $IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}MAC: $MAC"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Hostname: $HOSTNAME"${RESET} >> $LOG
		MYSQL_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$LOCAL_TABLE WHERE mac='$MAC';"`
		if [[ -z "$MYSQL_ID" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $IP to the database"${RESET} >> $LOG
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $LOCAL_TABLE(ip,mac,hostname,updated) VALUES('$IP','$MAC','$HOSTNAME','$NOW');
EOF
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating $IP in the database"${RESET} >> $LOG
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $LOCAL_TABLE SET ip='$IP',hostname='$HOSTNAME',updated='$NOW' WHERE id='$MYSQL_ID';
EOF
		fi
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
}

UPDATE_DATA ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}updating or adding the data into the database"${RESET} >> $LOG
for LINE in `cat $FILE`
	do
		LINE_ARRAY=($(echo "$LINE" | sed 's/;;/ /g'))
		IP=$(echo "${LINE_ARRAY[2]}" | sed 's/"//g')
		MAC=$(echo "${LINE_ARRAY[0]}" | sed 's/"//g')
		HOSTNAME=$(echo "${LINE_ARRAY[1]}" | sed 's/"//g')
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP: $IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}MAC: $MAC"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Hostname: $HOSTNAME"${RESET} >> $LOG
		# read -p "Press enter to continue " DEBUG
		MYSQL_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$LOCAL_TABLE WHERE mac='$MAC' AND hostname='$HOSTNAME';"`
		if [[ -z "$MYSQL_ID" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding data to the database"${RESET} >> $LOG
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $LOCAL_TABLE(ip,mac,hostname,updated) VALUES('$IP','$MAC','$HOSTNAME','$NOW');
EOF
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating data in the database"${RESET} >> $LOG
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $LOCAL_TABLE SET ip='$IP',updated=NOW() WHERE id='$MYSQL_ID';
EOF
		fi
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ===" >> $LOG
}

CLEANUP ()
{
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $LOCAL_TABLE SET ip='' WHERE ip IS NULL;
UPDATE $LOCAL_TABLE SET network_id='' WHERE ip='' OR network_id='0';
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked"${RESET} >> $LOG

CHECK_TCPDUMP
COPY_FILE
# IPS=$(cat $IP_FILE | egrep -o "(^192\.168(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){2}$)|(^172\.(1[6-9]|2[0-9]|3[0-1])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){2}$)|(^10(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$)" | sort --unique)
# MACS=$(cat $MAC_FILE | egrep --color=never -o '[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}\:[A-Fa-f0-9]{2}' | sort --unique)
# if [[ -n "$MACS" ]]
# 	then
# 		UPDATE_DATA_BY_MAC
# 	else
# 		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}No MACs found"${RESET} >> $LOG
# fi
# if [[ -n "$IPS" ]]
# 	then
# 		UPDATE_DATA_BY_IP
# 	else
# 		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}No IPs found"${RESET} >> $LOG
# fi
UPDATE_DATA

CLEANUP

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
