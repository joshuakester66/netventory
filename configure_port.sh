#!/bin/bash
#Filename: configure_port.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# net-snmp
# net-snmp-utils
# openldap-clients.x86_64
# expect-tcl
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="configure_port"
SCRIPT_CAT="netventory"

IP=$1
PORTS=$2
NETWORK=$3
PERM_OR_TEMP=$4

mkdir -p $HOME/scripts/logs &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/scripts/logs/$SCRIPT_NAME.log"
EXPECT_LOG="$HOME/scripts/tmp/$SCRIPT_NAME/logs/expect.log"
CREDENTIALS="$HOME/scripts/.credentials"
MYSQL_USERNAME=$(cat $CREDENTIALS | grep mysql_username: | sed 's/mysql_username://g')
MYSQL_PASSWORD=$(cat $CREDENTIALS | grep mysql_password: | sed 's/mysql_password://g')
NETWORK_USERNAME=$(cat $CREDENTIALS | grep network_username: | sed 's/network_username://g')
NETWORK_PASSWORD=$(cat $CREDENTIALS | grep network_password: | sed 's/network_password://g')
NETWORK_USERNAME_ADMIN=$(cat $CREDENTIALS | grep network_username_admin: | sed 's/network_username_admin://g')
NETWORK_PASSWORD_ADMIN=$(cat $CREDENTIALS | grep network_password_admin: | sed 's/network_password_admin://g')
SNMPV2_READ_USERNAME=$(cat $CREDENTIALS | grep snmpv2_username: | sed 's/snmpv2_username://g')
SNMPV2_WRITE_USERNAME=$(cat $CREDENTIALS | grep snmpv2_write_username: | sed 's/snmpv2_write_username://g')
SNMP_VERSION="2c"
MYSQL_DATABASE="netventory"
DEVICE_TABLE="device"
INTERFACE_TABLE="interface"
VLAN_TABLE="vlan"
OID_TABLE="oid"
SWITCH_CONFIG_TABLE="switch_configuration"
NETWORK_TABLE="network"
VLAN_NAME_COLUMN="name"
VLAN_TAGGED_COLUMN="tagged"
VLAN_UNTAGGED_COLUMN="untagged"
VLAN_TABLE="vlan_discover"
INTERFACE_ENABLE="1"
INTERFACE_DISABLE="2"
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

GET_INPUT ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting input"${RESET} >> $LOG
if [[ -z "$IP" ]]
	then
		read -p "What's the IP address of the switch? : " IP
fi
if [[ -z "$IP" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No switch IP provided"${RESET} >> $LOG
		echo "No switch IP provided. This script is exiting."
		EXIT_CODE="85"
		EXIT_FUNCTION
fi
if [[ -z "$PORTS" ]]
	then
		read -p "What's the port(s) you'd like to change separated by a comma? : " PORTS
fi
if [[ -z "$PORTS" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No Ports provided"${RESET} >> $LOG
		echo "No Ports provided. This script is exiting."
		EXIT_CODE="84"
		EXIT_FUNCTION
fi
if [[ -z "$NETWORK" ]]
	then
		read -p "What network would you like to set these ports to? ie. ap : " NETWORK
fi
if [[ -z "$NETWORK" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}No network provided"${RESET} >> $LOG
		echo "No network provided. This script is exiting."
		EXIT_CODE="83"
		EXIT_FUNCTION
fi
if [[ -z "$PERM_OR_TEMP" ]]
	then
		read -p "Will this change be permanent or temporary? : " PERM_OR_TEMP
fi
if [[ -z "$PERM_OR_TEMP" ]]
	then
		PERM_OR_TEMP="t"
fi
}

CLEANUP_INPUT ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Cleanig up input"${RESET} >> $LOG
PORTS="${PORTS^^}"
PORTS_SPACED=$(echo "$PORTS" | sed 's/,/ /g')
SWITCH_CONFIG_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $SWITCH_CONFIG_TABLE.id FROM $MYSQL_DATABASE.$SWITCH_CONFIG_TABLE LEFT JOIN $MYSQL_DATABASE.$NETWORK_TABLE ON $SWITCH_CONFIG_TABLE.network_id=$NETWORK_TABLE.id WHERE $NETWORK_TABLE.subnet_name='$NETWORK';"`
if [[ -z "$SWITCH_CONFIG_ID" ]]
	then
		echo "The $NETWORK network could not be located. Please try again"
		read -p "What network would you like to set these ports to? ie. ap : " NETWORK
		SWITCH_CONFIG_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $SWITCH_CONFIG_TABLE.id FROM $MYSQL_DATABASE.$SWITCH_CONFIG_TABLE LEFT JOIN $MYSQL_DATABASE.$NETWORK_TABLE ON $SWITCH_CONFIG_TABLE.network_id=$NETWORK_TABLE.id WHERE $NETWORK_TABLE.subnet_name='$NETWORK';"`
fi
if [[ -z "$SWITCH_CONFIG_ID" ]]
	then
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}The $NETWORK network could not be located"${RESET} >> $LOG
		echo "The $NETWORK network could not be located. This script is exiting."
		EXIT_CODE="82"
		EXIT_FUNCTION
fi
case $PERM_OR_TEMP
	in
		"PERM"|"Perm"|"perm"|"Permanent"|"PERMANENT"|"permanent"|"P"|"p")	PERM_OR_TEMP="p";;
		*)																	PERM_OR_TEMP="t";;
esac
}

