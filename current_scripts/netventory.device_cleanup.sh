#!/bin/bash
#Filename: netventory.device_cleanup.sh
#Description: 
# .bashrc alias=alias git_commit="/bin/bash ~/scripts/templates/$SCRIPT_NAME.sh"
#Requirements:
# Credentials file located at $HOME/scripts/.credentials
# Packages:
# mariadb-server/mysqld
# net-snmp
# net-snmp-utils
# procmail (lockfile command)

# read -p "Press any key to continue. " DEBUG #DEUBG

SCRIPT_NAME="netventory.device_cleanup"
SCRIPT_CAT="netventory"

mkdir -p $HOME/logs/$SCRIPT_CAT &> /dev/null
mkdir -p $HOME/scripts/tmp/$SCRIPT_NAME &> /dev/null
TODAY=`date +%Y-%m-%d`
NOW=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$HOME/logs/$SCRIPT_CAT/$SCRIPT_NAME.log"
CREDENTIALS="$HOME/scripts/.credentials"
DATABASE_USERNAME=$(cat $CREDENTIALS | egrep ^mysql_username: | sed 's/mysql_username://g')
DATABASE_PASSWORD=$(cat $CREDENTIALS | egrep ^mysql_password: | sed 's/mysql_password://g')
LOCAL_DATABASE="netventory"
DEVICE_TABLE="device"
ENDPOINT_TABLE="endpoint"
DEVICE_TABLES="$DEVICE_TABLE $ENDPOINT_TABLE"
DHCP_TABLE="dhcp"
ARP_TABLE="arp"
OUI_TABLE="oui"
OID_TABLE="oid"
WORKING_DIR="$HOME/scripts/tmp/$SCRIPT_NAME"
SCRIPT_DIR="$HOME/scripts/$SCRIPT_CAT"
LOCK_FILE="$WORKING_DIR/$SCRIPT_NAME.lock"
FILE="$WORKING_DIR/file"
COUNTS_PER_RUN="100"

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

CHECK_MAC ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the mac addresses for ${CURRENT_TABLE}s without SNMP"${RESET} >> $LOG
DEVICE_IDS=
DEVICE_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$CURRENT_TABLE WHERE (mac IS NULL OR mac='') AND (ping > (NOW() - INTERVAL 7 DAY)) ORDER BY updated DESC;"`
UPDATE_MAC
DEVICE_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$CURRENT_TABLE WHERE (ping > (NOW() - INTERVAL 7 DAY)) ORDER BY updated DESC LIMIT $COUNTS_PER_RUN;"`
UPDATE_MAC
}

UPDATE_MAC ()
{
for DEVICE_ID in $DEVICE_IDS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Working with $CURRENT_TABLE id $DEVICE_ID"${RESET} >> $LOG
		IP=
		IP=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$CURRENT_TABLE WHERE id='$DEVICE_ID';"`
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating $CURRENT_TABLE id $DEVICE_ID with a mac from the $ARP_TABLE table"${RESET} >> $LOG
		mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set mac=(SELECT mac FROM $ARP_TABLE WHERE ip='$IP' AND mac!='ff:ff:ff:ff:ff:ff' AND mac!='00:00:00:00:00:00' ORDER BY updated DESC LIMIT 1) WHERE id='$DEVICE_ID';
EOF
done
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set mac=NULL WHERE mac='00:00:00:00:00:00' OR mac='ff:ff:ff:ff:ff:ff';
EOF
}

UPDATE_OUI ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the oui for ${CURRENT_TABLE}s that haven't been updated yet"${RESET} >> $LOG
DEVICE_IDS=
DEVICE_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$CURRENT_TABLE WHERE (oui IS NULL AND mac IS NOT NULL) AND ((ping_check > (NOW() - INTERVAL 7 DAY) AND updated < (NOW() - INTERVAL 1 DAY)) OR added > (NOW() - INTERVAL 1 DAY)) ORDER BY updated LIMIT $COUNTS_PER_RUN;"`
if [[ -z "$DEVICE_IDS" ]]
	then
		DEVICE_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$CURRENT_TABLE WHERE (oui IS NULL AND mac IS NOT NULL) ORDER BY updated LIMIT $COUNTS_PER_RUN;"`
fi
if [[ -z "$DEVICE_IDS" ]]
	then
		DEVICE_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$CURRENT_TABLE WHERE mac IS NOT NULL ORDER BY updated LIMIT $COUNTS_PER_RUN;"`
