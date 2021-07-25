#!/bin/bash
#Filename: netventory.remote_user.sh
#Description: 
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Winexe credentials file located at $HOME/scripts/.winexe_credentials
#Packages:
# winexe

# read -p "Press any key to continue. " DEBUG #DEBUG

SCRIPT_NAME="netventory.remote_user"
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
REMOTE_USER_TABLE="remote_user"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
USER_TABLE="user"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
OPENVPN_FILE="$WORKING_DIR/openvpn_file"
NETMOTION_FILE="$WORKING_DIR/netmotion_file.xml"
EXPECT_LOG=$OPENVPN_FILE
DOMAIN="wvcmsdom"
WINDOWS_VPN_SERVER="chwv-vpn.$DOMAIN"
OPENVPN_SERVER="chlv-vpn.$DOMAIN"
NETMOTION_SERVER="chwsnetmotion.$DOMAIN"
STATUS="Connected"

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

GET_WINDOWS_VPN_CONNECTIONS ()
{
SERVER_NAME=$WINDOWS_VPN_SERVER
CONNECTION_TYPE="Windows VPN"
SERVER_IP=
SERVER_IP=$(dig +short $SERVER_NAME)
WINDOWS_VPN_CONNECTIONS=$(winexe-static-2 --authentication-file=$WINEXE_CREDENTIALS //$SERVER_NAME "powershell.exe Get-RemoteAccessConnectionStatistics | FT -AutoSize" 2> /dev/null | grep --color=never "Vpn" | sed 's/\s\s*/;;/g' | sed 's/;;Vpn;;$//g')
if [[ -z "$WINDOWS_VPN_CONNECTIONS" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_USER_TABLE set status='unknown',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_USER_TABLE set status='disconnected',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
fi
for VPN_CONNECTION in $WINDOWS_VPN_CONNECTIONS
	do
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		SERVER_NAME=$WINDOWS_VPN_SERVER
		DOMAIN=
		USERNAME=
		IP=
		CONNECTION_TIME=
		DURATION=
		EXT_IP=
		USERNAME=$(echo "$VPN_CONNECTION" | egrep --color=never -o '\\[A-Za-z0-9\.\-]+' | sed 's/\\//g' | tr [:upper:] [:lower:])
		IP=$(echo "$VPN_CONNECTION" | egrep --color=never -o '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
		DURATION=$(echo "$VPN_CONNECTION" | egrep --color=never -o '[0-9]+$')
		CONVERT_SECONDS
		GET_ENDPOINT_ID
		GET_USER_ID
		CONNECTION_TIME=`date -d "$OLD_DURATION seconds ago" +%Y-%m-%d\ %H:%M:%S`
		GET_VPN_USER_ID
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Username: $USERNAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Endpoint ID: $ENDPOINT_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server Name: $SERVER_NAME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Server IP: $SERVER_IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Domain: $DOMAIN"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}User ID: $USER_ID"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}IP Address: $IP"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Time: $CONNECTION_TIME"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Duration: $DURATION"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Old Duration: $OLD_DURATION"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Status: $STATUS"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Connection Type: $CONNECTION_TYPE"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}VPN User ID: $VPN_USER_ID"${RESET} >> $LOG
		UPDATE_DATABASE
# read -p "Press any key to continue. " DEBUG #DEBUG
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
}

GET_OPENVPN_CONNECTIONS ()
{
SERVER_NAME=$OPENVPN_SERVER
CONNECTION_TYPE="OpenVPN"
SERVER_IP=
SERVER_IP=$(dig +short $SERVER_NAME)
OPENVPN_LOGIN
OPENVPN_CONNECTIONS=$(cat $EXPECT_LOG | tr [:upper:] [:lower:])
if [[ -z "$OPENVPN_CONNECTIONS" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_USER_TABLE set status='unknown',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_USER_TABLE set status='disconnected',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
fi
for VPN_CONNECTION in $OPENVPN_CONNECTIONS
	do
		SERVER_NAME=$OPENVPN_SERVER
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		USERNAME=
		IP=
		CONNECTION_TIME=
		DURATION=
		EXT_IP=
		USERNAME=$(echo "$VPN_CONNECTION" | egrep --color=never -o '^[a-z0-9\.\-]+;;[a-z0-9\.\-]+;;' | sed 's/^[a-z0-9\.\-]*;;//g' | sed 's/;;//g')
		IP=$(echo "$VPN_CONNECTION" | egrep --color=never -o '^[a-z0-9\.\-]+;;[a-z0-9\.\-]+;;[0-9a-z\._\:]+;;[0-9]+;;[a-z]+;;[0-9]+;;[0-9]+;;[0-9\.]+;;[0-9\.]+;;' | egrep --color=never -o ';;[0-9\.]+;;$' | sed 's/;;//g')
		CONNECTION_TIME=$(echo "$VPN_CONNECTION" | egrep --color=never -o '^[a-z0-9\.\-]+;;[a-z0-9\.\-]+;;[0-9a-z\._\:]+;;' | egrep --color=never -o ';;[0-9a-z\._\:]+;;$' | egrep --color=never -o '[0-9\.\:_]+' | sed 's/_$//g' | sed 's/\./-/g' | sed 's/_/ /g')
		DURATION=$(echo "$VPN_CONNECTION" | egrep --color=never -o '^[a-z0-9\.\-]+;;[a-z0-9\.\-]+;;[0-9a-z\._\:]+;;[0-9]+;;' | egrep --color=never -o ';;[0-9]+;;$' | sed 's/;;//g')
		CONVERT_SECONDS
		GET_ENDPOINT_ID
		GET_USER_ID
		GET_VPN_USER_ID
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
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}VPN User ID: $VPN_USER_ID"${RESET} >> $LOG
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
sed -i '/\$/d' $FILE
sed -i '/bash /d' $FILE
sed -i '/password /d' $FILE
sed -i '/login:/d' $FILE
sed -i '/Node,Username,/d' $FILE
sed -i 's/,\s$//g' $FILE
sed -i 's/,/;;/g' $FILE
sed -i 's/,/;;/g' $FILE
sed -i 's/\([0-9A-Za-z]\)\s\([0-9A-Za-z]\)/\1_\2/g' $FILE
}

GET_NETMOTION_CONNECTIONS ()
{
SERVER_NAME=$NETMOTION_SERVER
CONNECTION_TYPE="NetMotion"
SERVER_IP=
SERVER_IP=$(dig +short $SERVER_NAME)
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
sed -i 's/;;/,/g' $NETMOTION_FILE
NETMOTION_CONNECTIONS=$(cat "$NETMOTION_FILE")
if [[ -z "$NETMOTION_CONNECTIONS" ]]
	then
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_USER_TABLE set status='unknown',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
	else
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_USER_TABLE set status='disconnected',duration='00:00:00',updated=NOW() WHERE connection_type='$CONNECTION_TYPE';
EOF
fi
INPUT=$NETMOTION_FILE
OLDIFS=$IFS
IFS=,
[ ! -f $INPUT ] && { echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}$NETMOTION_FILE not found"${RESET} >> $LOG; }
while read EXT_IP SERVER_NAME CONNECTION_STATUS CONNECTION_TIME USERNAME IP
	do
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}External IP: $EXT_IP"${RESET} >> $LOG
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
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}VPN User ID: $VPN_USER_ID"${RESET} >> $LOG
		DURATION=
		SERVER_NAME=$(echo "$SERVER_NAME" | tr [:upper:] [:lower:])
		USERNAME=$(echo "$USERNAME" | tr [:upper:] [:lower:] | sed "s/$DOMAIN//g" | sed 's/\\//g')
		CONNECTION_TIME=$(echo "$CONNECTION_TIME" | sed 's/T/ /g' | sed 's/Z$//g')
		CONNECTION_TIME=$(TZ=MST date -d "$CONNECTION_TIME UTC" +%Y-%m-%d\ %H:%M:%S)
 		let DURATION=(`date +%s`-`date +%s -d "$CONNECTION_TIME"`)
		CONVERT_SECONDS
		GET_ENDPOINT_ID
		GET_USER_ID
		GET_VPN_USER_ID
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}External IP: $EXT_IP"${RESET} >> $LOG
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
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}VPN User ID: $VPN_USER_ID"${RESET} >> $LOG
		# UPDATE_DATABASE