REMOVE_AUTHENTICATION ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Removing authentication"${RESET} >> $LOG
/usr/bin/expect << EOF
set timeout 10
log_user 0
log_file -a $LOG
spawn -noecho ssh -o StrictHostKeyChecking=no $NETWORK_USERNAME@$IP
expect {
        "fingerprint" {
                send "yes\n"
                exp_continue
        }
        "passphrase" {
                send "\n"
                exp_continue
        }
        "s password:" {
                send "$NETWORK_PASSWORD\n"
        }
}
expect {
	"Permission denied" {
		send_user "

Invalid password or username

"
		exit
		exp_continue
	}
	"Press any key to continue" {
		send "n\n"
	}
	"#" {
		send "configure\n"
	}
}
expect "#"
send "configure\n"
expect "(config)#"
send "terminal length 1000\n"
expect "(config)#"
send "show run interface $PORTS\n"
expect "(config)#"
send "show mac-address $PORTS\n"
expect "(config)#"
send "interface $PORTS\n"
expect "(eth-*)#"
send "poe-allocate-by usage\n"
expect "(eth-*)#"
send "poe-value 17\n"
expect "(eth-*)#"
send "speed-duplex $SPEED_DUPLEX\n"
expect "(eth-*)#"
send "no flow-control\n"
expect "(eth-*)#"
send "poe-lldp-detect disable\n"
expect "(eth-*)#"
send "exit\n"
expect "(config)#"
send "no port-security $PORTS\n"
expect "(config)#"
send "no aaa port-access authenticator $PORTS\n"
expect "(config)#"
send "no aaa port-access authenticator $PORTS client-limit\n"
expect "(config)#"
send "no aaa port-access authenticator $PORTS auth-vid\n"
expect "(config)#"
send "no aaa port-access authenticator $PORTS unauth-vid\n"
expect "(config)#"
send "aaa port-access authenticator $PORTS server-timeout 300\n"
expect "(config)#"
send "no aaa port-access mac-based $PORTS\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS logoff-period 300\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS addr-limit 1\n"
expect "(config)#"
send "trunk $PORTS Trk8 lacp\n"
expect "(config)#"
send "no trunk $PORTS\n"
expect "(config)#"
send "port-security $PORTS learn-mode static address-limit 2\n"
expect "(config)#"
send "vlan 2010\n"
expect "(vlan-2010)#"
send "untagged $PORTS\n"
expect "(vlan-2010)#"
send "exit\n"
expect "(config)#"
send "exit\n"
expect "#"
send "show run interface $PORTS\n"
expect "#"
send "show mac-address $PORTS\n"
expect "#"
send "write memory\n"
expect "#"
send "logout\n"
EOF
echo >> $LOG
}