fi
for DEVICE_ID in $DEVICE_IDS
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Working with $CURRENT_TABLE id $DEVICE_ID"${RESET} >> $LOG
		MAC=
		MAC=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT mac FROM $LOCAL_DATABASE.$CURRENT_TABLE WHERE id='$DEVICE_ID';"`
		GET_MAC_OUI
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating $CURRENT_TABLE id $DEVICE_ID with an oui from the $OUI_TABLE table"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set oui="$OUI" WHERE id='$DEVICE_ID';
EOF
done
}

GET_MAC_OUI ()
{
OUI=
MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{1}')
OUI=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI' ORDER BY updated DESC LIMIT 1;"`
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}')
		OUI=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI' ORDER BY updated DESC LIMIT 1;"`
fi
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{1}')
		OUI=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI' ORDER BY updated DESC LIMIT 1;"`
fi
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}')
		OUI=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI' ORDER BY updated DESC LIMIT 1;"`
fi
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{1}')
		OUI=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI' ORDER BY updated DESC LIMIT 1;"`
fi
if [[ -z "$OUI" ]]
	then
		MAC_OUI=$(echo "$MAC" | egrep --color=never -o '^[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}\:[0-9A-Fa-f]{2}')
		OUI=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT vendor FROM $LOCAL_DATABASE.$OUI_TABLE WHERE mac='$MAC_OUI' ORDER BY updated DESC LIMIT 1;"`
fi
}

UPDATE_OIDS ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating devices OIDs"${RESET} >> $LOG
OID_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$OID_TABLE;"`
for OID_ID in $OID_IDS
	do
		if [[ "$OID_ID" == "1" ]]
			then
				continue
		fi
		OID_ARRAY=(`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT device_manufacturer,device_type FROM $LOCAL_DATABASE.$OID_TABLE WHERE id='$OID_ID';"`)
		DEVICE_MANUFACTURER=${OID_ARRAY[0]}
		DEVICE_TYPE=${OID_ARRAY[1]}
		DEVICE_MANUFACTURER=$(echo "$DEVICE_MANUFACTURER" | sed 's/_/ /g')
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE table with a manufacturer of $DEVICE_MANUFACTURER and a type of $DEVICE_TYPE with an OID ID of $OID_ID"${RESET} >> $LOG
		mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set oid_id='$OID_ID' WHERE manufacturer LIKE'$DEVICE_MANUFACTURER' AND type='$DEVICE_TYPE';
EOF
done
}

DEVICE_CLEANUP ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Removing unnecessary IPs from the $CURRENT_TABLE table"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
DELETE FROM $CURRENT_TABLE WHERE ip LIKE '169.%.%.%';
EOF

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE table sysname"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set sysname=NULL WHERE sysname LIKE '%no such object%';
UPDATE $CURRENT_TABLE set sysname=NULL WHERE sysname='';
EOF

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE table hostname"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set hostname=NULL WHERE hostname LIKE '%no such object%';
EOF

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE table model"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set model=NULL WHERE model LIKE '%end of mib%';
UPDATE $CURRENT_TABLE set model=NULL WHERE model='';
UPDATE $CURRENT_TABLE set model=NULL WHERE model='no';
EOF

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE table description"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set description=NULL WHERE description LIKE '%no such object%';
EOF

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE manufacturer"${RESET} >> $LOG
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set manufacturer='Panasonic' WHERE oui LIKE '%Matsushita Electric%';
UPDATE $CURRENT_TABLE set manufacturer='HP' WHERE manufacturer LIKE '%hewlett%' OR manufacturer LIKE '%hpn supply%' OR manufacturer LIKE '%aruba%' OR manufacturer LIKE '%hewlett%' OR manufacturer LIKE '%hpn%' OR manufacturer LIKE '%aruba%' OR oui LIKE '%aruba%' OR oui LIKE '%hp%' OR oui LIKE '%hpn supply%' OR oui LIKE '%hewlett%' OR manufacturer='hp';
UPDATE $CURRENT_TABLE set manufacturer='Ubiquiti' WHERE oui LIKE '%ubiquiti%';
UPDATE $CURRENT_TABLE set manufacturer='Pulse Secure' WHERE description LIKE '%pulse secure%';
UPDATE $CURRENT_TABLE set manufacturer='Dell' WHERE oui LIKE '%vnx5200%';
UPDATE $CURRENT_TABLE set manufacturer='Mitel' WHERE oui LIKE '%shoretel%' OR model LIKE '%shoregear%';
UPDATE $CURRENT_TABLE set manufacturer='Cisco' WHERE oui LIKE 'cisco%';
UPDATE $CURRENT_TABLE set manufacturer='Konica Minolta' WHERE oui LIKE '%konica minolta%';
UPDATE $CURRENT_TABLE set manufacturer='Fortinet' WHERE description LIKE '%fortinet%';
UPDATE $CURRENT_TABLE set manufacturer='HP' WHERE oui LIKE '%procurve%';
UPDATE $CURRENT_TABLE set manufacturer='Motorola' WHERE manufacturer LIKE '%cmm4%';
UPDATE $CURRENT_TABLE set manufacturer=NULL WHERE manufacturer='';
UPDATE $CURRENT_TABLE set manufacturer=NULL WHERE manufacturer='no';
UPDATE $CURRENT_TABLE set manufacturer='CommScope' WHERE oui LIKE '%Arris Group, Inc%';
UPDATE $CURRENT_TABLE set manufacturer='Ruckus' WHERE oui LIKE '%ruckus wireless%' OR description LIKE '%ruckus wireless%';
EOF

