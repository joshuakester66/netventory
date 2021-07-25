#!/bin/bash
#Filename: script_template.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# openldap-clients.x86_64
# expect-tcl
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="script_template"
SCRIPT_CAT="test_dir"

mkdir -p $HOME/scripts/logs &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/scripts/logs/$SCRIPT_NAME.log"
EXPECT_LOG="$HOME/scripts/tmp/$SCRIPT_NAME/logs/expect.log"
CREDENTIALS="$HOME/scripts/.credentials"
SPILLMAN_USERNAME=$(cat $CREDENTIALS | grep spillman_username: | sed 's/spillman_username://g')
SPILLMAN_PASSWORD=$(cat $CREDENTIALS | grep spillman_password: | sed 's/spillman_password://g')
MYSQL_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
NETWORK_USERNAME=$(cat $CREDENTIALS | grep network_username: | sed 's/network_username://g')
NETWORK_PASSWORD=$(cat $CREDENTIALS | grep network_password: | sed 's/network_password://g')
NETWORK_USERNAME_ADMIN=$(cat $CREDENTIALS | grep network_username_admin: | sed 's/network_username_admin://g')
NETWORK_PASSWORD_ADMIN=$(cat $CREDENTIALS | grep network_password_admin: | sed 's/network_password_admin://g')
SNMPV2_USERNAME=$(cat $CREDENTIALS | grep snmpv2_username: | sed 's/snmpv2_username://g')
SNMP_MIB_VLAN="mib-2.17.7.1.4.3.1.1"
SNMP_MIB_NAME="1.3.6.1.2.1.1.5"
# SNMP_MIB_NAME="sysname"
SNMP_MIB_MAC="mib-2.17.1.1.0"
SNMP_MIB_SYSTEM="system"
LDAP_URI_1='ldap://chwsdc1.wvcmsdom:389'
LDAP_URI_2='ldap://chwsdc2.wvcmsdom:389'
#LDAP_URI_3='ldap://chwsdc3.wvcmsdom:389'
LDAP_URI_3='ldap://mcwv-dc1.wvcmsdom:389'
LDAP_QUERY_USERNAME=$(cat $CREDENTIALS | grep ldap_username: | sed 's/ldap_username://g')
LDAP_QUERY_PASSWORD=$(cat $CREDENTIALS | grep ldap_password: | sed 's/ldap_password://g')
LDAP_DOMAIN="wvcmsdom"
LDAP_ATTRIBUTES="cn sn displayName employeeID mail telephoneNumber mobile physicalDeliveryOfficeName sAMAccountName"
LDAP_NAME_ATT="cn"
# LDAP_NAME_ATT="displayName"
LDAP_EMPLOYEE_ID_ATT="displayName"
LDAP_BADGE_NUMBER_ATT="badgeNumber"
LDAP_USERNAME_ATT="sAMAccountName"
LDAP_USER_DN="OU=Domain Users,DC=wvcmsdom"
EMAIL="/home/jkester/scripts/backup_scripts/NetworkBackupDailyEmail"
RECIPIENT="josh.kester@wvc-ut.gov"
LOCAL_DATABASE="test"
LOCAL_TABLE="test"
IP_COLUMN="ip"
ODBC_SERVER="Shoretel"
REMOTE_DATABASE="test"
REMOTE_TABLE="test"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
SQL_COMMAND="SELECT name FROM test.test WHERE name='test' ORDER BY name;"

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

VARIABLE_FROM_SNMP ()
{
VLANS=$(snmpwalk -t 0.2 -v 2c -c $SNMPV2_USERNAME $IP $SNMP_MIB_VLAN | egrep --color=never -o '[0-9]{1,4}\s=\sSTRING:.+$' | sed 's/STRING: //g' | sed 's/ = /:/g' | sed 's/"//g')
}

