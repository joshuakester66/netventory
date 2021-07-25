#!/bin/bash
#Filename: port_authentication.sh
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

SCRIPT_NAME="port_authentication"
SCRIPT_CAT="netventory"

IPS=$1

mkdir -p $HOME/scripts/logs &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/scripts/logs/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
NETWORK_USERNAME=$(cat $CREDENTIALS | grep network_username: | sed 's/network_username://g')
NETWORK_PASSWORD=$(cat $CREDENTIALS | grep network_password: | sed 's/network_password://g')
LDAP_QUERY_USERNAME=$(cat $CREDENTIALS | grep ldap_username: | sed 's/ldap_username://g')
LDAP_QUERY_PASSWORD=$(cat $CREDENTIALS | grep ldap_password: | sed 's/ldap_password://g')
SNMP_TABLE="snmp"
SNMP_TIMEOUT="0.2"
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
PORT_AUTH_TABLE="port_auth"
INTERFACE_TABLE="interface"
OID_TABLE="oid"
LDAP_URI_1='ldap://chwsdc1.wvcmsdom:389'
LDAP_URI_2='ldap://chwsdc2.wvcmsdom:389'
#LDAP_URI_3='ldap://chwsdc3.wvcmsdom:389'
LDAP_URI_3='ldap://mcwv-dc1.wvcmsdom:389'
LDAP_DOMAIN="wvcmsdom"
LDAP_NAME_ATT="displayName"
LDAP_USERNAME_ATT="sAMAccountName"
LDAP_USER_DN="OU=Domain Users,DC=wvcmsdom"
LDAP_SEARCH_CRITERIA=$LDAP_USERNAME_ATT
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
PORT_AUTH_FILE="$WORKING_DIR/port_auth"
FILE=$PORT_AUTH_FILE
TEMP_FILE="$WORKING_DIR/port_auth_temp"

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
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE snmp_enabled='1' AND ping_check > (NOW() - INTERVAL 30 DAY);"`
}

GET_DEVICE_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the device ID for $IP"${RESET} >> $LOG
DEVICE_ID=
DEVICE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
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
INSERT INTO $DEVICE_TABLE(ip,updated,added) VALUES('$IP',NOW(),NOW());
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

GET_FILE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Logging into $IP"${RESET} >> $LOG
/usr/bin/expect << EOF
set timeout 5
log_user 0
log_file -a $FILE
spawn -noecho ssh $NETWORK_USERNAME@$IP
expect {
	"Are you sure you want to continue" {
		send "yes\n"
	}
	"s password:" {
		send "$NETWORK_PASSWORD\n"
	}
	"Press any key to continue" {
		send "ne\n"
	}
	"#" {
		send "ne\n"
	}
}
expect {
	"s password:" {
		send "$NETWORK_PASSWORD\n"
	}
	"Press any key to continue" {
		send "ne\n"
	}
	"#" {
		send "ne\n"
	}
}
expect {
	"Press any key to continue" {
		send "ne\n"
	}
	"#" {
		send "ne\n"
	}
}
expect "#"
send "terminal length 1000\n"
expect "#"
send "show port-access authenticator clients all detailed\n"
expect "#"
send "logout\n"
EOF
echo >> $FILE
# tr -cd "[:print:]\n" < $FILE
}