SET_VLAN ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Setting the VLANS and bouncing the port(s) using SNMP"${RESET} >> $LOG
GET_VARIABLES
for PORT in $PORTS_SPACED
	do
		INTERFACE_ID=
		PORT_IDENTIFIER=
		PORT_MODULE=
		INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $INTERFACE_TABLE.id FROM $MYSQL_DATABASE.$INTERFACE_TABLE LEFT JOIN $MYSQL_DATABASE.$DEVICE_TABLE ON $INTERFACE_TABLE.device_id=$DEVICE_TABLE.id WHERE $DEVICE_TABLE.ip='$IP' AND $INTERFACE_TABLE.port_name='$PORT';"`
		PORT_IDENTIFIER=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT port FROM $MYSQL_DATABASE.$INTERFACE_TABLE WHERE id='$INTERFACE_ID';"`
		PORT_IDENTIFIER=$(echo "$PORT_IDENTIFIER" | head -n 1)
		PORT_MODULE=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT module FROM $MYSQL_DATABASE.$INTERFACE_TABLE WHERE id='$INTERFACE_ID';"`
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the port information from the database for $PORT"${RESET} >> $LOG
		# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface ID: $INTERFACE_ID"${RESET} >> $LOG
		# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Port Identifier: $PORT_IDENTIFIER"${RESET} >> $LOG
		# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Module: $PORT_MODULE"${RESET} >> $LOG
		# read -p "Press any key to continue. " DEBUG
		if [[ -n "$TAGGED_VLANS" ]]
			then
				for TAGGED_VLAN in $TAGGED_VLANS
					do
						VLAN_NAME=
						VLAN_NAME=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $VLAN_NAME_COLUMN FROM $MYSQL_DATABASE.$VLAN_TABLE WHERE vlan='$TAGGED_VLAN' LIMIT 1;"`
						snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_CREATE_OID.$TAGGED_VLAN i 4 &> /dev/null
						#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_CREATE_OID.$TAGGED_VLAN i 4"${RESET} >> $LOG
						if [[ -n "$VLAN_NAME" ]]
							then
								snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_NAME_OID.$TAGGED_VLAN s "$VLAN_NAME" &> /dev/null
								#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_NAME_OID.$TAGGED_VLAN s \"$VLAN_NAME\""${RESET} >> $LOG
						fi
						snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_OID.$PORT_IDENTIFIER u $TAGGED_VLAN &> /dev/null
						#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_OID.$PORT_IDENTIFIER u $TAGGED_VLAN "${RESET} >> $LOG
				done
		fi
		VLAN_NAME=
		VLAN_NAME=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $VLAN_NAME_COLUMN FROM $MYSQL_DATABASE.$VLAN_TABLE WHERE vlan='$UNTAGGED_VLAN' LIMIT 1;"`
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Power cycling $PORT"${RESET} >> $LOG
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_CREATE_OID.$UNTAGGED_VLAN i 4 &> /dev/null
		#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_CREATE_OID.$UNTAGGED_VLAN i 4"${RESET} >> $LOG
		if [[ -n "$VLAN_NAME" ]]
			then
				snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_NAME_OID.$UNTAGGED_VLAN s "$VLAN_NAME" &> /dev/null
				#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_NAME_OID.$UNTAGGED_VLAN s \"$VLAN_NAME\""${RESET} >> $LOG
		fi
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_OID.$PORT_IDENTIFIER u $UNTAGGED_VLAN &> /dev/null
		#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $VLAN_OID.$PORT_IDENTIFIER u $UNTAGGED_VLAN"${RESET} >> $LOG
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_POE_OID.$PORT_MODULE.$PORT_IDENTIFIER i $INTERFACE_DISABLE &> /dev/null
		#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_POE_OID.$PORT_IDENTIFIER i $INTERFACE_DISABLE"${RESET} >> $LOG
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_ADMIN_OID.$PORT_IDENTIFIER i $INTERFACE_DISABLE &> /dev/null
		#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_ADMIN_OID.$PORT_IDENTIFIER i $INTERFACE_DISABLE"${RESET} >> $LOG
		#sleep 2
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_POE_OID.$PORT_MODULE.$PORT_IDENTIFIER i $INTERFACE_ENABLE &> /dev/null
		#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_POE_OID.$PORT_IDENTIFIER i $INTERFACE_ENABLE"${RESET} >> $LOG
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_ADMIN_OID.$PORT_IDENTIFIER i $INTERFACE_ENABLE &> /dev/null
		#echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_ADMIN_OID.$PORT_IDENTIFIER i $INTERFACE_ENABLE"${RESET} >> $LOG
