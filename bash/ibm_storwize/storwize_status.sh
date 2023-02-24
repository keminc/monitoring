#!/bin/bash
#
# Check StorWize
# 2014
# by KEM
#

 
VERSION='27112014' 
#
###
#IPA="10.1.1.1 10.1.1.2"
IPA="10.1.1.1"
##



for shcmd in "lshealth" ; do

	 #: > ./log/${shcmd}.log_tmp

	 for IP in  $IPA; do

			#########
			RC=`echo $IP| awk -F. '{print $2}' `
			IPA="10.${RC}.237.11" 
			[ $RC = 87 ] && RC=201;
			[ $RC = 57 ] && RC=202;
			[ $RC = 69 ] && RC=203;
			[ $RC = 85 ] && RC=207;
			[ $RC = 51 ] && RC=206;
			 (( ${#RC} == 1 )) && RC="00$RC"
			 (( ${#RC} == 2 )) && RC="0$RC"

			USER="${RC}-monitor"
			PASSWD="password"
			SCP_TIMEOUT=10

			#########


			ping -c 4 -i 0.5 -w 2 $IP | grep 0.recei.*100.*los &> /dev/null
			(( $? == 0 )) && echo -e "AllHosts\tAllSensor\tNoAccess\tCan not connect to $IP\t`date '+%F %T'` " | sed -e "s%^%${RC}_%g" | tee -a ./log/${shcmd}.log_tmp   && continue;


			 
			 usrcmd="ssh ${USER}@${IP}"
				
			expect -c "set timeout $SCP_TIMEOUT ; spawn $usrcmd $shcmd; expect yes {send yes\n}; expect passw {send $PASSWD\n}; expect nevertext"   > ./log/tmp #2>/dev/null

			#if NO connect
			cat ./log/tmp |egrep  "(No.route|not.known|Permission.denied|password.aged)" &>/dev/null && echo -e "AllHosts\tAllSensor\tNoAccess\tCan not connect to $IP\t`date '+%F %T'` "  | tee -a ./log/${shcmd}.log_tmp   && continue;
				
			#if connect
			cat ./log/tmp | egrep -v "(spawn|password|successfully|Sensor)" |   \
			sed -e "s/\r//g" -e "s/$/\t`date '+%F %T'`/g"  |\
			awk   '{
				if  ( (NF > 3) &&  ($2 != "OK") && (($3 == "OK") || ($3 == "ERROR") || ($3 == "WARNING")) )  {cn=$1; pr=1} else pr=0 ; 
				if (pr == 1) {v=""; for(i = 4; i < NF-1; i++) v=v" "$i; print cn"\t"$2"\t"$3"\t"v"\t"$(NF-1)" "$NF; } 
				else { v=""; for(i = 3; i < NF-1; i++) v=v" "$i; print cn"\t"$1"\t"$2"\t"v"\t"$(NF-1)" "$NF; } 
				}' \
				|grep . | sed -e "s%^%${RC}_%g" | tee -a ./log/${shcmd}.log_tmp 


	done
		#rm -f ./log/tmp
		mv -f ./log/${shcmd}.log_tmp  ./log/${shcmd}.log
		cat ./log/${shcmd}.log  >> ./log/${shcmd}.arch
done


