#!/bin/bash
#Filename: netventory.remote_connections.sh
#Description: 
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Winexe credentials file located at $HOME/scripts/.winexe_credentials
#Packages:
# winexe

# read -p "Press any key to continue. " DEBUG #DEBUG

SCRIPT_NAME="netventory.remote_connections"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
WINEXE_CREDENTIALS="$HOME/scripts/.winexe_credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
OPENVPN_USERNAME=$(cat $CREDENTIALS | grep openvpn_username: | sed 's/openvpn_username://g')
OPENVPN_PASSWORD=$(cat $CREDENTIALS | grep openvpn_password: | sed 's/openvpn_password://g')
NETMOTION_USERNAME=$(cat $CREDENTIALS | grep network_username: | sed 's/network_username://g')
NETMOTION_PASSWORD=$(cat $CREDENTIALS | grep network_password: | sed 's/network_password://g')
NETVENTORY_DATABASE="netventory"
REMOTE_CONNECTION_TABLE="remote_connections"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
USER_TABLE="user"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
WINDOWS_VPN_FILE="$WORKING_DIR/windows_vpn_file"
WINDOWS_RD_FILE="$WORKING_DIR/windows_rd_file"
OPENVPN_FILE="$WORKING_DIR/openvpn_file"
NETMOTION_FILE="$WORKING_DIR/netmotion_file.xml"
NETMOTION_USERNAME_FILE="$WORKING_DIR/netmotion_users"
DOMAIN="wvcmsdom"
WINDOWS_VPN_SERVER="chwv-vpn.$DOMAIN"
WINDOWS_RD_SERVER="chwv-rdgw2019.$DOMAIN"
OPENVPN_SERVER="chlv-vpn.$DOMAIN"
NETMOTION_SERVER="chwsnetmotion.$DOMAIN"
STATUS="Connected"
DELETE_DAYS="90"

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

CLEANUP_OLD_DATA ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Cleaning up all connections older than $DELETE_DAYS"${RESET} >> $LOG
SERVER_NAME=$(echo "$SERVER_NAME" | sed "s/\.$DOMAIN\$//g")
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
DELETE FROM $REMOTE_CONNECTION_TABLE WHERE connection_check < (NOW() - INTERVAL $DELETE_DAYS DAY);
EOF
}