#Type by Subnet
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
#UPDATE $CURRENT_TABLE set category='camera' WHERE ip LIKE '10.%.5.%' AND category IS NULL;
UPDATE $CURRENT_TABLE set category='storage' WHERE ip LIKE '10.3.6.%' AND category IS NULL;
UPDATE $CURRENT_TABLE set category='storage' WHERE ip LIKE '10.%.3.%' AND category IS NULL;
EOF

#Type by DNS Name
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set category='av' WHERE dns_name LIKE '%\.av%\.%';
UPDATE $CURRENT_TABLE set category='camera' WHERE dns_name LIKE '%\.camera\.%';
UPDATE $CURRENT_TABLE set category='power' WHERE dns_name LIKE '%\.ups\.%';
UPDATE $CURRENT_TABLE set category='printer' WHERE dns_name LIKE '%\.printer\.%';
UPDATE $CURRENT_TABLE set category='wireless',type='wap' WHERE dns_name LIKE '%\.ap\.%';
UPDATE $CURRENT_TABLE set category='wireless',type='ptp' WHERE dns_name LIKE '%\.ptp\.%';
EOF

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Updating the $CURRENT_TABLE types"${RESET} >> $LOG
# Generic updates
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set category='unknown' WHERE category IS NULL OR category='';
UPDATE $CURRENT_TABLE set category='client',type='mac' WHERE oui LIKE '%apple%';
UPDATE $CURRENT_TABLE set category='pc' WHERE manufacturer='hp' AND type IS NULL AND (model IS NULL OR model='hp');
UPDATE $CURRENT_TABLE set category='mobile',type='ios' WHERE oui LIKE '%apple%' AND (ip LIKE '192.168.%' OR ip LIKE '172.16.%');
UPDATE $CURRENT_TABLE set category='network' WHERE oui LIKE '%cisco%system%' OR oui LIKE '%cisco%meraki%';
UPDATE $CURRENT_TABLE set category='voice',type='ip phone' WHERE manufacturer='mitel' OR manufacturer LIKE '%shoretel%' OR oui LIKE '%mitel%' OR oui LIKE '%shoretel%';
UPDATE $CURRENT_TABLE set category='server' WHERE description LIKE '%hardware: intel64%' OR description LIKE '%hardware: x86%';
UPDATE $CURRENT_TABLE set category='server',type='linux' WHERE description LIKE '%pulse secure%';
UPDATE $CURRENT_TABLE set category='server' WHERE description LIKE '%red hat%';
UPDATE $CURRENT_TABLE set category='server' WHERE description LIKE '%server%';
UPDATE $CURRENT_TABLE set category='server',type='linux' WHERE description LIKE 'linux %';
UPDATE $CURRENT_TABLE set category='server' WHERE oui LIKE '%super micro%';
EOF

