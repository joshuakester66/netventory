#!/bin/bash
#Filename: remove_locks.sh
#Description: 
#Requirements:
#Packages:

# read -p "Press any key to continue. " DEBUG #DEBUG

PROCESS_SEARCH=$1
LOCK_DIR=$2

SCRIPT_NAME="remove_locks"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
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

KILL_PROCESSES ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking process for $PROCESS_SEARCH."${RESET} >> $LOG
PROCESS_IDS=$(ps aux | grep -i "$PROCESS_SEARCH\." | grep --color=never -v grep | egrep --color=never -o '^[A-Za-z_-]+\s+[0-9]+\s' | sed 's/ $//g' | egrep --color=never -o '[0-9]+$')
if [[ -n "$PROCESS_IDS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Process IDs found:"${RESET} >> $LOG
		ps aux | grep -i "$PROCESS_SEARCH\." | grep --color=never -v grep >> $LOG
		for PROCESS_ID in $PROCESS_IDS
			do
				KILL_PROCESS
		done
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}No processes found"${RESET} >> $LOG
fi
}

KILL_PROCESS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Killing process $PROCESS_ID"${RESET} >> $LOG
kill $PROCESS_ID
}

REMOVE_LOCK_FILES ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Removing the locks file found in $LOCK_DIR"${RESET} >> $LOG
SCRIPT_LOCK_FILES=$(find $LOCK_DIR -name "$PROCESS_SEARCH\.*\.lock")
for SCRIPT_LOCK_FILE in $SCRIPT_LOCK_FILES
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Removing $SCRIPT_LOCK_FILE"${RESET} >> $LOG
		rm --force $SCRIPT_LOCK_FILE
done
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

if [[ -n "$PROCESS_SEARCH" ]]
	then
		if [[ -n "$LOCK_DIR" ]]
			then
				KILL_PROCESSES
				REMOVE_LOCK_FILES
			else
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No search directory provided"${RESET} >> $LOG
				echo
				EXIT_CODE="84"
				EXIT_FUNCTION
		fi
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No search term provided"${RESET} >> $LOG
		echo
		EXIT_CODE="85"
		EXIT_FUNCTION
fi

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the script"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