CLEANUP_FILE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Cleaning up the file $FILE"${RESET} >> $LOG
sed -i -n '/Client Status Detailed/,$p' $FILE
sed -i '1d' $FILE
sed -i '1d' $FILE
sed -i '1d' $FILE
sed -i '1d' $FILE
sed -i '1d' $FILE
sed -i '1d' $FILE
sed -i 's/\([0-9a-fA-F]\{2\}\)\([0-9a-fA-F]\{2\}\)\([0-9a-fA-F]\{2\}\)\-\([0-9a-fA-F]\{2\}\)\([0-9a-fA-F]\{2\}\)\([0-9a-fA-F]\{2\}\)/\1:\2:\3:\4:\5:\6/g' $FILE
sed -i 's/ seconds//g' $FILE
sed -i '/Client Base Details/d' $FILE
sed -i '/Access Policy Details/d' $FILE
sed -i 's/^\s*COS Map\s*:\s/;;/g' $FILE
sed -i 's/\s*In Limit Kbps\s*:\s/;;/g' $FILE
sed -i 's/^\s*Untagged VLAN\s*:\s/;;/g' $FILE
sed -i 's/\s*Out Limit Kbps\s*:\s/;;/g' $FILE
sed -i 's/^\s*Tagged VLANs\s*:\s/;;/g' $FILE
sed -i 's/^\s*Port Mode\s*:\s/;;/g' $FILE
sed -i 's/^\s*RADIUS ACL List\s*:\s/;;/g' $FILE
sed -i 's/^\s*Port\s*:\s//g' $FILE
sed -i 's/^\s*Client Status\s*:\s/;;/g' $FILE
sed -i 's/\s*Session Time\s*:\s/;;/g' $FILE
sed -i 's/^\s*Client name\s*:\s/;;/g' $FILE
sed -i 's/\s*Session Timeout\s*:\s/;;/g' $FILE
sed -i 's/^\s*IP\s*:\s/;;/g' $FILE
sed -i 's/\s*MAC Address\s*:\s/;;/g' $FILE
sed -i '/^\s*$/d' $FILE
sed -i 's/\s*$//g' $FILE
sed -i '$d' $FILE
sed -i '$d' $FILE
sed -i '$d' $FILE
cat $FILE > $TEMP_FILE
tr '\n' ';' < $TEMP_FILE > $FILE
sed -i 's/\([0-9A-Za-z]\);\([0-9A-Za-z]\)/\1\n\2/g' $FILE
sed -i 's/;$//g' $FILE
sed -i 's/;;;/,/g' $FILE
sed -i 's/;;/,/g' $FILE
sed -i 's/;/,/g' $FILE
sed -i 's/\.\.\.,/,/g' $FILE
sed -i 's/\.wvc,/,/g' $FILE
sed -i 's/host\///g' $FILE
sed -i 's/WVCMSDOM\\//g' $FILE
sed -i -r 's/\.wvcm?s?d?o?m?,/,/g' $FILE
}

UPDATE_DATABASE ()
{
INPUT=$FILE
OLDIFS=$IFS
IFS=,
[ ! -f $INPUT ] && { echo "$INPUT file not found"; exit 98; }
while read PORT CLIENT_STATUS SESSION_TIME CLIENT_NAME SESSION_TIMEOUT CLIENT_IP CLIENT_MAC COS_MAP IN_LIMIT UNTAGGED_VLAN OUT_LIMIT TAGGED_VLANS PORT_MODE RADIUS_ACL_LIST
	do
		MYSQL_EXIST=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$PORT_AUTH_TABLE WHERE device_id='$DEVICE_ID' AND port='$PORT' AND client_name='$CLIENT_NAME';"`
		if [[ -z "$MYSQL_EXIST" ]]
			then
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $PORT_AUTH_TABLE(id,device_id,port,client_status,session_time,client_name,session_timeout,client_ip,client_mac,cos_map,in_limit,untagged_vlan,out_limit,tagged_vlans,port_mode,radius_acl_list,updated) VALUES(NULL,'$DEVICE_ID','$PORT','$CLIENT_STATUS','$SESSION_TIME','$CLIENT_NAME','$SESSION_TIMEOUT','$CLIENT_IP','$CLIENT_MAC','$COS_MAP','$IN_LIMIT','$UNTAGGED_VLAN','$OUT_LIMIT','$TAGGED_VLANS','$PORT_MODE','$RADIUS_ACL_LIST',NOW());
EOF
			else
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $PORT_AUTH_TABLE SET client_status='$CLIENT_STATUS',session_time='$SESSION_TIME',session_timeout='$SESSION_TIMEOUT',client_ip='$CLIENT_IP',client_mac='$CLIENT_MAC',cos_map='$COS_MAP',in_limit='$IN_LIMIT',untagged_vlan='$UNTAGGED_VLAN',out_limit='$OUT_LIMIT',tagged_vlans='$TAGGED_VLANS',port_mode='$PORT_MODE',radius_acl_list='$RADIUS_ACL_LIST',updated=NOW() WHERE id='$MYSQL_EXIST';
EOF
		fi
done < $INPUT
IFS=$OLDIFS
}

UPDATE_NAME ()
{
USERNAMES=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT client_name FROM $LOCAL_DATABASE.$PORT_AUTH_TABLE WHERE device_id='$DEVICE_ID';"`
for USERNAME in $USERNAMES
	do
		NAME=
		NAME=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_SEARCH_CRITERIA=*$USERNAME*))" $LDAP_NAME_ATT | egrep --color=never -o "^$LDAP_NAME_ATT:.+$" | sed "s/$LDAP_NAME_ATT: //g")
		USERNAME_AD=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_SEARCH_CRITERIA=*$USERNAME*))" $LDAP_USERNAME_ATT | egrep --color=never -o "^$LDAP_USERNAME_ATT:.+$" | sed "s/$LDAP_USERNAME_ATT: //g")
		FIRST_NAME=$(echo "$NAME" | egrep --color=never -o '^[A-Za-z]+\s' | sed 's/ //g')
		LAST_NAME=$(echo "$NAME" | egrep --color=never -o '\s[A-Za-z]+$' | sed 's/ //g')
		if [[ -n "$NAME" ]]
			then
				PORT_AUTH_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$PORT_AUTH_TABLE WHERE client_name='$USERNAME';"`
				mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $PORT_AUTH_TABLE SET first_name='$FIRST_NAME',last_name='$LAST_NAME',username='$USERNAME_AD',updated=NOW() WHERE id='$PORT_AUTH_ID';
