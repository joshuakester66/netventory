#!/bin/bash
#Filename: netventory.update_user.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# openldap-clients.x86_64
# mariadb-server/mysqld
# procmail (lockfile command)

# read -p "Press enter to continue. " DEBUG #DEBUG

USERNAME=$1

SCRIPT_NAME="netventory.update_user"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
LDAP_QUERY_USERNAME=$(cat $CREDENTIALS | grep ldap_username: | sed 's/ldap_username://g')
LDAP_QUERY_PASSWORD=$(cat $CREDENTIALS | grep ldap_password: | sed 's/ldap_password://g')
LDAP_URI_1='ldap://chwsdc1.wvcmsdom:389'
LDAP_URI_2='ldap://chwsdc2.wvcmsdom:389'
LDAP_URI_3='ldap://ecws1.wvcmsdom:389'
LDAP_DOMAIN="wvcmsdom"
LDAP_ATTRIBUTES="cn displayName employeeID badgeNumber sAMAccountName sn mail telephoneNumber mobile title"
LDAP_NAME_ATT="displayName"
LDAP_EMPLOYEE_ID_ATT="employeeID"
LDAP_BADGE_NUMBER_ATT="badgeNumber"
LDAP_USERNAME_ATT="sAMAccountName"
LDAP_COMMONNAME_ATT="cn"
LDAP_SURNAME_ATT="sn"
LDAP_EMAIL_ATT="mail"
LDAP_DESKPHONE_ATT="telephoneNumber"
LDAP_CELLPHONE_ATT="mobile"
LDAP_TITLE_ATT="title"
LDAP_LOCKOUT_ATT="lockoutTime"
LDAP_DIVISION_ATT="physicalDeliveryOfficeName"
LDAP_DEPARTMENT_ATT="department"
LDAP_USER_DN="OU=Domain Users,DC=wvcmsdom"
LDAP_USER_ROOT_DN="DC=wvcmsdom"
LDAP_LOGON_ATT="lastLogon"
LDAP_PASSWORD_SET_ATT="pwdLastSet"
NETVENTORY_DATABASE="netventory"
USER_TABLE="user"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
PWD_EXPR_IN_DAYS="90"
COUNT_PER_RUN="5"
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

GET_ALL_USERS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting all enabled users from Active Directory"${RESET} >> $LOG
# ALL_USERNAMES=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)(sAMAccountName=*)(userAccountControl:1.2.840.113556.1.4.803:=2))" $LDAP_USERNAME_ATT | grep --color=never 'sAMAccountName' | sed 's/sAMAccountName: //g')
ALL_USERNAMES=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_ROOT_DN" "(&(objectClass=user)(sAMAccountName=*)(userAccountControl:1.2.840.113556.1.4.803:=2))" $LDAP_USERNAME_ATT | grep --color=never 'sAMAccountName' | sed 's/sAMAccountName: //g')
}

GET_USER_ID ()
{
USER_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username='$USERNAME';"`
if [[ -z "$USER_ID" ]]
	then
		ADD_USER
		USER_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username='$USERNAME';"`
fi
}

SELECT_NEW_USERS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the User IDs for any new users"${RESET} >> $LOG
# USER_IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username IS NOT NULL AND (first_name IS NULL OR last_name IS NULL);"`
# USER_IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE added > (NOW() - INTERVAL 3 DAY);"`
USER_IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username IS NOT NULL AND (first_name IS NULL OR last_name IS NULL) ORDER BY modified LIMIT $COUNT_PER_RUN;"`
}

SELECT_UPDATE_USERS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the User IDs for any users that need to be updated"${RESET} >> $LOG
# USER_IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username IS NOT NULL AND modified < NOW() - INTERVAL 1 DAY LIMIT $COUNT_PER_RUN;"`
USER_COUNT=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT COUNT(id) FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username IS NOT NULL;"`
COUNT_PER_RUN=$(expr $USER_COUNT / $COUNT_DIVISION)
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting up to $COUNT_PER_RUN users"${RESET} >> $LOG
USER_IDS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT id FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username IS NOT NULL ORDER BY modified LIMIT $COUNT_PER_RUN;"`
}

