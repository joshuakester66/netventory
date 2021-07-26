#!/bin/bash
#Filename: netventory.runtime.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
#Packages:
# openldap-clients.x86_64
# expect-tcl

# read -p "Press any key to continue. " DEBUG #DEBUG

SCRIPT_NAME="netventory.runtime"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
TODAY_MONTH_DAY=`date +%B\ %d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
DATABASE_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
DATABASE_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
LOCAL_DATABASE="netventory"
RUNTIME_TABLE="runtime"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
LOG_DIR="$HOME/logs/netventory"
ITERATION_START="1"
ITERATION_MAX="3"
FILE_LINES="$(( $ITERATION_MAX * 2 ))"
ARRAY_INDEX_START="0"
ARRAY_INDEX_MAX="$(( $FILE_LINES - 1 ))"

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

VALIDATE_DATA ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Validating the file"${RESET} >> $LOG
ENOUGH_STARTS=
ENOUGH_FINISHES=
ENOUGH_STARTS=$(echo "${FILE_ARRAY[@]}" | grep --color=never -o "start" | wc -l)
if [[ "$ENOUGH_STARTS" != "$ITERATION_MAX" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Not the proper amount of starts in this file"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Skipping $LOG_FILE"${RESET} >> $LOG
		continue
fi	
ENOUGH_FINISHES=$(echo "${FILE_ARRAY[@]}" | grep --color=never -o "finish" | wc -l)
if [[ "$ENOUGH_FINISHES" != "$ITERATION_MAX" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Not the proper amount of finishes in this file"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Skipping $LOG_FILE"${RESET} >> $LOG
		continue
fi	
ARRAY_INDEX=$ARRAY_INDEX_START
while [[ "$ARRAY_INDEX" -le "$ARRAY_INDEX_MAX" ]]
	do
		if (( $ARRAY_INDEX % 2 ))
			then
				KEYWORD="finish"
			else
				KEYWORD="start"
		fi
		VALIDATE_ORDER
		let ARRAY_INDEX+=1
done
}

VALIDATE_ORDER ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Validating the order of line $(( $ARRAY_INDEX + 1 ))"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Looking at array index [$ARRAY_INDEX] for $KEYWORD"${RESET} >> $LOG
VALIDATE_ORDER=$(echo "${FILE_ARRAY[$ARRAY_INDEX]}" | grep --color=never "$KEYWORD")
if [[ -z "$VALIDATE_ORDER" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Lines are not in the proper order"${RESET} >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${YELLOWF}Skipping $LOG_FILE"${RESET} >> $LOG
		INVALID="1"
		break
	else
		INVALID=
fi	
}

GET_DURATION ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Calculating the duration"${RESET} >> $LOG
IFS=: read START_HOUR START_MIN START_SEC <<< "$CURRENT_START"
IFS=: read FINISH_HOUR FINISH_MIN FINISH_SEC <<< "$CURRENT_FINISH"
START_HOUR=$(echo "$START_HOUR" | sed 's/^0*\([0-9]\)/\1/g')
START_MIN=$(echo "$START_MIN" | sed 's/^0*\([0-9]\)/\1/g')
START_SEC=$(echo "$START_SEC" | sed 's/^0*\([0-9]\)/\1/g')
FINISH_HOUR=$(echo "$FINISH_HOUR" | sed 's/^0*\([0-9]\)/\1/g')
FINISH_MIN=$(echo "$FINISH_MIN" | sed 's/^0*\([0-9]\)/\1/g')
FINISH_SEC=$(echo "$FINISH_SEC" | sed 's/^0*\([0-9]\)/\1/g')
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Start Hour: $START_HOUR"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Start Minutes: $START_MIN"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Start Seconds: $START_SEC"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Finish Hours: $FINISH_HOUR"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Finish Minutes: $FINISH_MIN"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Finish Seconds: $FINISH_SEC"${RESET} >> $LOG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}START_HOUR_SEC=\$(( 60 * ( $START_HOUR * 60 )))"${RESET} >> $LOG
START_HOUR_SEC=$(( 60 * ( $START_HOUR * 60 )))
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}START_MIN_SEC=\$((( $START_MIN * 60 )))"${RESET} >> $LOG
START_MIN_SEC=$((( $START_MIN * 60 )))
# read -p "Press enter to continue " DEBUG #DEBUG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}FINISH_HOUR_SEC=\$(( 60 * ( $FINISH_HOUR * 60 )))"${RESET} >> $LOG
FINISH_HOUR_SEC=$(( 60 * ( $FINISH_HOUR * 60 )))
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}FINISH_MIN_SEC=\$((( $FINISH_MIN * 60 )))"${RESET} >> $LOG
FINISH_MIN_SEC=$((( $FINISH_MIN * 60 )))
# read -p "Press enter to continue " DEBUG #DEBUG
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}START_SEC=\$((( $START_HOUR_SEC + $START_MIN_SEC + $START_SEC)))"${RESET} >> $LOG
START_SEC=$((( $START_HOUR_SEC + $START_MIN_SEC + $START_SEC)))
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}FINISH_SEC=\$((( $FINISH_HOUR_SEC + $FINISH_MIN_SEC + $FINISH_SEC )))"${RESET} >> $LOG
FINISH_SEC=$((( $FINISH_HOUR_SEC + $FINISH_MIN_SEC + $FINISH_SEC )))
# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}DURATION_SEC=\$((( $FINISH_SEC - $START_SEC )))"${RESET} >> $LOG
DURATION_SEC=$((( $FINISH_SEC - $START_SEC )))
}

GET_AVERAGE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the average for the $FILE_LINES file lines"${RESET} >> $LOG
AVG_RUNTIME=$((( $AVG_SUM ) / $ITERATION_MAX ))
}

CONVERT_SECONDS_TO_HOURS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Converting seconds to time"${RESET} >> $LOG
NUM=$AVG_RUNTIME
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
AVG_RUNTIME="$HOUR:$MIN:$SEC"
}

GET_LAST_RUN ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking for the last time $FILENAME was run"${RESET} >> $LOG
LAST_RUN=$(tail -n 5 $LOG_FILE | egrep -o --color=never '^[A-Z][a-z]{2}\s[0-9]{2}\s[0-9]{4}\s[0-9]{2}\:[0-9]{2}\:[0-9]{2}' | tail -n 1)
LAST_RUN=`date -d "$LAST_RUN" +%Y-%m-%d\ %H:%M:%S`
}

UPDATE_DATABASE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the database"${RESET} >> $LOG
GET_DATABASE_ID
if [[ -z "$RUNTIME_ID" ]]
	then
		ADD_TO_TABLE
	else
		UPDATE_TABLE
fi
}

GET_DATABASE_ID ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the database ID"${RESET} >> $LOG
RUNTIME_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$RUNTIME_TABLE WHERE file='$FILENAME';"`
}

