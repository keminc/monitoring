#!/bin/bash
# by keminc
# 2015
#
	
Check_MQ_Alive() {
	#port_count=`netstat -an | egrep -c "1414.*LISTEN"`;
	#((port_count != 1)) && return 1
	
	ps_count=`ps -ef | grep -c pvo_manager`;
	((ps_count <  5)) && return 2
	
	[ -n "`ps -u mqm -o pid,args | grep defunct | grep -v grep`" ] && return 4
	
	return 0
}

#----------------------------------------------------------------------------------------
Check_MQ_Channels(){
	mqmc='runmqsc pvo_manager';
	mqtmp='mqtmp.log'
	
	#Chanl_name='FCOD_FMS*';
	#cnt="`echo "dis chstatus($Chanl_name) " | $mqmc | grep -c RUNNING`";
	#echo "run_FcodFmsChl=$cnt";
	
	echo "dis chstatus(S_*) " | $mqmc | egrep "(CHANNEL|STATUS)" > $mqtmp ;
	#Anal log
	Chl_type="";
	PChl_type="";
	lbl=1;
	AChl_type="S_FMS....._MRCOD S_MRCOD_FMS..... STATUS";
	while read ln;
	do
		
		#-----------------------------------
		#Пропуск статуса на наёденого в списке канала
		#[ $lbl == 0 ] && continue;		
		#-----------------------------------
		
		Chl_type="";
		lbl=0;
		for i in $AChl_type;
		do
			echo $ln | grep $i &>/dev/null && Chl_type=$i && lbl=1 && break;
		done	
		
		[ "$Chl_type" != "STATUS" ] && [ $lbl == 1 ] && PChl_type=${Chl_type//./} &&  continue;
		[ $lbl == 0 ]  || [ "$PChl_type" == "" ] &&  continue;
		
		#-----------------------------------
		if [ "$Chl_type" == "STATUS" ] &&  [ "`echo $ln | grep -i -c RETRY`" == "1" ]; then
			  eval rn=\$$PChl_type;
			  let "$PChl_type=$rn+1";
			  PChl_type="";
		fi
		
	done < $mqtmp
	rm -f $mqtmp;
	# Вывод счётчика по всем типам каналов
	for i in $AChl_type;
	do
	    [ "$i" == "STATUS" ] && continue;
		vn=${i//./};
		eval rn=\$$vn;
		[[ -z $rn ]] &&	rn=0;
		echo "CnlsRun_"$vn"="$rn;
	done
}

#----------------------------------------------------------------------------------------
#Подсчёт глубины  транспортных очередей
Check_MQ_Trance_Queue(){
	mqmc='runmqsc pvo_manager';
	
	AChl_type="S_INQUEUE  SYSTEM.DEAD.LETTER.QUEUE S_MRCOD.TRANSPORT";
	# приёмник S_MRCOD.RQ
	
		for i in $AChl_type;
		do
			rs=`echo "dis qstatus($i)" | $mqmc  |grep CURDEPTH | awk '{print $1}'`;

			let "x=${#rs}-1";
			rs=`echo $rs | cut -c 10-$x`;
			rs=`echo  ${rs/(/}`;
			vn="${i//./}";
			let "$vn = $rs";			
		done	

	# Вывод счётчика по всем типам каналов
	for i in $AChl_type;
	do
		vn=${i//./};
		eval rn=\$$vn;
		echo "QDepth_"$vn"="$rn;
	done
}




#----------------------------------------------------------------------------------------
#Подсчёт глубины  внутренних очередей
Check_MQ_SPO_Queue(){
	mqmc='runmqsc pvo_manager';
	
	AChl_type="S_AGGREGATOR_SUCCESS_QUEUE S_PROCESSOR_1_QUEUE S_PROCESSOR_3_QUEUE S_PROCESSOR_4_QUEUE S_PROCESSOR_5_QUEUE S_PROCESSOR_6_QUEUE S_PROCESSOR_CHANGE_STATE_QUEUE S_PROCESSOR_CHECK_CHANGE_STATE_QUEUE S_PROCESSOR_DRAFT_QUEUE S_PROCESSOR_NOTIFICATION_QUEUE S_SEPARATOR_QUEUE S_VERIFICATION_QUEUE";
	
	
		for i in $AChl_type;
		do
			rs=`echo "dis qstatus($i)" | $mqmc  |grep CURDEPTH | awk '{print $1}'`;

			let "x=${#rs}-1";
			rs=`echo $rs | cut -c 10-$x`;
			rs=`echo  ${rs/(/}`;
			vn="${i//./}";
			let "$vn = $rs";			
		done	

	# Вывод счётчика по всем типам каналов
	for i in $AChl_type;
	do
		vn=${i//./};
		eval rn=\$$vn;
		echo "QDepth_"$vn"="$rn;
	done
}

#----------------------------------------------------------------------------------------
#В след. версии ввести и передовать на выход только очереди с превышением
#Подсчёт глубины  внутренних очередей
Check_MQ_FMS_Queue(){
	mqmc='runmqsc fcod_manager';
	tf="qtmp.log";

	echo "dis qstatus(FMS*)" | $mqmc  |grep CURDEPTH | awk '{print $1}' > $tf
	echo "Total_FMS_QC=`grep -c . $tf`";
	
	Total_FMS_Q_Depth=0;
	while read ln;
	do
			rs=$ln;
			let "x=${#rs}-1";
			rs=`echo $rs | cut -c 10-$x`;
			let "Total_FMS_Q_Depth = Total_FMS_Q_Depth + $rs";			
	done < $tf
	
	echo "Total_FMS_QD="$Total_FMS_Q_Depth;
	rm -f $tf;

}

#----------------------------------------------------------------------------------------
#Проверка наличия важных каналов
# На выходе разница от всех из списка каналов и запущенных каналов
Check_MQ_Channel_Status_Crit(){
	
	mqmc='runmqsc fcod_manager';
	Chanl_name="S_FMS....._MRCOD S_MRCOD_FMS.....";
	
	tcc=0;  #total chanel count
	trc=0;  #total run chanel chanel
	for i in $Chanl_name;
	do
		let "tcc=tcc+1"
		cnt="`echo "dis chstatus($i) " | $mqmc | grep -c RETR`";
		let "trc=trc+cnt"
	done
	
	#let "rslt=tcc-trc"
	return $trc;
	
}



###############################################################################
######### M A I N ############


cd /var/mqm/Monitoring;
#lock
[ -e lock ] && echo "InWork" && exit 1;
date '+%Y.%m.%d-%H:%M:%S' > lock

logfilet="/var/mqm/Monitoring/log/mq_merc.log.t"
logfile="/var/mqm/Monitoring/log/mq_merc.log"
# Если директории нет, создаем ее
[ ! -d /var/mqm/Monitoring/log ] && mkdir -p /var/mqm/Monitoring/log

# Проверка работоспособности MQ
Check_MQ_Alive;
mq_alive=$?;

#Подсчёт корличества НЕ рабочих КРИТИЧЕСКИХ каналов
Check_MQ_Channel_Status_Crit;
mq_ChanlTrance_status=$?;




{
echo -e "run_date=`date '+%Y.%m.%d-%H:%M:%S'`";
for i in mq_alive mq_ChanlTrance_status; do
	eval result_value=\$$i
	echo "$i=$result_value"
done

#Подсчёт корличества рабочих каналов
Check_MQ_Channels;

#Подсчёт глубины транспортных очередей
Check_MQ_Trance_Queue;

#Подсчёт глубины внутренних очередей
Check_MQ_SPO_Queue;

#Подсчёт шлубины  очередей ФМС
#Check_MQ_FMS_Queue; - in develop

} > "$logfilet";

mv $logfilet $logfile
rm -f lock;

exit $?;