done
}

GET_VARIABLES ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the variables needed for setting the VLANs"${RESET} >> $LOG
OID_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT oid_id FROM $MYSQL_DATABASE.$DEVICE_TABLE WHERE ip='$IP';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}OID ID: $OID_ID"${RESET} >> $LOG
VLAN_OID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT vlan FROM $MYSQL_DATABASE.$OID_TABLE WHERE id='$OID_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}VLAN OID: $VLAN_OID"${RESET} >> $LOG
VLAN_CREATE_OID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT vlan_create FROM $MYSQL_DATABASE.$OID_TABLE WHERE id='$OID_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}VLAN Create OID: $VLAN_CREATE_OID"${RESET} >> $LOG
VLAN_NAME_OID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT vlan_name FROM $MYSQL_DATABASE.$OID_TABLE WHERE id='$OID_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}VLAN Name OID: $VLAN_NAME_OID"${RESET} >> $LOG
INT_POE_OID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT int_poe FROM $MYSQL_DATABASE.$OID_TABLE WHERE id='$OID_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface PoE OID: $INT_POE_OID"${RESET} >> $LOG
INT_ADMIN_OID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT int_admin FROM $MYSQL_DATABASE.$OID_TABLE WHERE id='$OID_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Interface Admin OID: $INT_ADMIN_OID"${RESET} >> $LOG
TAGGED_VLANS=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $SWITCH_CONFIG_TABLE.$VLAN_TAGGED_COLUMN FROM $MYSQL_DATABASE.$SWITCH_CONFIG_TABLE LEFT JOIN $MYSQL_DATABASE.$NETWORK_TABLE ON $SWITCH_CONFIG_TABLE.network_id=$NETWORK_TABLE.id WHERE $SWITCH_CONFIG_TABLE.id='$SWITCH_CONFIG_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Tagged VLANs: $TAGGED_VLANS"${RESET} >> $LOG
UNTAGGED_VLAN=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $SWITCH_CONFIG_TABLE.$VLAN_UNTAGGED_COLUMN FROM $MYSQL_DATABASE.$SWITCH_CONFIG_TABLE WHERE $SWITCH_CONFIG_TABLE.id='$SWITCH_CONFIG_ID';"`
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Untagged VLAN: $UNTAGGED_VLAN"${RESET} >> $LOG
# read -p "Press any key to continue. " DEBUG
}

ADD_AUTHENTICATION ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding authentication"${RESET} >> $LOG
case $LOCATION
	in
		"mcb" | "mcc")MC;;
		"ps") PUBLIC_SAFETY;;
		*) CITY;;
esac
}

MC ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding authentication for the Maverik Center"${RESET} >> $LOG
VLAN="41"
/usr/bin/expect << EOF
set timeout 10
log_user 0
log_file -a $LOG
spawn -noecho ssh -o StrictHostKeyChecking=no $NETWORK_USERNAME@$IP
expect {
        "fingerprint" {
                send "yes\n"
                exp_continue
        }
        "passphrase" {
                send "\n"
                exp_continue
        }
        "s password:" {
                send "$NETWORK_PASSWORD\n"
        }
}
expect {
	"Permission denied" {
		send_user "

Invalid password or username

"
		exit
		exp_continue
	}
	"Press any key to continue" {
		send "n\n"
	}
	"#" {
		send "configure\n"
	}
}
expect "#"
send "configure\n"
expect "(config)#"
send "terminal length 1000\n"
expect "(config)#"
send "show run interface $PORTS\n"
expect "(config)#"
send "show mac-address $PORTS\n"
expect "(config)#"
send "interface $PORTS\n"
expect "(eth-*)#"
send "speed-duplex auto\n"
expect "(eth-*)#"
send "no flow-control\n"
expect "(eth-*)#"
send "poe-lldp-detect disable\n"
expect "(eth-*)#"
send "exit\n"
expect "(config)#"
send "trunk $PORTS Trk8 lacp\n"
expect "(config)#"
send "no trunk $PORTS\n"
expect "(config)#"
send "no port-security $PORTS\n"
expect "(config)#"
send "aaa port-access authenticator $PORTS\n"
expect "(config)#"
send "aaa port-access authenticator $PORTS client-limit 4\n"
expect "(config)#"
send "aaa port-access authenticator $PORTS auth-vid $VLAN\n"
expect "(config)#"
send "aaa port-access authenticator $PORTS unauth-vid 375\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS logoff-period 300\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS addr-limit 2\n"
expect "(config)#"
send "vlan $VLAN\n"
expect "(vlan-$VLAN)#"
send "untagged $PORTS\n"
expect "(vlan-$VLAN)#"
expect "(config)#"
send "exit\n"
expect "#"
send "terminal length 1000\n"
expect "#"
send "show run interface $PORTS\n"
expect "#"
send "show mac-address $PORTS\n"
expect "#"
send "write memory\n"
expect "#"
send "logout\n"
EOF
echo >> $LOG
}