EXPECT_TEMPLATE ()
{
rm -rf $EXPECT_LOG &> /dev/null
/usr/bin/expect << EOF
set timeout 5
# log_user 0
# log_file -a $EXPECT_LOG
log_file $EXPECT_LOG
spawn -noecho ssh $NETWORK_USERNAME@$IP
expect {
	"Are you sure you want to continue" {
		send "yes\r"
	}
	"s password:" {
		send "$NETWORK_PASSWORD\r"
	}
	"Press any key to continue" {
		send "ne\r"
	}
	"#" {
		send "ne\r"
	}
}
expect {
	"s password:" {
		send "$NETWORK_PASSWORD\r"
	}
	"Press any key to continue" {
		send "ne\r"
	}
	"#" {
		send "ne\r"
	}
}
expect {
	"Press any key to continue" {
		send "ne\r"
	}
	"#" {
		send "ne\r"
	}
}
expect "#"
send "show system\r"
expect "#"
send "logout\r"
EOF
echo >> $EXPECT_LOG
tr -cd "[:print:]\n" < $EXPECT_LOG
}

EMAIL ()
{
echo "To: $RECIPIENT
From: heimdall@wvc-ut.gov
Subject: The subject of the email goes here
" > "$EMAIL"
echo "The body of the email goes here" >> "$EMAIL"
# For the next two lines you must manually enter them in the script
# by pressing ctrl+v then without releasing ctrl press [ or m
sed -i 's/^[//g' "$EMAIL"
sed -i 's/^M//g' "$EMAIL"
sed -i 's/\[0m//g' "$EMAIL"
sed -i 's/\[31m//g' "$EMAIL"
sed -i 's/\[32m//g' "$EMAIL"
sed -i 's/\[33m//g' "$EMAIL"
ssmtp "$RECIPIENT" < "$EMAIL"
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished.  The results have been emailed"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG
}

SELECT_MYSQL ()
{
IPS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$LOCAL_TABLE;"`
}

ADD_MYSQL ()
{
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $LOCAL_TABLE(test_id,column1,column2,date,time) VALUES(NULL,'$COLUMN1_VAR','$COLUMN2_VAR','$TODAY','$NOW');
EOF
}

UPDATE_MYSQL ()
{
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $LOCAL_TABLE SET date='$TODAY',time='$NOW' WHERE test_id='$TEST_ID_VAR';
EOF
}

DB_TO_FILE ()
{
MYSQL=`echo "$SQL_COMMAND" | isql $ODBC_SERVER -b -c -d,`
echo "$MYSQL" | sed '/MACAddress/d' > $FILE
sed -i 's/.*/"&"/' $FILE
sed -i 's/,/","/g' $FILE
for LINE in `cat $FILE`
	do
		MAC_ORIGINAL=$(echo $LINE | egrep -o '[0-9A-Za-z]{12}')
		MAC="${MAC_ORIGINAL,,}"
		MAC=$(echo "$MAC" | sed 's/\(\w\w\)\(\w\w\)\(\w\w\)\(\w\w\)\(\w\w\)\(\w\w\)/\1:\2:\3:\4:\5:\6/g')
		sed -i "s|,\"$MAC_ORIGINAL\"|,\"$MAC_ORIGINAL\",\"$MAC\"|g" $FILE
done
sed -i 's/^/NULL,/' $FILE
}

LDAP_QUERY ()
{
LDAP_USERNAME_SEARCH="jkester"
ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(sAMAccountName=$LDAP_USERNAME_SEARCH)" $LDAP_ATTRIBUTES
}

FILE_TO_DB ()
{
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
truncate $LOCAL_TABLE;
load data local infile "$FILE" into table $LOCAL_DATABASE.$LOCAL_TABLE fields terminated by ',' enclosed by '"' lines terminated by '\n';
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the script for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Script has been locked"${RESET} >> $LOG
# for IP in `cat IPlist`
# IPS="10.10.10.1 10.10.10.2"
# for IP in $IPS

if [[ -z "$IPS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs provided"${RESET} >> $LOG
		echo "No IPs provided. This script is exiting"
		EXIT_CODE="85"
		EXIT_FUNCTION
fi

SELECT_MYSQL
for IP in $IPS
	do
		echo "$IP"
done

if [[ -z "$IPS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No IPs or Hostnames provided"${RESET} >> $LOG
		echo
		echo -e ${REDF}"No IPs or Hostnames provided. This script is exiting"${RESET}
		EXIT_CODE="85"
		EXIT_FUNCTION
fi

# VARIABLE_FROM_SNMP
# EMAIL
# ADD_MYSQL
# UPDATE_MYSQL
# DB_TO_FILE
# FILE_TO_DB
# LDAP_QUERY

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the script"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