GET_WINDOWS_RD_CONNECTIONS ()
{

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the Windows RD Connections"${RESET} >> $LOG
SERVER_NAME=$WINDOWS_RD_SERVER
CONNECTION_TYPE="Windows RD Gateway"
SERVER_IP=
SERVER_IP=$(dig +short $SERVER_NAME | sed ':a;N;$!ba;s/\n/,/g')
winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$SERVER_NAME 'powershell Get-WmiObject -class "Win32_TSGatewayConnection" -namespace "root\cimv2\TerminalServices" -Authentication 6 | select ClientAddress,ConnectedResource,ConnectedTime,ConnectionDuration,UserName,PsComputerName | Format-Table -Wrap -AutoSize | Out-String -Width 4096' 2> /dev/null | tr [:upper:] [:lower:] | sed '/^[[:space:]]*$/d' | sed '/clientaddress/d' | sed '/---/d' | sed 's/\s\s*/;;/g' | sed 's/;;$//g' | sed 's/;;/ /g' > $WINDOWS_RD_FILE
WINDOWS_RD_USERNAMES=$(cat $WINDOWS_RD_FILE | egrep --color=never -o '\\[A-Za-z0-9\.\_-]+ ' | sed 's/\\//g' | sed 's/ //g' | sort --unique)
if [[ -z "$WINDOWS_RD_USERNAMES" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='unknown',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='disconnected',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
fi
for USERNAME in $WINDOWS_RD_USERNAMES
	do
		CONNECTION_ARRAY=($(cat $WINDOWS_RD_FILE | grep -i --color=never "$USERNAME" | tail -n 1))
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		SERVER_NAME=${CONNECTION_ARRAY[5]}
		REMOTE_IP=${CONNECTION_ARRAY[0]}
		DURATION=${CONNECTION_ARRAY[3]}
		DURATION=$(echo "$DURATION" | sed 's/\..*//g' | sed 's/^0*//g' | sed 's/\([0-9]\{1,2\}\)$/\:\1/g' | sed 's/\([0-9]\{1\}\)\([0-9]\{2\}:\)/\1\:\2/g')
		CONNECTION_TIME=${CONNECTION_ARRAY[2]}
		CONNECTION_TIME=$(echo "$CONNECTION_TIME" | sed 's/\..*//g' | sed 's/\([0-9]\{8\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1 \2\:\3\:\4/g')
		DATE_TO_BE_CONVERTED=$CONNECTION_TIME
		CONVERT_DATE_FORMAT
		CONNECTION_TIME=$CONVERTED_DATE
		IP=${CONNECTION_ARRAY[1]}
		IP=$(nslookup $IP | grep --color=never "Address" | tail -n 1 | sed 's/Address: //g')
		GET_ENDPOINT_ID
		GET_USER_ID
		GET_REMOTE_CONNECTION_ID
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote IP: $REMOTE_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Username: $USERNAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server Name: $SERVER_NAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server IP: $SERVER_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain: $DOMAIN"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User ID: $USER_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP Address: $IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Time: $CONNECTION_TIME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Duration: $DURATION"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Status: $STATUS"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Type: $CONNECTION_TYPE"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote Connection ID: $REMOTE_CONNECTION_ID"${RESET} >> $LOG
		UPDATE_DATABASE
# read -p "Press any key to continue. " DEBUG #DEBUG
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
}

GET_WINDOWS_VPN_CONNECTIONS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the Windows VPN Connections"${RESET} >> $LOG
SERVER_NAME=$WINDOWS_VPN_SERVER
CONNECTION_TYPE="Windows VPN"
SERVER_IP=
SERVER_IP=$(dig +short $SERVER_NAME | sed ':a;N;$!ba;s/\n/,/g')
winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$SERVER_NAME "powershell.exe Get-RemoteAccessConnectionStatistics | Select-Object -property ClientIPAddress,UserName,ConnectionDuration,ClientExternalAddress,ConnectionStartTime | Format-Table -Wrap -AutoSize | Out-String -Width 4096" 2> /dev/null | tr [:upper:] [:lower:] | sed '/^[[:space:]]*$/d' | sed '/clientipaddress/d' | sed '/---/d' | sed 's/{//g' | sed 's/}//g' | sed 's/\([0-9]\{1,2\}\/[0-9]\{1,2\}\/[0-9]\{4\}\) \([0-9]\{1,2\}\:[0-9]\{1,2\}\:[0-9]\{1,2\}\) \([ap]m\)/\1_\2_\3/g' | sed 's/\s\s*/;;/g' | sed 's/;;$//g' | sed 's/;;/ /g' > $WINDOWS_VPN_FILE
WINDOWS_VPN_USERNAMES=$(cat $WINDOWS_VPN_FILE | egrep --color=never -o '\\[A-Za-z0-9\.\_-]+ ' | sed 's/\\//g' | sed 's/ //g' | sort --unique)
if [[ -z "$WINDOWS_VPN_USERNAMES" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='unknown',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='disconnected',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Windows VPN Usernames: $WINDOWS_VPN_USERNAMES"${RESET} >> $LOG
for USERNAME in $WINDOWS_VPN_USERNAMES
	do
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Working with $USERNAME"${RESET} >> $LOG
		CONNECTION_ARRAY=($(cat $WINDOWS_VPN_FILE | grep -i --color=never "$USERNAME" | tail -n 1))
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Line: ${CONNECTION_ARRAY[@]}"${RESET} >> $LOG
		SERVER_NAME=$WINDOWS_VPN_SERVER
		REMOTE_IP=${CONNECTION_ARRAY[3]}
		IP=${CONNECTION_ARRAY[0]}
		DURATION=${CONNECTION_ARRAY[2]}
		CONVERT_SECONDS_TO_HOURS
		CONNECTION_TIME=${CONNECTION_ARRAY[4]}
		CONNECTION_TIME=$(echo "$CONNECTION_TIME" | sed 's/_/ /g')
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Time: $CONNECTION_TIME"${RESET} >> $LOG
		DATE_TO_BE_CONVERTED=$CONNECTION_TIME
		CONVERT_DATE_FORMAT
		CONNECTION_TIME=$CONVERTED_DATE
		GET_ENDPOINT_ID
		GET_USER_ID
		GET_REMOTE_CONNECTION_ID
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote IP: $REMOTE_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Username: $USERNAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server Name: $SERVER_NAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server IP: $SERVER_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain: $DOMAIN"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User ID: $USER_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP Address: $IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Time: $CONNECTION_TIME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Duration: $DURATION"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Status: $STATUS"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Type: $CONNECTION_TYPE"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote Connection ID: $REMOTE_CONNECTION_ID"${RESET} >> $LOG
		UPDATE_DATABASE
# read -p "Press any key to continue. " DEBUG #DEBUG
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
}

GET_OPENVPN_CONNECTIONS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the OpenVPN Connections"${RESET} >> $LOG
EXPECT_LOG=$OPENVPN_FILE
SERVER_NAME=$OPENVPN_SERVER
CONNECTION_TYPE="OpenVPN"
SERVER_IP=
SERVER_IP=$(dig +short $SERVER_NAME | sed ':a;N;$!ba;s/\n/,/g')
OPENVPN_LOGIN
sort --unique --output=$EXPECT_LOG $EXPECT_LOG
# OPENVPN_CONNECTIONS=$(cat $EXPECT_LOG | tr [:upper:] [:lower:])
OPENVPN_USERNAMES=$(cat $EXPECT_LOG | egrep --color=never -o '^[A-Za-z0-9\.\_-]+;;[A-Za-z0-9\.\_-]+;;' | sed 's/;;$//g' | sed 's/^.*;;//g' | sed 's/;;//g' | tr [:upper:] [:lower:] | sort --unique)
if [[ -z "$OPENVPN_USERNAMES" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='unknown',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='disconnected',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
fi
for USERNAME in $OPENVPN_USERNAMES
	do
		CONNECTION_ARRAY=($(cat $EXPECT_LOG | grep -i --color=never "$USERNAME" | tail -n 1 | sed 's/;;/ /g'))
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		REMOTE_IP=${CONNECTION_ARRAY[7]}
		IP=${CONNECTION_ARRAY[8]}
		CONNECTION_TIME=${CONNECTION_ARRAY[2]}
		CONNECTION_TIME=$(echo "$CONNECTION_TIME" | sed 's/_MST//g' | sed 's/_/ /g')
		DURATION=${CONNECTION_ARRAY[3]}
		SERVER_NAME=${CONNECTION_ARRAY[0]}
		SERVER_NAME=$(echo "$SERVER_NAME" | tr [:upper:] [:lower:])
		CONVERT_SECONDS_TO_HOURS
		GET_ENDPOINT_ID
		GET_USER_ID
		GET_REMOTE_CONNECTION_ID
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote IP: $REMOTE_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Username: $USERNAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server Name: $SERVER_NAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server IP: $SERVER_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain: $DOMAIN"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User ID: $USER_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP Address: $IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Time: $CONNECTION_TIME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Duration: $DURATION"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Status: $STATUS"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Type: $CONNECTION_TYPE"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote Connection ID: $REMOTE_CONNECTION_ID"${RESET} >> $LOG
		UPDATE_DATABASE
# read -p "Press any key to continue. " DEBUG #DEBUG
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
}

OPENVPN_LOGIN ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Logging into $SERVER_NAME"${RESET} >> $LOG
rm -rf $EXPECT_LOG &> /dev/null
/usr/bin/expect << EOF
set timeout 5
log_user 0
log_file -a $EXPECT_LOG
spawn -noecho ssh $OPENVPN_USERNAME@$SERVER_NAME
# expect "s password:"
# send "$OPENVPN_PASSWORD\r"
expect "$"
send "sudo /bin/bash /usr/local/openvpn_as/scripts/logdba --csv --active=1\r"
expect "password for"
send "$OPENVPN_PASSWORD\r"
expect "$"
send "logout\r"
EOF
echo >> $EXPECT_LOG
sed -i '/\$/d' $EXPECT_LOG
sed -i '/bash /d' $EXPECT_LOG
sed -i '/password /d' $EXPECT_LOG
sed -i '/login:/d' $EXPECT_LOG
sed -i '/Node,Username,/d' $EXPECT_LOG
sed -i 's/,\s$//g' $EXPECT_LOG
sed -i 's/,/;;/g' $EXPECT_LOG
sed -i 's/,/;;/g' $EXPECT_LOG
sed -i 's/\([0-9A-Za-z]\)\s\([0-9A-Za-z]\)/\1_\2/g' $EXPECT_LOG
}

GET_NETMOTION_CONNECTIONS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the NetMotion Connections"${RESET} >> $LOG
SERVER_NAME=$NETMOTION_SERVER
CONNECTION_TYPE="NetMotion"
SERVER_IP=
SERVER_IP=$(dig +short $SERVER_NAME | sed ':a;N;$!ba;s/\n/,/g')
wget --output-file $HOME/logs/wget.log --user=$DOMAIN\\$NETMOTION_USERNAME --password=$NETMOTION_PASSWORD "http://$NETMOTION_SERVER:8080/WebService/ConnectionStatus?" --output-document=$NETMOTION_FILE 2 > /dev/null
echo >> $NETMOTION_FILE
sed -i 's/<connectionState>/\n<connectionState>/g' $NETMOTION_FILE
sed -i '/connectionStatusResponse/d' $NETMOTION_FILE
sed -i 's/<\/connectionState>$//g' $NETMOTION_FILE
sed -i '/Disconnected/d' $NETMOTION_FILE
sed -i '/Unreachable/d' $NETMOTION_FILE
sed -i 's/<\/deviceName>/;;/g' $NETMOTION_FILE
sed -i 's/<\/devicePid>/;;/g' $NETMOTION_FILE
sed -i 's/<\/firstTimestamp>/;;/g' $NETMOTION_FILE
sed -i 's/<\/lastUser>/;;/g' $NETMOTION_FILE
sed -i 's/<\/lastUserTimestamp>/;;/g' $NETMOTION_FILE
sed -i 's/<\/pop>/;;/g' $NETMOTION_FILE
sed -i 's/<\/serverMachineName>/;;/g' $NETMOTION_FILE
sed -i 's/<\/state>/;;/g' $NETMOTION_FILE
sed -i 's/<\/timestamp>/;;/g' $NETMOTION_FILE
sed -i 's/<\/user>/;;/g' $NETMOTION_FILE
sed -i 's/<\/userName>/;;/g' $NETMOTION_FILE
sed -i 's/<\/vip>/;;/g' $NETMOTION_FILE
sed -i 's/<deviceName>//g' $NETMOTION_FILE
sed -i 's/<devicePid>//g' $NETMOTION_FILE
sed -i 's/<firstTimestamp>//g' $NETMOTION_FILE
sed -i 's/<lastUser>//g' $NETMOTION_FILE
sed -i 's/<lastUserTimestamp>//g' $NETMOTION_FILE
sed -i 's/<pop>//g' $NETMOTION_FILE
sed -i 's/<serverMachineName>//g' $NETMOTION_FILE
sed -i 's/<state>//g' $NETMOTION_FILE
sed -i 's/<timestamp>//g' $NETMOTION_FILE
sed -i 's/<user>//g' $NETMOTION_FILE
sed -i 's/<userName>//g' $NETMOTION_FILE
sed -i 's/<vip>//g' $NETMOTION_FILE
sed -i 's/^<connectionState>//g' $NETMOTION_FILE
sed -i 's/<\/connectionState>.*$//g' $NETMOTION_FILE
sed -i 's/;;$//g' $NETMOTION_FILE
sort --unique --output=$NETMOTION_FILE $NETMOTION_FILE
# NETMOTION_CONNECTIONS=$(cat "$NETMOTION_FILE")
NETMOTION_USERNAMES=$(cat $NETMOTION_FILE | egrep --color=never -o ';;[A-Za-z0-9\.\_-]+\\[A-Za-z0-9\.\_-]+;;' | sed 's/^;;.*\\//g' | sed 's/;;//g' | tr [:upper:] [:lower:] | sort --unique)
if [[ -z "$NETMOTION_USERNAMES" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='unknown',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='disconnected',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
fi
for USERNAME in $NETMOTION_USERNAMES
	do
		CONNECTION_ARRAY=($(cat $NETMOTION_FILE | grep -i --color=never "$USERNAME" | tail -n 1 | sed 's/;;/ /g'))
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		REMOTE_IP=${CONNECTION_ARRAY[0]}
		SERVER_NAME=${CONNECTION_ARRAY[1]}
		SERVER_NAME=$(echo "$SERVER_NAME" | tr [:upper:] [:lower:])
		IP=${CONNECTION_ARRAY[5]}
		CONNECTION_TIME=${CONNECTION_ARRAY[3]}
		CONNECTION_TIME=$(echo "$CONNECTION_TIME" | sed 's/T/ /g' | sed 's/Z//g')
		CONNECTION_TIME=$(TZ=MST date -d "$CONNECTION_TIME UTC" +%Y-%m-%d\ %H:%M:%S)
 		let DURATION=(`date +%s`-`date +%s -d "$CONNECTION_TIME"`)
		CONVERT_SECONDS_TO_HOURS
		GET_ENDPOINT_ID
		GET_USER_ID
		GET_REMOTE_CONNECTION_ID
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote IP: $REMOTE_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Username: $USERNAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server Name: $SERVER_NAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server IP: $SERVER_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain: $DOMAIN"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User ID: $USER_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP Address: $IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Time: $CONNECTION_TIME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Duration: $DURATION"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Status: $STATUS"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Type: $CONNECTION_TYPE"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote Connection ID: $REMOTE_CONNECTION_ID"${RESET} >> $LOG
		UPDATE_DATABASE
# read -p "Press any key to continue. " DEBUG #DEBUG
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
}

GET_GUACAMOLE_CONNECTIONS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the OpenVPN Connections"${RESET} >> $LOG
EXPECT_LOG=$OPENVPN_FILE
SERVER_NAME=$OPENVPN_SERVER
CONNECTION_TYPE="OpenVPN"
SERVER_IP=
SERVER_IP=$(dig +short $SERVER_NAME | sed ':a;N;$!ba;s/\n/,/g')
OPENVPN_LOGIN
sort --unique --output=$EXPECT_LOG $EXPECT_LOG
# OPENVPN_CONNECTIONS=$(cat $EXPECT_LOG | tr [:upper:] [:lower:])
OPENVPN_USERNAMES=$(cat $EXPECT_LOG | egrep --color=never -o '^[A-Za-z0-9\.\_-]+;;[A-Za-z0-9\.\_-]+;;' | sed 's/;;$//g' | sed 's/^.*;;//g' | sed 's/;;//g' | tr [:upper:] [:lower:] | sort --unique)
if [[ -z "$OPENVPN_USERNAMES" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='unknown',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE set status='disconnected',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
fi
for USERNAME in $OPENVPN_USERNAMES
	do
		CONNECTION_ARRAY=($(cat $EXPECT_LOG | grep -i --color=never "$USERNAME" | tail -n 1 | sed 's/;;/ /g'))
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		REMOTE_IP=${CONNECTION_ARRAY[7]}
		IP=${CONNECTION_ARRAY[8]}
		CONNECTION_TIME=${CONNECTION_ARRAY[2]}
		CONNECTION_TIME=$(echo "$CONNECTION_TIME" | sed 's/_MST//g' | sed 's/_/ /g')
		DURATION=${CONNECTION_ARRAY[3]}
		SERVER_NAME=${CONNECTION_ARRAY[0]}
		SERVER_NAME=$(echo "$SERVER_NAME" | tr [:upper:] [:lower:])
		CONVERT_SECONDS_TO_HOURS
		GET_ENDPOINT_ID
		GET_USER_ID
		GET_REMOTE_CONNECTION_ID
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote IP: $REMOTE_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Username: $USERNAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server Name: $SERVER_NAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server IP: $SERVER_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain: $DOMAIN"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User ID: $USER_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP Address: $IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Time: $CONNECTION_TIME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Duration: $DURATION"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Status: $STATUS"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Type: $CONNECTION_TYPE"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote Connection ID: $REMOTE_CONNECTION_ID"${RESET} >> $LOG
		UPDATE_DATABASE
# read -p "Press any key to continue. " DEBUG #DEBUG
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
}

GUACAMOLE_LOGIN ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Logging into $SERVER_NAME"${RESET} >> $LOG
rm -rf $EXPECT_LOG &> /dev/null
/usr/bin/expect << EOF
set timeout 5
log_user 0
log_file -a $EXPECT_LOG
spawn -noecho ssh $OPENVPN_USERNAME@$SERVER_NAME
# expect "s password:"
# send "$OPENVPN_PASSWORD\r"
expect "$"
send "sudo /bin/bash /usr/local/openvpn_as/scripts/logdba --csv --active=1\r"
expect "password for"
send "$OPENVPN_PASSWORD\r"
expect "$"
send "logout\r"
EOF
echo >> $EXPECT_LOG
sed -i '/\$/d' $EXPECT_LOG
sed -i '/bash /d' $EXPECT_LOG
sed -i '/password /d' $EXPECT_LOG
sed -i '/login:/d' $EXPECT_LOG
sed -i '/Node,Username,/d' $EXPECT_LOG
sed -i 's/,\s$//g' $EXPECT_LOG
sed -i 's/,/;;/g' $EXPECT_LOG
sed -i 's/,/;;/g' $EXPECT_LOG
sed -i 's/\([0-9A-Za-z]\)\s\([0-9A-Za-z]\)/\1_\2/g' $EXPECT_LOG
}

CONVERT_SECONDS_TO_HOURS ()
{
OLD_DURATION=$DURATION
NUM=$DURATION
MIN=0
HOUR=0
if((NUM>59))
	then
    	((SEC=NUM%60))
    	((NUM=NUM/60))
    	if((NUM>59))
    		then
		        ((MIN=NUM%60))
		        ((NUM=NUM/60))
       			((HOUR=NUM))
    		else
        		((MIN=NUM))
    	fi
	else
    	((SEC=NUM))
fi
HOUR_SHORT=$(echo "$HOUR" | egrep --color=never '[0-9]{2}')
if [[ -z "$HOUR_SHORT" ]]
	then
		HOUR=0${HOUR}
fi
MIN_SHORT=$(echo "$MIN" | egrep --color=never '[0-9]{2}')
if [[ -z "$MIN_SHORT" ]]
	then
		MIN=0${MIN}
fi
SEC_SHORT=$(echo "$SEC" | egrep --color=never '[0-9]{2}')
if [[ -z "$SEC_SHORT" ]]
	then
		SEC=0${SEC}
fi
DURATION="$HOUR:$MIN:$SEC"
}

CONVERT_DATE_FORMAT ()
{
CONVERTED_DATE=$(date -d "$DATE_TO_BE_CONVERTED" +%Y-%m-%d\ %H:%M:%S)
}

GET_ENDPOINT_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the endpoint ID for $IP"${RESET} >> $LOG
ENDPOINT_ID=
ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
if [[ -z "$ENDPOINT_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP does not exist in the database yet. Adding it"${RESET} >> $LOG
		ADD_ENDPOINT
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the new endpoint ID"${RESET} >> $LOG
		ENDPOINT_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$ENDPOINT_TABLE WHERE ip='$IP';"`
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
}

ADD_ENDPOINT ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the endpoint to the $ENDPOINT_TABLE table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
INSERT INTO $ENDPOINT_TABLE(ip,ping_check,updated,added) VALUES('$IP',CURDATE(),NOW(),NOW());
EOF
}

GET_USER_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the User ID for $USERNAME"${RESET} >> $LOG
USER_ID=
USER_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username='$USERNAME';"`
if [[ -z "$USER_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$USERNAME does not exist in the database yet. Adding it"${RESET} >> $LOG
		ADD_USERNAME_TO_DATABASE
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the new User ID"${RESET} >> $LOG
		USER_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username='$USERNAME';"`
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User ID: $USER_ID"${RESET} >> $LOG
}

ADD_USERNAME_TO_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $USERNAME to the $USER_TABLE table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
INSERT IGNORE INTO $USER_TABLE(username,updated,added) values('$USERNAME',NOW(),NOW()) ON DUPLICATE KEY UPDATE UPDATED=NOW();
EOF
}

GET_REMOTE_CONNECTION_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the Remote Connection ID for $IP"${RESET} >> $LOG
OLD_SERVER_NAME=$SERVER_NAME
SERVER_NAME=$(echo "$SERVER_NAME" | sed "s/\.$DOMAIN\$//g")
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}SELECT id FROM $NETVENTORY_DATABASE.$REMOTE_CONNECTION_TABLE WHERE endpoint_id='$ENDPOINT_ID' AND server_name='$SERVER_NAME' AND domain='$DOMAIN' AND user_id='$USER_ID' AND ip='$IP' ORDER BY connection_time DESC LIMIT 1"${RESET} >> $LOG
REMOTE_CONNECTION_ID=
REMOTE_CONNECTION_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$REMOTE_CONNECTION_TABLE WHERE endpoint_id='$ENDPOINT_ID' AND server_name='$SERVER_NAME' AND domain='$DOMAIN' AND user_id='$USER_ID' AND ip='$IP' ORDER BY connection_time DESC LIMIT 1;"`
if [[ -z "$REMOTE_CONNECTION_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP does not exist in the database yet. Adding it"${RESET} >> $LOG
		ADD_REMOTE_CONNECTION_RECORD
		REMOTE_CONNECTION_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$REMOTE_CONNECTION_TABLE WHERE endpoint_id='$ENDPOINT_ID' AND server_name='$SERVER_NAME' AND domain='$DOMAIN' AND user_id='$USER_ID' AND ip='$IP' ORDER BY connection_time DESC LIMIT 1;"`
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Remote Connection ID: $REMOTE_CONNECTION_ID"${RESET} >> $LOG
SERVER_NAME=$OLD_SERVER_NAME
}

ADD_REMOTE_CONNECTION_RECORD ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding a record for $USERNAME"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
INSERT INTO $REMOTE_CONNECTION_TABLE(endpoint_id,server_name,domain,user_id,ip,updated,added) VALUES('$ENDPOINT_ID','$SERVER_NAME','$DOMAIN','$USER_ID','$IP',NOW(),NOW());
EOF
}

UPDATE_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $REMOTE_CONNECTION_TABLE table"${RESET} >> $LOG
SERVER_NAME=$(echo "$SERVER_NAME" | sed "s/\.$DOMAIN\$//g")
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}UPDATE $REMOTE_CONNECTION_TABLE SET endpoint_id='$ENDPOINT_ID',server_name='$SERVER_NAME',server_ip='$SERVER_IP',domain='$DOMAIN',user_id='$USER_ID',ip='$IP',duration='$DURATION',status='$STATUS',connection_type='$CONNECTION_TYPE',connection_time='$CONNECTION_TIME',connection_check=NOW(),updated=NOW() WHERE id='$REMOTE_CONNECTION_ID';"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_CONNECTION_TABLE SET endpoint_id='$ENDPOINT_ID',server_name='$SERVER_NAME',server_ip='$SERVER_IP',domain='$DOMAIN',user_id='$USER_ID',ip='$IP',duration='$DURATION',status='$STATUS',connection_type='$CONNECTION_TYPE',connection_time='$CONNECTION_TIME',remote_ip='$REMOTE_IP',connection_check=NOW(),updated=NOW() WHERE id='$REMOTE_CONNECTION_ID';
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

CLEANUP_OLD_DATA
GET_WINDOWS_RD_CONNECTIONS
GET_WINDOWS_VPN_CONNECTIONS
GET_OPENVPN_CONNECTIONS
GET_NETMOTION_CONNECTIONS
# GET_GUACAMOLE_CONNECTIONS

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the script"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