GET_INFO ()
{
SEARCH_CRITERIA=$LDAP_NAME_ATT
USERNAME=
NAME=
TITLE=
EMAIL=
DEPARTMENT=
DIVISION=
DESKPHONE=
CELLPHONE=
EMPLOYEE_ID=
BADGE_NUMBER=
ACCOUNT_DISABLED=
ACCOUNT_LOCKED=
LAST_LOGON=
PWD_SET=
PWD_EXPR=
USERNAME=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT username FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE id='$USER_ID';"`
USERNAME=${USERNAME,,}
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}===================="${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the relevant information for User ID: $USER_ID (Username: $USERNAME)"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Username: $USERNAME"${RESET} >> $LOG
NAME=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_NAME_ATT | egrep --color=never -o "^$LDAP_NAME_ATT:.+$" | sed "s/$LDAP_NAME_ATT: //g" | sed "s/'//g")
#read -p "Press enter to continue. " DEBUG #DEBUG
if [[ -z "$NAME" ]] 
	then
		NAME=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_COMMONNAME_ATT | egrep --color=never -o "^$LDAP_COMMONNAME_ATT:.+$" | sed "s/$LDAP_COMMONNAME_ATT: //g" | sed "s/'//g")
fi		
FIRST_NAME=$(echo "$NAME" | sed 's/\s.*$//g' | sed "s/'/\\\'/g")
FIRST_NAME=${FIRST_NAME,,}
FIRST_NAME=${FIRST_NAME^}
LAST_NAME=$(echo "$NAME" | sed 's/^.*\s//g' | sed "s/'/\\\'/g")
LAST_NAME=${LAST_NAME,,}
LAST_NAME=${LAST_NAME^}
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Name: $NAME"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
TITLE=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_TITLE_ATT | egrep --color=never -o "^$LDAP_TITLE_ATT:.+$" | sed "s/$LDAP_TITLE_ATT: //g")
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Title: $TITLE"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
EMAIL=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_EMAIL_ATT | egrep --color=never -o "^$LDAP_EMAIL_ATT:.+$" | sed "s/$LDAP_EMAIL_ATT: //g" | sed "s/'//g")
EMAIL=${EMAIL,,}
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Email: $EMAIL"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
DEPARTMENT=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_DEPARTMENT_ATT | egrep --color=never -o "^$LDAP_DEPARTMENT_ATT:.+$" | sed "s/$LDAP_DEPARTMENT_ATT: //g")
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Department: $DEPARTMENT"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
DIVISION=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_DIVISION_ATT | egrep --color=never -o "^$LDAP_DIVISION_ATT:.+$" | sed "s/$LDAP_DIVISION_ATT:\(\:\)\? //g")
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Division: $DIVISION"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
DESKPHONE=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_DESKPHONE_ATT | egrep --color=never -o "^$LDAP_DESKPHONE_ATT:.+$" | sed "s/$LDAP_DESKPHONE_ATT: //g")
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Desk Phone: $DESKPHONE"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
CELLPHONE=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_CELLPHONE_ATT | egrep --color=never -o "^$LDAP_CELLPHONE_ATT:.+$" | sed "s/$LDAP_CELLPHONE_ATT: //g")
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Cell Phone: $CELLPHONE"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
EMPLOYEE_ID=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_EMPLOYEE_ID_ATT | egrep --color=never -o "^$LDAP_EMPLOYEE_ID_ATT:.+$" | sed "s/$LDAP_EMPLOYEE_ID_ATT: //g")
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Employee ID: $EMPLOYEE_ID"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
BADGE_NUMBER=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_BADGE_NUMBER_ATT | egrep --color=never -o "^$LDAP_BADGE_NUMBER_ATT:.+$" | sed "s/$LDAP_BADGE_NUMBER_ATT: //g")
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Badge Number: $BADGE_NUMBER"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
ACCOUNT_DISABLED=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($SEARCH_CRITERIA=*$USERNAME*)(userAccountControl:1.2.840.113556.1.4.803:=2))" cn)
if [[ -n "$ACCOUNT_DISABLED" ]]
	then
		ACCOUNT_DISABLED="Disabled"
	else
		ACCOUNT_DISABLED="Enabled"
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Account status: $ACCOUNT_DISABLED"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
ACCOUNT_LOCKED=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_LOCKOUT_ATT | egrep --color=never -o "^$LDAP_LOCKOUT_ATT:.+$" | sed "s/$LDAP_LOCKOUT_ATT: //g")
if [[ "$ACCOUNT_LOCKED" == "0" ]]
	then
		ACCOUNT_LOCKED="Unlocked"
	elif [[ -z "$ACCOUNT_LOCKED" ]]
		then ACCOUNT_LOCKED="Unknown"
	else
		ACCOUNT_LOCKED="Locked"