PUBLIC_SAFETY ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding authentication for the Public Safety"${RESET} >> $LOG
VLAN="2010"
/usr/bin/expect << EOF
set timeout 10
log_user 0
log_file -a $LOG
spawn -noecho ssh -o StrictHostKeyChecking=no $NETWORK_USERNAME@$IP
expect {
        "fingerprint" {
                send "yes\n"
                exp_continue
        }
        "passphrase" {
                send "\n"
                exp_continue
        }
        "s password:" {
                send "$NETWORK_PASSWORD\n"
        }
}
expect {
	"Permission denied" {
		send_user "

Invalid password or username

"
		exit
		exp_continue
	}
	"Press any key to continue" {
		send "n\n"
	}
	"#" {
		send "configure\n"
	}
}
expect "#"
send "configure\n"
expect "(config)#"
send "terminal length 1000\n"
expect "(config)#"
send "show run interface $PORTS\n"
expect "(config)#"
send "show mac-address $PORTS\n"
expect "(config)#"
send "interface $PORTS\n"
expect "(eth-*)#"
send "speed-duplex auto\n"
expect "(eth-*)#"
send "no flow-control\n"
expect "(eth-*)#"
send "poe-lldp-detect disable\n"
expect "(eth-*)#"
send "exit\n"
expect "(config)#"
send "trunk $PORTS Trk8 lacp\n"
expect "(config)#"
send "no trunk $PORTS\n"
expect "(config)#"
send "no port-security $PORTS\n"
expect "(config)#"
send "aaa port-access authenticator $PORTS\n"
expect "(config)#"
send "aaa port-access authenticator $PORTS client-limit 4\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS logoff-period 300\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS addr-limit 1\n"
expect "(config)#"
send "vlan $VLAN\n"
expect "(vlan-$VLAN)#"
send "untagged $PORTS\n"
expect "(vlan-$VLAN)#"
send "exit\n"
expect "(config)#"
send "vlan 102\n"
expect "(vlan-102)#"
send "tagged $PORTS\n"
expect "(vlan-102)#"
send "vlan 101\n"
expect "(vlan-101)#"
send "no tagged $PORTS\n"
expect "(vlan-101)#"
send "exit\n"
expect "#"
send "show run interface $PORTS\n"
expect "#"
send "show mac-address $PORTS\n"
expect "#"
send "write memory\n"
expect "#"
send "logout\n"
EOF
echo >> $LOG
}

