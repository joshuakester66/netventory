#!/bin/bash
#Filename: netventory_installer.sh
#Description: 
#Requirements:
# Commands to get installer
# sudo yum install -y dos2unix wget
# wget -O netventory_installer.sh https://www.dropbox.com/s/r95ocaa77o06qxn/netventory_installer.sh?dl=0
# dos2unix netventory_installer.sh &> /dev/null
# /bin/bash netventory_installer.sh
#Packages:
# wget

# read -p "Press enter to continue. " DEBUG #DEBUG

SCRIPT_NAME="netventory_installer"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
DOWNLOAD_DIR="/tmp"
NET_FILES="netventory_files"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
WINEXE_URI="https://www.dropbox.com/s/h6by8pi6qt1k6l2/winexe-static-2?dl=0"
NETVENTORY_INSTALLER_URI="https://www.dropbox.com/s/r95ocaa77o06qxn/netventory_installer.sh?dl=0"
FILES_URI="https://www.dropbox.com/sh/qd5jgznytk312jf/AABFQnFDx1rlMSIF69MSikFLa?dl=0"
# INSTALL_DIR="/opt/netventory"
INSTALL_DIR="$HOME/scripts/$SCRIPT_CAT"
SYSTEM_USER="netventory"
PACKAGES="
bc
curl
dos2unix
expect
fping
httpd
httpd-tools
initscripts
jwhois
lynx
mariadb-server
mariadb
mtr
netcat
net-snmp
net-snmp-utils
net-tools
nmap
OpenIPMI
openldap-clients
php
php-cli
php-common
php-mysqlnd
php-pdo
procmail
rsync
sendmail
tcl
tcpdump
telnet
traceroute
unixODBC
unzip
wget
zip
"
PACKAGES=$(echo "$PACKAGES" | tr "\n" " ")

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

GET_SUDO_PERMISSIONS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Elevating permissions"${RESET} >> $LOG
sudo echo "Elevating permissions"
}

CREATE_INSTALL_DIR ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Creating the install directory $INSTALL_DIR"${RESET} >> $LOG
sudo mkdir -p $INSTALL_DIR &> /dev/null
}

CREATE_NETVENTORY_USER ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Creating the system user $SYSTEM_USER"${RESET} >> $LOG
sudo useradd $SYSTEM_USER -d $INSTALL_DIR -M -r -s "$(which bash)" &> /dev/null
}

GET_PACKAGES ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the system and installing the necessary packages"${RESET} >> $LOG
sudo yum update -y
sudo yum install -y epel-release
sudo yum update -y
sudo rpm -Uvh http://li.nux.ro/download/nux/dextop/el7/x86_64/nux-dextop-release-0-5.el7.nux.noarch.rpm
sudo sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/nux-dextop.repo
sudo sed -i 's/enabled = 1/enabled = 0/g' /etc/yum.repos.d/nux-dextop.repo
sudo yum update -y
sudo yum --enablerepo=nux-dextop install -y winexe
sudo yum install -y $PACKAGES
wget -O /tmp/winexe-static-2 https://www.dropbox.com/s/h6by8pi6qt1k6l2/winexe-static-2?dl=0
sudo mv /tmp/winexe-static-2 /usr/bin/winexe-static-2 &> /dev/null
sudo chmod 755 /usr/bin/winexe-static-2 &> /dev/null
}

GET_FILES ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the $SCRIPT_CAT files"${RESET} >> $LOG
wget -O $DOWNLOAD_DIR/$NET_FILES.zip $FILES_URI
sudo unzip -o $DOWNLOAD_DIR/$NET_FILES.zip -d $INSTALL_DIR/
sudo chown -R netventory:netventory $INSTALL_DIR
}

SETUP_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}SETUP_DATABASE function needs to be completed"${RESET} >> $LOG
}

SETUP_CRON ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Setting up the cron job for $SYSTEM_USER"${RESET} >> $LOG
sudo cp $INSTALL_DIR/netventory.cron /etc/cron.d/netventory
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

GET_SUDO_PERMISSIONS
CREATE_NETVENTORY_USER
GET_PACKAGES
GET_FILES
SETUP_DATABASE
SETUP_CRON

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the script"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