# Specific updates
mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE $CURRENT_TABLE set category='av' WHERE description LIKE '%extron%' OR oui LIKE '%extron%';
UPDATE $CURRENT_TABLE set category='av' WHERE oui LIKE '%D&M Holdings Inc%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%audinate%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%audiotonix%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%Behringer Spezielle%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%LEA Professional%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%biamp%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%crestron%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%qsc llc%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%shure%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%slim device%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%sonos%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%soundcraft%';
UPDATE $CURRENT_TABLE set category='av',type='audio' WHERE oui LIKE '%sur-gard%';
UPDATE $CURRENT_TABLE set category='av',type='display' WHERE oui LIKE '%awind%';
UPDATE $CURRENT_TABLE set category='av',type='network' WHERE oui LIKE '%Pakedge Device AND Software Inc%';
UPDATE $CURRENT_TABLE set category='av',type='streaming' WHERE oui LIKE '%amazon%';
UPDATE $CURRENT_TABLE set category='av',type='streaming' WHERE oui LIKE '%roku%';
UPDATE $CURRENT_TABLE set category='av',type='streaming' WHERE oui LIKE '%salcomp%' OR hostname LIKE '%chromecast%';
UPDATE $CURRENT_TABLE set category='av',type='tv' WHERE oui LIKE '%Sony Visual Products Inc%';
UPDATE $CURRENT_TABLE set category='av',type='tv' WHERE oui LIKE '%vizio%';
UPDATE $CURRENT_TABLE set category='av',type='video' WHERE oui LIKE '%brightsign%';
UPDATE $CURRENT_TABLE set category='av',type='video' WHERE oui LIKE '%RGB Spectrum%';
UPDATE $CURRENT_TABLE set category='av' WHERE oui LIKE '%Paradigm Electronics Inc%';
UPDATE $CURRENT_TABLE set category='camera' WHERE oui LIKE '%avigilon%';
UPDATE $CURRENT_TABLE set category='camera',manufacturer='bosch' WHERE oui LIKE '%vcs video%';
UPDATE $CURRENT_TABLE set category='camera' WHERE oui LIKE '%tvt co%';
UPDATE $CURRENT_TABLE set category='camera' WHERE description LIKE '%camera%';
UPDATE $CURRENT_TABLE set category='camera' WHERE oui LIKE '%axis communication%';
UPDATE $CURRENT_TABLE set category='camera',type='dock' WHERE oui LIKE '%taser international%';
UPDATE $CURRENT_TABLE set category='camera' WHERE oui LIKE '%hanwha%';
UPDATE $CURRENT_TABLE set category='camera',manufacturer='hikvision' WHERE oui LIKE '%hikvision%';
UPDATE $CURRENT_TABLE set category='camera' WHERE oui LIKE '%lilin%' OR oui LIKE '%Merit Li-Lin%';
UPDATE $CURRENT_TABLE set category='camera' WHERE oui LIKE '%vivotek%';
UPDATE $CURRENT_TABLE set category='camera' WHERE oui LIKE '%mobotix%';
UPDATE $CURRENT_TABLE set category='camera',type='dock' WHERE hostname REGEXP '^X[0-9A-Za-z]+$' AND oui LIKE '%private%';
UPDATE $CURRENT_TABLE set category='camera',type='dvr' WHERE oui LIKE '%acti corporation%';
UPDATE $CURRENT_TABLE set category='game console',type='nintendo' WHERE oui LIKE '%nintendo%';
UPDATE $CURRENT_TABLE set category='game console',type='xbox' WHERE oui LIKE '%microsoft%' AND hostname LIKE '%xbox%';
UPDATE $CURRENT_TABLE set category='hvac' WHERE oui LIKE '%Advantech Co%';
UPDATE $CURRENT_TABLE set category='hvac' WHERE oui LIKE '%johnson controls%';
UPDATE $CURRENT_TABLE set category='hvac' WHERE oui LIKE '%tridium%';
UPDATE $CURRENT_TABLE set category='hvac',type='thermostat' WHERE oui LIKE '%ecobee%';
UPDATE $CURRENT_TABLE set category='hvac',type='thermostat' WHERE oui LIKE '%nest labs%';
UPDATE $CURRENT_TABLE set category='hvac' WHERE oui LIKE '%daikin industries%';
UPDATE $CURRENT_TABLE set category='hypervisor' WHERE description LIKE '%esxi%';
UPDATE $CURRENT_TABLE set category='hypervisor',type='vmware' WHERE description LIKE '%esxi%';
UPDATE $CURRENT_TABLE set category='iot' WHERE oui LIKE '%Alarm.com%';
UPDATE $CURRENT_TABLE set category='iot',type='Door Bell' WHERE oui LIKE '%Ring Llc%';
UPDATE $CURRENT_TABLE set category='iot',type='garage door' WHERE oui LIKE '%The Chamberlain Group%';
UPDATE $CURRENT_TABLE set category='iot',type='Intercom' WHERE oui LIKE '%Aiphone Co%';
UPDATE $CURRENT_TABLE set category='iot',type='pos' WHERE oui LIKE '%equinox payment%';
UPDATE $CURRENT_TABLE set category='iot',type='pos' WHERE oui LIKE '%ingenico%';
UPDATE $CURRENT_TABLE set category='iot',type='pos' WHERE oui LIKE '%quest retail%';
UPDATE $CURRENT_TABLE set category='iot',type='fuel pump' WHERE oui LIKE '%syn-tech%';
UPDATE $CURRENT_TABLE set category='iot',type='raspberry pi' WHERE oui LIKE '%raspberry pi%' OR description LIKE '% pi%';
UPDATE $CURRENT_TABLE set category='iot',type='Solar Monitor' WHERE oui LIKE '%SolarEdge Tech%';
UPDATE $CURRENT_TABLE set category='iot',type='usb nic' WHERE oui LIKE '%cable matters%';
UPDATE $CURRENT_TABLE set category='iot',type='usb wireless nic' WHERE oui LIKE '%edimax%';
UPDATE $CURRENT_TABLE set category='iot',type='headset' WHERE oui LIKE '%coachcomm%';
UPDATE $CURRENT_TABLE set category='iot',type='navigation' WHERE oui LIKE '%essys%';
UPDATE $CURRENT_TABLE set category='iot',type='fitness' WHERE oui LIKE '%fitbit%';
UPDATE $CURRENT_TABLE set category='iot',type='doorbell' WHERE oui LIKE '%skybell, inc%';
UPDATE $CURRENT_TABLE set category='iot',type='irrigation' WHERE oui LIKE '%orbit irrigation%';
UPDATE $CURRENT_TABLE set category='mobile',type='android' WHERE oui LIKE 'lg elec%mobile%' AND (ip LIKE '192.168.%' OR ip LIKE '172.16.%');
UPDATE $CURRENT_TABLE set category='mobile',type='android' WHERE oui LIKE 'oneplus%' AND (ip LIKE '192.168.%' OR ip LIKE '172.16.%');
UPDATE $CURRENT_TABLE set category='mobile',type='android' WHERE oui LIKE '%motorola%wuhan%mobility%';
UPDATE $CURRENT_TABLE set category='mobile',type='android',manufacturer='Samsung' WHERE oui LIKE '%murata manufacturing%';
UPDATE $CURRENT_TABLE set category='mobile',type='android',manufacturer='nokia' WHERE oui LIKE '%hmd global%' OR oui LIKE '%nokia%';
UPDATE $CURRENT_TABLE set category='mobile',type='android',manufacturer='htc' WHERE oui LIKE '%htc%';
UPDATE $CURRENT_TABLE set category='mobile',type='android',manufacturer='huawei' WHERE oui LIKE '%huawei%';
UPDATE $CURRENT_TABLE set category='mobile',manufacturer='kyocera' WHERE oui LIKE '%kyocera%';
UPDATE $CURRENT_TABLE set category='mobile' WHERE oui LIKE '%Tct mobile Ltd%';
UPDATE $CURRENT_TABLE set category='network' WHERE (type!='switch' OR type IS NULL OR type='unknown') AND manufacturer='ubiquiti';
UPDATE $CURRENT_TABLE set category='network',type='firewall' WHERE description LIKE '%fortigate%' OR description LIKE '%fortiwifi%' OR model LIKE '%fgt_%';
UPDATE $CURRENT_TABLE set category='network',type='firewall' WHERE model LIKE '%edgeos%' OR description LIKE '%edgeos%';
UPDATE $CURRENT_TABLE set category='network',type='oob' WHERE oui LIKE '%idrac%' OR hostname LIKE '%idrac%' OR sysname LIKE '%idrac%';
UPDATE $CURRENT_TABLE set category='network',type='oob' WHERE oui LIKE '%lantronix%';
UPDATE $CURRENT_TABLE set category='network',type='adapter' WHERE oui LIKE '%veracity uk ltd%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE description LIKE '%aruba%vsf%';
UPDATE $CURRENT_TABLE set category='network' WHERE oui LIKE '%zyxel%';
UPDATE $CURRENT_TABLE set category='network',manufacturer='netgear' WHERE oui LIKE '%netgear%';
UPDATE $CURRENT_TABLE set category='network',manufacturer='smc' WHERE oui LIKE '%smc network%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE description LIKE '%cisco ios%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE description LIKE '%extremexos%' OR oui LIKE '%extreme networks%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE description LIKE '%switch%' AND (description NOT LIKE '%cdu%' AND description NOT LIKE '%pdu%');
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE description LIKE '%vc flex%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE manufacturer LIKE '%trendnet%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE model LIKE '%stack%' OR description LIKE '%brocade%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE model LIKE '%switch%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE oui LIKE '%etherwan%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE oui LIKE '%luxul%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE oui LIKE '%procurve%';
UPDATE $CURRENT_TABLE set category='network',type='switch' WHERE oui LIKE '%tp-link%';
UPDATE $CURRENT_TABLE set category='network' WHERE oui LIKE '%Adtran, Inc%';
UPDATE $CURRENT_TABLE set category='pc',type=NULL WHERE (manufacturer LIKE '%microsoft%' OR oui like '%microsoft%') AND (hostname NOT LIKE '%xbox%' OR hostname IS NULL);
UPDATE $CURRENT_TABLE set category='pc',type=NULL WHERE hostname REGEXP '^[A-Za-z]{1,4}\-W[0-9]{1,5}$' OR hostname REGEXP '^W[0-9]{1,5}$' OR dns_name REGEXP '^[A-Za-z]{1,4}\-W[0-9]{1,5}\..+$';
UPDATE $CURRENT_TABLE set category='pc',type=NULL WHERE manufacturer LIKE '%hp%' AND oui LIKE '%hewlett%' AND category='unknown';
UPDATE $CURRENT_TABLE set category='pc',type=NULL WHERE oui LIKE '%motorola%lenovo%';
UPDATE $CURRENT_TABLE set category='pc',type=NULL WHERE oui LIKE '%shuttle%';
UPDATE $CURRENT_TABLE set category='pc',type=NULL WHERE hostname LIKE '__%-w_____' OR hostname LIKE '__w_-%' OR hostname LIKE 'w0____' OR hostname LIKE '__ws%';
UPDATE $CURRENT_TABLE LEFT JOIN device_services ON $CURRENT_TABLE.id=device_services.device_id SET $CURRENT_TABLE.category='pc' WHERE device_services.port_135='open';
UPDATE $CURRENT_TABLE set category='power' WHERE oui LIKE '%panamax llc%';
UPDATE $CURRENT_TABLE set category='power',type='pdu' WHERE description LIKE '%cdu%' OR description LIKE '%pdu%';
UPDATE $CURRENT_TABLE set category='power',type='ups' WHERE description LIKE '%apc%snmp%';
UPDATE $CURRENT_TABLE set category='power',type='ups' WHERE model LIKE '%ups%';
UPDATE $CURRENT_TABLE set category='power' WHERE oui LIKE '%liteon%';
UPDATE $CURRENT_TABLE set category='printer' WHERE description LIKE '%epson%';
UPDATE $CURRENT_TABLE set category='printer' WHERE description LIKE '%HP ETHERNET MULTI-ENVIRONMENT%';
UPDATE $CURRENT_TABLE set category='printer' WHERE description LIKE '%jetdirect%';
UPDATE $CURRENT_TABLE set category='printer' WHERE hostname REGEXP '^NPI[A-Fa-f0-9]+$';
UPDATE $CURRENT_TABLE set category='printer' WHERE manufacturer LIKE '%canon%';
UPDATE $CURRENT_TABLE set category='printer' WHERE manufacturer LIKE '%konica minolta%';
UPDATE $CURRENT_TABLE set category='printer' WHERE manufacturer LIKE '%ricoh%';
UPDATE $CURRENT_TABLE set category='printer' WHERE manufacturer LIKE '%sharp%';
UPDATE $CURRENT_TABLE set category='printer' WHERE manufacturer LIKE '%xerox%' OR oui LIKE '%xerox%';
UPDATE $CURRENT_TABLE set category='printer' WHERE oui LIKE '%brother industries%';
UPDATE $CURRENT_TABLE set category='printer' WHERE oui LIKE '%sharp corp%';
UPDATE $CURRENT_TABLE set category='security' WHERE oui LIKE '%Pronet Gmbh%';
UPDATE $CURRENT_TABLE set category='security' WHERE oui LIKE '%suprema%';
UPDATE $CURRENT_TABLE set category='security' WHERE oui LIKE '%napco%';
UPDATE $CURRENT_TABLE set category='server' WHERE manufacturer='juniper' AND oui LIKE '%armorlink%' AND description LIKE '%mag%';
UPDATE $CURRENT_TABLE set category='server' WHERE oui LIKE '%vmware%' AND description IS NULL;
UPDATE $CURRENT_TABLE set category='server',type='authentication' WHERE description LIKE '%clearpass%';
UPDATE $CURRENT_TABLE set category='server',type='controller' WHERE oui LIKE '%trapeze%' AND description LIKE '%mx-%';
UPDATE $CURRENT_TABLE set category='server',type='ilo' WHERE description LIKE '%integrated lights%' OR hostname LIKE 'ilo%' OR sysname LIKE 'ilo%';
UPDATE $CURRENT_TABLE set category='server',type='wap' WHERE oui LIKE '%trapeze%' AND description NOT LIKE '%mx-%';
UPDATE $CURRENT_TABLE set category='smart device',type='google home' WHERE oui LIKE '%google, inc%' OR hostname LIKE '%google%home%';
UPDATE $CURRENT_TABLE set category='smart device',type='home automation' WHERE hostname LIKE '%control4%' OR oui LIKE '%control4%';
UPDATE $CURRENT_TABLE set category='smart device',type='outlet' WHERE hostname LIKE '%Etekcity%';
UPDATE $CURRENT_TABLE set category='stb',type='directv' WHERE oui LIKE '%directv%';
UPDATE $CURRENT_TABLE set category='stb',type='dish network' WHERE oui LIKE '%dish technologies%' OR oui LIKE '%dish tech corp%';
UPDATE $CURRENT_TABLE set category='storage',type='nas' WHERE oui LIKE '%data robotics%';
UPDATE $CURRENT_TABLE set category='storage',type='nas' WHERE oui LIKE '%netapp%';
UPDATE $CURRENT_TABLE set category='storage',type='san' WHERE description LIKE '%data domain%';
UPDATE $CURRENT_TABLE set category='storage',type='san' WHERE description LIKE '%san%' AND description LIKE '%msa%';
UPDATE $CURRENT_TABLE set category='storage',type='san' WHERE description LIKE '%vnx5200%';
UPDATE $CURRENT_TABLE set category='storage',type='san' WHERE oui LIKE '%equallogic%';
UPDATE $CURRENT_TABLE set category='storage',type='san' WHERE oui LIKE '%datrium%';
UPDATE $CURRENT_TABLE set category='storage',type='san' WHERE oui LIKE 'seagate%';
UPDATE $CURRENT_TABLE set category='storage',type='san',manufacturer='Dell/EMC' WHERE oui LIKE '%Clariion%';
UPDATE $CURRENT_TABLE set category='voice',type='ip phone' WHERE dns_name REGEXP '^p[A-Fa-f0-9]{13}\..+';
UPDATE $CURRENT_TABLE set category='voice',type='ip phone' WHERE oui LIKE '%avaya%' OR oui LIKE '%polycom%' OR hostname LIKE 'polycom_%';
UPDATE $CURRENT_TABLE set category='voice',type='analog adapter' WHERE oui LIKE '%Obihai%';
UPDATE $CURRENT_TABLE set category='voice',type='switch' WHERE category='voice' AND type='IP Phone' AND description LIKE '%shoregear%';
UPDATE $CURRENT_TABLE set category='wireless' WHERE oui LIKE '%ruckus wireless%' OR description LIKE '%ruckus wireless%';
UPDATE $CURRENT_TABLE set category='wireless',type='ptp' WHERE description LIKE '%canopy%';
UPDATE $CURRENT_TABLE set category='wireless',type='ptp' WHERE description LIKE '%ptp%';
UPDATE $CURRENT_TABLE set category='wireless',type='ptp' WHERE oui LIKE '%cambium networks%';
UPDATE $CURRENT_TABLE set category='wireless',type='ptp' WHERE oui LIKE '%radwin%';
UPDATE $CURRENT_TABLE set category='wireless',type='wap' WHERE manufacturer LIKE '%ubiquit%' AND model LIKE '%uap%';
EOF
}