CITY ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Adding authentication for everything not Maverik Center or Public Safety"${RESET} >> $LOG
VLAN="2010"
/usr/bin/expect << EOF
set timeout 10
log_user 0
log_file -a $LOG
spawn -noecho ssh -o StrictHostKeyChecking=no $NETWORK_USERNAME@$IP
expect {
        "fingerprint" {
                send "yes\n"
                exp_continue
        }
        "passphrase" {
                send "\n"
                exp_continue
        }
        "s password:" {
                send "$NETWORK_PASSWORD\n"
        }
}
expect {
	"Permission denied" {
		send_user "

Invalid password or username

"
		exit
		exp_continue
	}
	"Press any key to continue" {
		send "n\n"
	}
	"#" {
		send "configure\n"
	}
}
expect "#"
send "configure\n"
expect "(config)#"
send "terminal length 1000\n"
expect "(config)#"
send "show run interface $PORTS\n"
expect "(config)#"
send "show mac-address $PORTS\n"
expect "(config)#"
send "interface $PORTS\n"
expect "(eth-*)#"
send "speed-duplex auto\n"
expect "(eth-*)#"
send "no flow-control\n"
expect "(eth-*)#"
send "exit\n"
expect "(config)#"
send "no port-security $PORTS\n"
expect "(config)#"
send "trunk $PORTS Trk8 lacp\n"
expect "(config)#"
send "no trunk $PORTS\n"
expect "(config)#"
send "aaa port-access authenticator $PORTS\n"
expect "(config)#"
send "aaa port-access authenticator $PORTS client-limit 4\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS logoff-period 300\n"
expect "(config)#"
send "aaa port-access mac-based $PORTS addr-limit 1\n"
expect "(config)#"
send "vlan $VLAN\n"
expect "(vlan-$VLAN)#"
send "untagged $PORTS\n"
expect "(vlan-$VLAN)#"
send "exit\n"
expect "(config)#"
send "vlan 101\n"
expect "(vlan-101)#"
send "tagged $PORTS\n"
expect "(vlan-101)#"
send "exit\n"
expect "#"
send "show run interface $PORTS\n"
expect "#"
send "show mac-address $PORTS\n"
expect "#"
send "write memory\n"
expect "#"
send "logout\n"
EOF
echo >> $LOG
}

REBOOT_PHONE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Rebooting the phone"${RESET} >> $LOG
GET_VARIABLES
for PORT in $PORTS_SPACED
	do
		INTERFACE_ID=
		PORT_IDENTIFIER=
		PORT_MODULE=
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Getting the port information from the database for $PORT"${RESET} >> $LOG
		INTERFACE_ID=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT $INTERFACE_TABLE.id FROM $MYSQL_DATABASE.$INTERFACE_TABLE LEFT JOIN $MYSQL_DATABASE.$DEVICE_TABLE ON $INTERFACE_TABLE.device_id=$DEVICE_TABLE.id WHERE $DEVICE_TABLE.ip='$IP' AND $INTERFACE_TABLE.port_name='$PORT';"`
		PORT_IDENTIFIER=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT port FROM $MYSQL_DATABASE.$INTERFACE_TABLE WHERE id='$INTERFACE_ID';"`
		PORT_IDENTIFIER=$(echo "$PORT_IDENTIFIER" | head -n 1)
		PORT_MODULE=`mysql --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD --silent --skip-column-names -e "SELECT module FROM $MYSQL_DATABASE.$INTERFACE_TABLE WHERE id='$INTERFACE_ID';"`
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Power cycling $PORT"${RESET} >> $LOG
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_POE_OID.$PORT_MODULE.$PORT_IDENTIFIER i $INTERFACE_DISABLE &> /dev/null
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_ADMIN_OID.$PORT_IDENTIFIER i $INTERFACE_DISABLE &> /dev/null
		#sleep 2
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_POE_OID.$PORT_MODULE.$PORT_IDENTIFIER i $INTERFACE_ENABLE &> /dev/null
		snmpset -v $SNMP_VERSION -c $SNMPV2_WRITE_USERNAME $IP $INT_ADMIN_OID.$PORT_IDENTIFIER i $INTERFACE_ENABLE &> /dev/null
done
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started."${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution."${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked."${RESET} >> $LOG

GET_INPUT
if ping -c 1 -W 1 -i 0.2 $IP &> /dev/null
	then
		CLEANUP_INPUT
		if [[ "$PERM_OR_TEMP" == "p" ]]
			then
				SPEED_DUPLEX="auto"
			else
				SPEED_DUPLEX="auto-100"
		fi
		REMOVE_AUTHENTICATION
		SET_VLAN
		if [[ "$PERM_OR_TEMP" == "t" ]]
			then
				# echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Waiting 3 minutes"${RESET} >> $LOG
				# echo "Waiting 3 minutes"
				# sleep 60
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}2 minutes remain"${RESET} >> $LOG
				echo "2 minutes remain"
				sleep 60
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}1 minute left"${RESET} >> $LOG
				echo "1 minute left"
				sleep 60
				echo "Setting the ports for authentication"
				ADD_AUTHENTICATION
				REBOOT_PHONE
		fi
	else
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${REDF}$IP is not reachable"${RESET} >> $LOG
		echo "$IP is not reachable"
		EXIT_CODE="75"
		EXIT_FUNCTION
fi

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file."${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished."${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
