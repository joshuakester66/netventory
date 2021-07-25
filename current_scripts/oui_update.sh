#!/bin/bash
#Filename: netventory.oui_update.sh
#Description: 
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# wget
# mariadb-server/mysqld
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="netventory.oui_update"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | egrep ^mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | egrep ^mysql_password: | sed 's/mysql_password://g')
#DOWNLOAD_URL="http://anonsvn.wireshark.org/wireshark/trunk/manuf"
DOWNLOAD_URL="https://macaddress.io/database/macaddress.io-db.csv"
LOCAL_DATABASE="netventory"
OUI_TABLE="oui"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
FILE_EDITED="$WORKING_DIR/file_edited"

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

GET_OUI_FILE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Downloading the file"${RESET} >> $LOG
wget $DOWNLOAD_URL --output-document $FILE &> /dev/null
if [[ -f "$FILE" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File downloaded"${RESET} >> $LOG
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}$FILE does not exist"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}Exiting"${RESET} >> $LOG
		EXIT_CODE="69"
		EXIT_FUNCTION
fi
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Cleaning up the file"${RESET} >> $LOG
# cat $FILE | sed 's/\:[0-9A-Fa-f]\{2\}\:[0-9A-Fa-f]\{2\}\:[0-9A-Fa-f]\{2\}\/[0-9]\{1,2\}\s*\([A-Za-z0-9-]*\)\s/;;\1;;/g' | sed 's/\([0-9A-Fa-f]\{2\}\:[0-9A-Fa-f]\{2\}\:[0-9A-Fa-f]\{2\}\)\s*\([A-Za-z0-9-]*$\)/\1;;\2;;/g' | sed 's/\([0-9A-Fa-f]\{2\}\:[0-9A-Fa-f]\{2\}\:[0-9A-Fa-f]\{2\}\)\s*\([A-Za-z0-9-]*\)\s/\1;;\2;;/g' | sed 's/;;;;/;;/g' | sed '/^\s/d' | sed '/^#.*/d' | sed '/^$/d' > $FILE_EDITED
cat $FILE | sed 's/,0,/,/g' | sed 's/,1,/,/g' | sed 's/,[^,]*,[^,]*,[^,]*,[^,]*$//g' > $FILE_EDITED

}

UPDATE_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Deleting the existing data in the table"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
TRUNCATE $LOCAL_DATABASE.$OUI_TABLE;
EOF
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Importing the new data"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
# LOAD DATA LOW_PRIORITY LOCAL INFILE '$FILE_EDITED' REPLACE INTO TABLE $LOCAL_DATABASE.$OUI_TABLE FIELDS TERMINATED BY ';;' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES (mac,vendor,manufacturer);
# EOF
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Importing the new data"${RESET} >> $LOG
mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
LOAD DATA LOW_PRIORITY LOCAL INFILE '$FILE_EDITED' REPLACE INTO TABLE $LOCAL_DATABASE.$OUI_TABLE FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES (mac,vendor,address);
EOF
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Cleaning up the data"${RESET} >> $LOG
# mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $LOCAL_DATABASE << EOF
# UPDATE $LOCAL_DATABASE.$OUI_TABLE SET manufacturer='' WHERE manufacturer IS NULL;
# UPDATE $LOCAL_DATABASE.$OUI_TABLE SET description='' WHERE description IS NULL;
# EOF
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Database updated"${RESET} >> $LOG
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started."${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution."${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked."${RESET} >> $LOG

rm -rf $FILE &> /dev/null

GET_OUI_FILE
UPDATE_DATABASE

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file."${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
