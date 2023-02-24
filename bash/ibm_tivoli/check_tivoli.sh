#!/bin/bash


ip=$1
reg=$2
srv=$3
passwd=$4

(( ${#ip} < 6 )) && exit 123
(( ${#passwd} < 2 )) && exit 124


fslog="./log/tivoli_${reg}_${srv}_`date '+%d.%m.%Y'`"


ssh $ip " echo itmRunCnt=\$(/opt/IBM/ITM/bin/cinfo -R |grep -c \.running) ;\
       echo itmInstallCnt=\$(/opt/IBM/ITM/bin/cinfo -t | egrep  \"^[a-z]{2}[[:space:]].*l(i|x)[0-9]\" |  sort -k 1,2 -u | grep -c .) ;\
	   echo ncoRunCnt=\$(/opt/IBM/tivoli/netcool/omnibus/bin/nco_pa_status -password $passwd |grep -c RUNNING)  " > $fslog 2>/dev/null
           
       cat  $fslog
                   
       rm -f $fslog
                       



