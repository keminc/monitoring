logDir="/opt/IBM/ITM/scripts/logs/"
logFile="MQM.log"
process=0
port=0
log=0

[ ! -f $logDir$logFile ] && `:> $logDir$logFile`
logSize="`ls -lF "$logDir$logFile" | awk '{print $5}'`"
if (($logSize > 10000000)); then
    bzip2 -9 $logDir$logFile
    mv $logDir$logFile".bz2" $logDir"bak/"$logFile".bz2"
fi

ps_count=`pgrep -u mqm -fl mq | wc -l`
((ps_count < 1)) && process=1
((ps_count > 200)) && process=2

[ -z "`netstat -vpna --tcp | grep :1414.*LISTEN`" ] && port=1

log_file="/var/mqm/errors/`ls -lt /var/mqm/errors/ | grep .LOG | head -1 | awk '{print $9}'`"
log=`grep -c AMQ $log_file`

su - mqm ./mqm_mon.sh

echo $process $port $log
echo "`date +'%Y.%m.%d-%H:%M:%S'`" $process $port $log >> $logDir$logFile
cat /var/mqm/Monitoring/log/mq_merc.log >> $logDir$logFile