DEVICE2ENDPOINT ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Moving endpoints to the endpoint table"${RESET} >> $LOG
DEVICE_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE category!='network' AND category!='wireless' AND category!='unknown';"`
for DEVICE_ID in $DEVICE_IDS
	do
		DEVICE_IP=
		DEVICE_IP=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE id='$DEVICE_ID';"`
		ENDPOINT_ID=
		ENDPOINT_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE id='$DEVICE_ID';"`
		if [[ -z "$ENDPOINT_ID" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Moving $DEVICE_IP with Device ID $DEVICE_ID to the endpoint table"${RESET} >> $LOG
				mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $ENDPOINT_TABLE(id,ip,hostname,sysname,dns_name,mac,description,manufacturer,oui,syslocation,model,firmware_p,firmware_s,SERIAL,rom,category,type,oid_id,snmp_id,location_id,snmp_enabled,snmp_check,ping_check,updated,added) VALUES('$DEVICE_ID','$DEVICE_IP',(SELECT hostname FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT sysname FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT dns_name FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT mac FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT description FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT manufacturer FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT oui FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT syslocation FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT model FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT firmware_p FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT firmware_s FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT SERIAL FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT rom FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT category FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT type FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT oid_id FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT snmp_id FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT location_id FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT snmp_enabled FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),(SELECT snmp_check FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'),NOW(),NOW(),(SELECT added FROM $DEVICE_TABLE WHERE id='$DEVICE_ID'));
DELETE FROM $DEVICE_TABLE WHERE id='$DEVICE_ID';
EOF
			else
				mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
UPDATE endpoint SET ip='$DEVICE_IP',updated=NOW() WHERE id='$ENDPOINT_ID';
DELETE FROM $DEVICE_TABLE WHERE id='$DEVICE_ID';
EOF
		fi
done
}

ENDPOINT2DEVICE ()
{
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Moving devices to the device table"${RESET} >> $LOG
ENDPOINT_IDS=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE category='network' OR category='wireless';"`
for ENDPOINT_ID in $ENDPOINT_IDS
	do
		ENDPOINT_IP=
		ENDPOINT_IP=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT ip FROM $LOCAL_DATABASE.$ENDPOINT_TABLE WHERE id='$ENDPOINT_ID';"`
		DEVICE_ID=
		DEVICE_ID=`mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD --silent --skip-column-names -e "SELECT id FROM $LOCAL_DATABASE.$DEVICE_TABLE WHERE ip='$ENDPOINT_IP';"`
		if [[ -z "$DEVICE_ID" ]]
			then
				echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Moving $ENDPOINT_IP with ENDPOINT ID $ENDPOINT_ID to the DEVICE table"${RESET} >> $LOG
				mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
INSERT INTO $DEVICE_TABLE(id,ip,hostname,sysname,dns_name,mac,description,manufacturer,oui,syslocation,model,firmware_p,firmware_s,SERIAL,rom,category,type,oid_id,snmp_id,location_id,snmp_enabled,snmp_check,ping_check,updated,added) VALUES((SELECT id FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT ip FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT hostname FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT sysname FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT dns_name FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT mac FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT description FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT manufacturer FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT oui FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT syslocation FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT model FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT firmware_p FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT firmware_s FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT SERIAL FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT rom FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT category FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT type FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT oid_id FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT snmp_id FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT location_id FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT snmp_enabled FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),(SELECT snmp_check FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'),NOW(),NOW(),(SELECT added FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID'));
DELETE FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID';
EOF
			else
				mysql --user=$DATABASE_USERNAME --password=$DATABASE_PASSWORD $LOCAL_DATABASE << EOF
DELETE FROM $ENDPOINT_TABLE WHERE id='$ENDPOINT_ID';
EOF
		fi
done
}

trap CTRL_C SIGINT

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh was started by $USER"${RESET} >> $LOG
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Attempting to lock the file for execution"${RESET} >> $LOG
lockfile -r 0 $LOCK_FILE &> /dev/null || SCRIPT_RUNNING
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}File has been locked"${RESET} >> $LOG

for CURRENT_TABLE in $DEVICE_TABLES
	do
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: =========" >> $LOG
		echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Working on the $CURRENT_TABLE table"${RESET} >> $LOG
		CHECK_MAC
		UPDATE_OUI
		DEVICE_CLEANUP
		UPDATE_OIDS
done
DEVICE2ENDPOINT
ENDPOINT2DEVICE

echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${CYANF}Unlocking the file"${RESET} >> $LOG
rm -f $LOCK_FILE &> /dev/null
echo -e "`date +%b\ %d\ %Y\ %H:%M:%S`: ${GREENF}$SCRIPT_NAME.sh finished"${RESET} >> $LOG
echo "===============================================================================================" >> $LOG



exit
