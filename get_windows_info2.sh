#!/bin/bash

WMIC_PASSWORD=$1
WMIC_CLASS=$2
if [[ -z "$WMIC_PASSWORD" ]]
	then
		read -p "What's the password? " WMIC_PASSWORD
fi
if [[ -z "$WMIC_CLASS" ]]
	then
		read -p "What's the Class you'd like to look at? " WMIC_CLASS
fi

RESULTS=
CLASS=
ARRAY1=()
ARRAY2=()
CLASS=$(wmic --user "wvcmsdom\jkester" --password "$WMIC_PASSWORD" --delimiter='" "' //10.10.50.50 "SELECT * FROM $WMIC_CLASS" | head -n 1)
# echo "$CLASS"
# read -p "Press any key to continue." DEBUG
ARRAY1=(`wmic --user "wvcmsdom\jkester" --password "$WMIC_PASSWORD" --delimiter='" "' //10.10.50.50 "SELECT * FROM $WMIC_CLASS" | head -n 2 | tail -n 1 | sed 's/^/\"/g' | sed 's/$/\"/g'`)
ARRAY2=(`wmic --user "wvcmsdom\jkester" --password "$WMIC_PASSWORD" --delimiter='" "' //10.10.50.50 "SELECT * FROM $WMIC_CLASS" | tail -n 1 | sed 's/^/\"/g' | sed 's/$/\"/g'`)
# echo "${ARRAY1[@]}"
# read -p "Press any key to continue." DEBUG
# echo "${ARRAY2[@]}"
# read -p "Press any key to continue." DEBUG
echo "$CLASS"
# for INDEX in ${!ARRAY1[@]}
# # for ((INDEX=0; INDEX < ${#ARRAY1[@]}; INDEX++))
# 	do
# 		echo "${ARRAY1[$INDEX]}: ${ARRAY2[$INDEX]}"
# done

# for ((i=0;i<${#ARRAY1[@]};++i)); do
#     printf "%s: %s\n" "${ARRAY1[i]}" "${ARRAY2[i]}"
# done

for INDEX in ${!ARRAY1[*]}
	do
		echo "$INDEX"
		echo "${ARRAY1[$INDEX]}: ${ARRAY2[$INDEX]}"
done
# echo "${ARRAY2[@]}"

exit