EOF
				UPDATE_SWITCHPORT
		fi
done
}

UPDATE_SWITCHPORT ()
{
IP=
PORT=
OID_ID=
INT_ALIAS_OID=
PORT_IDENTIFIER=
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the name on the switch port"${RESET} >> $LOG
IP=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $DEVICE_TABLE.ip FROM $LOCAL_DATABASE.$PORT_AUTH_TABLE LEFT JOIN $LOCAL_DATABASE.$DEVICE_TABLE ON $PORT_AUTH_TABLE.device_id=$DEVICE_TABLE.id WHERE $PORT_AUTH_TABLE.id='$PORT_AUTH_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Switch IP: $IP"${RESET} >> $LOG
PORT=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT port FROM $LOCAL_DATABASE.$PORT_AUTH_TABLE WHERE $PORT_AUTH_TABLE.id='$PORT_AUTH_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port: $PORT"${RESET} >> $LOG
OID_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT oid_id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}OID ID: $OID_ID"${RESET} >> $LOG
INT_ALIAS_OID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT int_alias FROM $LOCAL_DATABASE.$OID_TABLE WHERE id='$OID_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface Alias OID: $INT_ALIAS_OID"${RESET} >> $LOG
PORT_IDENTIFIER=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $INTERFACE_TABLE.port FROM $LOCAL_DATABASE.$INTERFACE_TABLE LEFT JOIN $LOCAL_DATABASE.$DEVICE_TABLE ON $INTERFACE_TABLE.device_id=$DEVICE_TABLE.id WHERE $DEVICE_TABLE.ip='$IP' AND $INTERFACE_TABLE.port_name='$PORT';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port Identifier: $PORT_IDENTIFIER"${RESET} >> $LOG
snmpset -v $SNMP_VERSION -c $SNMP_COMMUNITY $IP $INT_ALIAS_OID.$PORT_IDENTIFIER s "$NAME" &> /dev/null
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
		echo -e ${REDF}"No IPs or Hostnames provided. This script is exiting"${RESET}
		EXIT_CODE="85"
		EXIT_FUNCTION
fi
for IP in $IPS
	do
		if ping -c 1 -W 1 $IP &> /dev/null
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking IP $IP"${RESET} >> $LOG
				# FILE=$PORT_AUTH_FILE.$IP
				rm -Rf $FILE &> /dev/null
				GET_DEVICE_ID
				GET_SNMP_CREDS
				GET_FILE
				# CLEANUP_FILE
				# UPDATE_DATABASE
				# UPDATE_NAME
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}$IP is not reachable. Moving on"${RESET} >> $LOG
		fi
done

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit





CREATE TABLE `port_auth` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `device_id` int(11) NOT NULL DEFAULT '0',
  `port` varchar(50) NOT NULL DEFAULT '0',
  `client_status` varchar(50) DEFAULT NULL,
  `session_time` int(10) DEFAULT NULL,
  `client_name` varchar(150) DEFAULT NULL,
  `session_timeout` int(10) DEFAULT NULL,
  `client_ip` varchar(50) DEFAULT NULL,
  `client_mac` varchar(50) DEFAULT NULL,
  `cos_map` varchar(100) DEFAULT NULL,
  `in_limit` varchar(50) DEFAULT NULL,
  `untagged_vlan` varchar(150) DEFAULT NULL,
  `out_limit` varchar(50) DEFAULT NULL,
  `tagged_vlans` varchar(150) DEFAULT NULL,
  `port_mode` varchar(50) DEFAULT NULL,
  `radius_acl_list` varchar(50) DEFAULT NULL,
  `first_name` varchar(150) DEFAULT NULL,
  `last_name` varchar(150) DEFAULT NULL,
  `username` varchar(150) DEFAULT NULL,
  `updated` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `added` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FK_port_auth_device` (`device_id`),
  CONSTRAINT `FK_port_auth_device` FOREIGN KEY (`device_id`) REFERENCES `device` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=573 DEFAULT CHARSET=latin1 ROW_FORMAT=COMPACT