ADD_TO_TABLE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding the data to the $RUNTIME_TABLE table"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}INSERT INTO $RUNTIME_TABLE(file,location,avg_runtime,last_run,updated,added) VALUES('$FILENAME','$LOG_DIR','$AVG_RUNTIME','$LAST_RUN',NOW(),NOW());"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $RUNTIME_TABLE(file,location,avg_runtime,last_run,updated,added) VALUES('$FILENAME','$LOG_DIR','$AVG_RUNTIME','$LAST_RUN',NOW(),NOW());
EOF
}

UPDATE_TABLE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the data in the $RUNTIME_TABLE table"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}UPDATE $RUNTIME_TABLE SET file='$FILENAME',location='$LOG_DIR',avg_runtime='$AVG_RUNTIME',last_run='$LAST_RUN',updated=NOW() WHERE id='$RUNTIME_ID';"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $RUNTIME_TABLE SET file='$FILENAME',location='$LOG_DIR',avg_runtime='$AVG_RUNTIME',last_run='$LAST_RUN',updated=NOW() WHERE id='$RUNTIME_ID';
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

LOG_FILES=$(ls $LOG_DIR/netventory.*)
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Found the following files in $LOG_DIR:"${RESET} >> $LOG
echo "$LOG_FILES" >> $LOG
AVG_SUM="0"
for LOG_FILE in $LOG_FILES
	do
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ====================" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Checking on $LOG_FILE"${RESET} >> $LOG
		FILENAME=$(echo "$LOG_FILE" | sed 's/^.*\///g' | sed 's/\.log//g' | sed 's/^netventory\.//g')
		FILE_ARRAY=($(grep --color=never "start\|finish" $LOG_FILE | tail -n "$FILE_LINES" | sed 's/ /_/g' | tr "\n" " "))
		VALIDATE_DATA
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		if [[ "$INVALID" == "1" ]]
			then
				continue
		fi
		FILE_ITERATION=$ITERATION_START
		ARRAY_INDEX=$ARRAY_INDEX_START
		while [[ "$FILE_ITERATION" -le "$ITERATION_MAX" ]]
			do
				CURRENT_START=$(echo "${FILE_ARRAY[$ARRAY_INDEX]}" | egrep --color=never -o '[0-9]{2}\:[0-9]{2}\:[0-9]{2}')
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Current Index: $ARRAY_INDEX"${RESET} >> $LOG
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Current Start: $CURRENT_START"${RESET} >> $LOG
				let ARRAY_INDEX+=1
				CURRENT_FINISH=$(echo "${FILE_ARRAY[$ARRAY_INDEX]}" | egrep --color=never -o '[0-9]{2}\:[0-9]{2}\:[0-9]{2}')
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Current Index: $ARRAY_INDEX"${RESET} >> $LOG
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Current Finish: $CURRENT_FINISH"${RESET} >> $LOG
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Start $FILE_ITERATION: $CURRENT_START"${RESET} >> $LOG
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Finish $FILE_ITERATION: $CURRENT_FINISH"${RESET} >> $LOG
				GET_DURATION
				CURRENT_DURATION=$DURATION_SEC
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Duration $FILE_ITERATION: $CURRENT_DURATION"${RESET} >> $LOG
				let ARRAY_INDEX+=1
				let FILE_ITERATION+=1
				let AVG_SUM+=$CURRENT_DURATION
		echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ==========" >> $LOG
		done
		GET_AVERAGE
		if [[ "$AVG_RUNTIME" == "0" ]]
			then
				AVG_RUNTIME="00:00:00"
			else
				CONVERT_SECONDS_TO_HOURS
		fi
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Average Runtime: $AVG_RUNTIME"${RESET} >> $LOG
		GET_LAST_RUN
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Last Run: $LAST_RUN"${RESET} >> $LOG
		UPDATE_DATABASE
		# read -p "Press enter to continue " DEBUG #DEBUG
done
echo "`date +%b\ %d\ %Y\ %H:%M:%S`: ====================" >> $LOG


echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the script"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
