#!/bin/bash
#
# ZE   temperatute  from HMC
# Kotov E. - 2014
#


cd /opt/IBM/ITM/lx8266/um/scripts/ZSystem/

IP='10.1.1.1'
IPPORT=$IP":6794"
ID='HMC1_25'

hmcVersion=`curl -k -s  https://$IPPORT/api/version |  sed -e "s/,/\n/g"  -e "s/\"//g"  -e "s/:/=/g"| grep hmc-version`
echo "date=`date '+%F %T'`" 	 > log/main.log
echo "HMC_IP="$IP >> log/main.log
echo $hmcVersion  >> log/main.log

SessionID=`curl -k -s -H "Accept: application/json" -H "Content-type: application/json" -X POST -d ' {"password": "qwerty","userid": "usr"}'  https://$IPPORT/api/sessions \
			|  sed -e "s/,/\n/g"  -e "s/\"//g"| grep session |awk -F ':' '{print $2}'`
#echo $SessionID

curl -k -s -H "x-api-session:$SessionID" -X GET  https://$IPPORT/api/cpcs/b4eae1cf-39fa-3ee7-ba25-dd9feebfd73e/energy-management-data  | tee -a log/energy-management-data_archiv.log  > log/energy-management-data.log  
curl -k -s -H "x-api-session:$SessionID" -X DELETE https://$IPPORT/api/session/this-session

# Make cool log

echo " " >> log/energy-management-data_archiv.log

cat log/energy-management-data.log |sed -e "s/,/\n/g"  -e "s/\"//g" -e "s/}//g" -e "s/\.[0-9]*//g"   -e "s/:/=/g"| grep temperature >> log/main.log 
#sed -i log/main.log 
#Add more data to log
sed -e "s/^exhaust/zbc-exhaust/g"  -e "s/^ambient/zbc-ambient/g" -e "s%$%=$ID%g" -i log/main.log 
cat log/main.log | tee -a  log/main_arch.log


exit 0
