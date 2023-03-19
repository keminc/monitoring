#!/bin/bash
# Get certificate end date from http(s)
# v1
# 27.01.2022
# Kotov E.
#
# Run: run.sh file_with_hosts
#       and you must have trusted certificates file - "trustCA.pem" 
#
# Host file structure (hosts.txt):
#      #HOSTNAME       NAME    CERT_PREFIX
#      # Commect text
#
# Host file example (hosts.txt):
#	mysite.com	 mysite_home certificate_name
#	mysite2.com  mysite_admin 
#   

[[ ! -f "$1" ]] && hostfile='hosts.txt' || hostfile="$1"

grep ... $hostfile | egrep -v '^#' | while read ln; do

    host="`echo $ln| awk '{print $1}'`"
    desc="`echo $ln| awk '{print $2}'`"
    cert="`echo $ln| awk '{print $3}'`"
    [[ ${#cert} -gt 2 ]] && certs=" --cert ./ssl/${cert}.pem --key ./ssl/${cert}.key --cacert ./ssl/trustCA.pem " || certs=''
    #echo "Cert:  ${certs}"

    EndDate="`curl -k -v ${certs} https://$host 2>&1 | grep expire.date | sed -e "s/.*date: //" |tail -1`"
    let DaysToExp=($(date +%s -d "$EndDate") - $(date +%s))/86400
    echo -e $desc"\t"$EndDate"\t"$DaysToExp
    result="host="$desc";DaysToExp="$DaysToExp
    echo $result |tee -a ${host}.out.log

done