fi
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Account Lockout: $ACCOUNT_LOCKED"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
LAST_LOGON=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_LOGON_ATT | egrep --color=never -o "^$LDAP_LOGON_ATT:.+$" | sed "s/$LDAP_LOGON_ATT: //g")


if [[ -z "$LAST_LOGON" ]]
	then
		LAST_LOGON="000000000000000000"
fi
LAST_LOGON=$(date --date="1601/1/1+$(expr $LAST_LOGON / 10000000 )Seconds" +%Y-%m-%d\ %H:%M:%S)
LAST_LOGON=$(date --date="$LAST_LOGON UTC" +%Y-%m-%d\ %H:%M:%S)
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Last Logon: $LAST_LOGON"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
PWD_SET=$(ldapsearch -x -D "$LDAP_QUERY_USERNAME@$LDAP_DOMAIN" -w $LDAP_QUERY_PASSWORD -LLL -H "$LDAP_URI_1 $LDAP_URI_2 $LDAP_URI_3" -b "$LDAP_USER_DN" "(&(objectClass=user)($LDAP_USERNAME_ATT=$USERNAME))" $LDAP_PASSWORD_SET_ATT | egrep --color=never -o "^$LDAP_PASSWORD_SET_ATT:.+$" | sed "s/$LDAP_PASSWORD_SET_ATT: //g")
if [[ -z "$PWD_SET" ]]
	then
		PWD_SET="000000000000000000"
fi
PWD_SET=$(date --date="1601/1/1+$(expr $PWD_SET / 10000000 )Seconds" +%Y-%m-%d\ %H:%M:%S)
PWD_SET=$(date --date="$PWD_SET UTC" +%Y-%m-%d\ %H:%M:%S)
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Password changed: $PWD_SET"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
PWD_EXPR=$(date --date="$PWD_SET $PWD_EXPR_IN_DAYS days" +%Y-%m-%d\ %H:%M:%S)
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Password expires: $PWD_EXPR"${RESET} >> $LOG
#read -p "Press enter to continue. " DEBUG #DEBUG
}

ADD_USER ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding $USERNAME to the $USER_TABLE table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
INSERT IGNORE INTO $USER_TABLE(username,updated,added) values('$USERNAME',NOW(),NOW()) ON DUPLICATE KEY UPDATE UPDATED=NOW();
EOF
}