# read -p "Press any key to continue. " DEBUG #DEBUG
done < $INPUT
IFS=$OLDIFS
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
}

ADD_VPN_USER_RECORD ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding a record for $USERNAME"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
INSERT INTO $REMOTE_USER_TABLE(endpoint_id,server_name,domain,user_id,ip,updated,added) VALUES('$ENDPOINT_ID','$SERVER_NAME','$DOMAIN','$USER_ID','$IP',NOW(),NOW());
EOF
}

CONVERT_SECONDS ()
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

GET_VPN_USER_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the vpn user ID for $IP"${RESET} >> $LOG
VPN_USER_ID=
VPN_USER_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$REMOTE_USER_TABLE WHERE endpoint_id='$ENDPOINT_ID' AND server_name='$SERVER_NAME' AND domain='$DOMAIN' AND user_id='$USER_ID' AND ip='$IP';"`
if [[ -z "$VPN_USER_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP does not exist in the database yet. Adding it"${RESET} >> $LOG
		ADD_VPN_USER_RECORD
		VPN_USER_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$REMOTE_USER_TABLE WHERE endpoint_id='$ENDPOINT_ID' AND server_name='$SERVER_NAME' AND domain='$DOMAIN' AND user_id='$USER_ID' AND ip='$IP';"`
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}VPN User ID: $VPN_USER_ID"${RESET} >> $LOG
}

ADD_VPN_USER_RECORD ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding a record for $USERNAME"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
INSERT INTO $REMOTE_USER_TABLE(endpoint_id,server_name,domain,user_id,ip,updated,added) VALUES('$ENDPOINT_ID','$SERVER_NAME','$DOMAIN','$USER_ID','$IP',NOW(),NOW());
EOF
}

UPDATE_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $REMOTE_USER_TABLE table"${RESET} >> $LOG
SERVER_NAME=$(echo "$SERVER_NAME" | sed "s/\.$DOMAIN\$//g")
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}UPDATE $REMOTE_USER_TABLE SET endpoint_id='$ENDPOINT_ID',server_name='$SERVER_NAME',server_ip='$SERVER_IP',domain='$DOMAIN',user_id='$USER_ID',ip='$IP',duration='$DURATION',status='$STATUS',connection_type='$CONNECTION_TYPE',connection_time='$CONNECTION_TIME',connection_check=NOW(),updated=NOW() WHERE id='$VPN_USER_ID';"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $REMOTE_USER_TABLE SET endpoint_id='$ENDPOINT_ID',server_name='$SERVER_NAME',server_ip='$SERVER_IP',domain='$DOMAIN',user_id='$USER_ID',ip='$IP',duration='$DURATION',status='$STATUS',connection_type='$CONNECTION_TYPE',connection_time='$CONNECTION_TIME',ext_ip='$EXT_IP',connection_check=NOW(),updated=NOW() WHERE id='$VPN_USER_ID';
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

# GET_WINDOWS_VPN_CONNECTIONS
GET_OPENVPN_CONNECTIONS
# GET_NETMOTION_CONNECTIONS

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the script"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
