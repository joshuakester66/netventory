#!/bin/bash

MYSQL_PASSWORD=$1

if [[ -z "$MYSQL_PASSWORD" ]]
	then
		read -p "What is the password for the database root user? " MYSQL_PASSWORD
fi
MYSQL_USERNAME="root"
LOCAL_DATABASE="netventory"
FILE=`pwd`/database_schema.sql
rm $FILE
DB_TABLES=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SHOW TABLES IN $LOCAL_DATABASE;"`
for TABLE in $DB_TABLES
	do
		mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SHOW CREATE TABLE $LOCAL_DATABASE.$TABLE;" | sed 's/^.*CREATE /CREATE /g' | sed "s/ DEFINER\=\`.*\`@\`.*\` SQL/ SQL/g" | sed 's/\\n\s*/\n/g' | sed 's/ALGORITHM=UNDEFINED SQL SECURITY DEFINER //g' >> $FILE
		cat $FILE
done



exit