UPDATE_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database for User ID: $USER_ID"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
UPDATE $USER_TABLE SET first_name='$FIRST_NAME',last_name='$LAST_NAME',title='$TITLE',email='$EMAIL',department='$DEPARTMENT',division='$DIVISION',desk_phone='$DESKPHONE',cell_phone='$CELLPHONE',employee_id='$EMPLOYEE_ID',badge_number='$BADGE_NUMBER',account_status='$ACCOUNT_DISABLED',account_lockout='$ACCOUNT_LOCKED',last_logon='$LAST_LOGON',pwd_set='$PWD_SET',pwd_expr='$PWD_EXPR',updated='$NOW' WHERE id='$USER_ID';
EOF
}

CLEANUP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Performing cleanup on the database"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Setting entries to null that are blank"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
# UPDATE
#     $USER_TABLE
# SET
# 	$FIRST_NAME = CASE $FIRST_NAME WHEN '' THEN NULL ELSE $FIRST_NAME END,
# 	$LAST_NAME = CASE $LAST_NAME WHEN '' THEN NULL ELSE $LAST_NAME END,
# 	$TITLE = CASE $TITLE WHEN '' THEN NULL ELSE $TITLE END,
# 	$EMAIL = CASE $EMAIL WHEN '' THEN NULL ELSE $EMAIL END,
# 	$DEPARTMENT = CASE $DEPARTMENT WHEN '' THEN NULL ELSE $DEPARTMENT END,
# 	$DIVISION = CASE $DIVISION WHEN '' THEN NULL ELSE $DIVISION END,
# 	$DESKPHONE = CASE $DESKPHONE WHEN '' THEN NULL ELSE $DESKPHONE END,
# 	$CELLPHONE = CASE $CELLPHONE WHEN '' THEN NULL ELSE $CELLPHONE END,
# 	$EMPLOYEE_ID = CASE $EMPLOYEE_ID WHEN '' THEN NULL ELSE $EMPLOYEE_ID END,
# 	$BADGE_NUMBER = CASE $BADGE_NUMBER WHEN '' THEN NULL ELSE $BADGE_NUMBER END,
# 	$ACCOUNT_DISABLED = CASE $ACCOUNT_DISABLED WHEN '' THEN NULL ELSE $ACCOUNT_DISABLED END,
# 	$ACCOUNT_LOCKED = CASE $ACCOUNT_LOCKED WHEN '' THEN NULL ELSE $ACCOUNT_LOCKED END,
# 	$LAST_LOGON = CASE $LAST_LOGON WHEN '' THEN NULL ELSE $LAST_LOGON END,
# 	$PWD_SET = CASE $PWD_SET WHEN '' THEN NULL ELSE $PWD_SET END
# EOF
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Deleting all entries older than $DAYS_EXPIRED"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
# DELETE FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE updated < NOW() - INTERVAL $DAYS_EXPIRED DAY;
# EOF
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $NETVENTORY_DATABASE << EOF
DELETE FROM $NETVENTORY_DATABASE.$USER_TABLE WHERE username='';
EOF
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked"${RESET} >> $LOG

# GET_ALL_USERS
# for USERNAME in $ALL_USERNAMES
# 	do
# 		USERNAME=${USERNAME,,}
# 		if [[ $USERNAME == *\$* ]]
# 			then
# 				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Username $USERNAME has a dollar sign in it. Moving on"${RESET} >> $LOG
# 				continue
# 			else
# 				ADD_USERNAME_TO_DATABASE
# 		fi
# done
if [[ -n "$USERNAME" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}This script has been run manually"${RESET} >> $LOG
		GET_USER_ID
		GET_INFO
		UPDATE_DATABASE
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}===================="${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}===================="${RESET} >> $LOG
		SELECT_NEW_USERS
		if [[ -n "$USER_IDS" ]]
			then
				for USER_ID in $USER_IDS
					do
						GET_INFO
						UPDATE_DATABASE
				done
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}No new users"${RESET} >> $LOG
		fi
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}===================="${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}===================="${RESET} >> $LOG
		SELECT_UPDATE_USERS
		for USER_ID in $USER_IDS
			do
				GET_INFO
				UPDATE_DATABASE
		done
fi
CLEANUP

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
