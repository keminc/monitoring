#!/bin/bash
#
ip=$1
reg=$2
srv=$3

(( ${#ip} < 6 )) && exit 123
(( ${#srv} < 2 )) && exit 124


fslog="log/fsck/fsck_${reg}_${srv}_`date '+%d.%m.%Y'`"

ssh $ip "e2fsck -vfn \$(mount | grep mapper.*root |awk '{print \$1}') ; touch ~/123 2>/dev/null && echo fsRW || echo fsRO"  &> $fslog


echo "fsBadBlock="`grep bad.blocks $fslog| awk '{print $1}'`;
echo "fsFixCount="`grep -c Fix $fslog`;
echo "fsReadWrite="`grep fsR  $fslog | sed -e "s/fsR/R/g"`;





