#!/bin/bash
#
# by Fedor + Evgeny
# 2010
#
# Функция для подсчета свободного места на ФС.
# Выводит на печать минимальный свободный объем (в %) на какой-либо смонтированной ФС
Check_Free_Space() {
	result=`df -mP | awk '
	BEGIN { max_mb = 0; }
	{
		if ($0 ~ /^\/dev\/sd/) {
			used_mb=$5;
			gsub(/%/, "", used_mb);
			if (used_mb >= max_mb) max_mb = used_mb;
		}
	}
	END {print max_mb;}'`
	echo "$result"
}

# Проверка работоспособности MySQL
# Принимает: 
# рутовый пароль на базу
# Возвращает :
# 0 - все в порядке
# 1 - процессы не запущены
# 2 - какие-то процессы запущены, но порт не слушается
# 3 - демон запущен и слушает порт, НО соединения не проходят. Это потенциально ОЧЕНЬ БОЛЬШОЙ АХТУНГ, БД может оказаться мертвой.
# 4 - куда-то делся файл ibdata1 (АЦЦКИЙ АХТУНГ!)
# 5 - демон запущен и работает, но как-то сильно расплодился
Check_MySQL_Daemon() {
	ps_count=`pgrep mysqld | wc -l`
	mysql_dir="/home/mysql"
	((ps_count == 0)) && return 1
	[ -z "`netstat -vpna --tcp | grep 3306.*LISTEN.*mysql`" ] && return 2
	echo "select count(*) from form;" | mysql -uroot -p"${1}" pvd 1>/dev/null 2>/dev/null
	[ $? -gt 0 ] && return 3
	[ ! -f "${mysql_dir}/ibdata1" ] && return 4
	((ps_count > 60)) && return 5
	return 0
}

# Функция проверки мегастрашных косяков по логу MySQL
# Возвращает:
# 0 - все ОК
# 1 - Не найден файл лога
# 2 - Аццкий ахтунг, объект нужно срочно останавливать
# ЗАМЕЧАНИЕ. Если в логе объекта попался ахтунг и объект после этого подняли, то лог-файл нужно создать с нуля руками.
# Иначе оно будет снова выдавать ахтунг.
Check_MySQL_Log_Achtungs() {
	mysql_error_file="/home/mysql/`hostname`.err"
	achtung_pattern='ERROR.*(Error writing file|no space left on device)|InnoDB:.*(Your database may be corrupt|which is outside the tablespace bounds|should have been written.*only .*were written|Database page corruption)'
	[ ! -f "$mysql_error_file" ] && return 1
	[ -n "`grep -E "$achtung_pattern" "$mysql_error_file"`" ] && return 2
	return 0
}

# Функция проверяет:
# 1. были ли сделаны бэкапы базы
# 2. не сильно ли отличаются размеры базы и бэкапа
# Принимает на вход:
# 1 - Путь к директории, где лежит файл базы ibdata1
# 2 - Путь к директории бэкапа
# 3 - Пороговый коэффициент (м.б. дробный, с точкой) отношения размера ibdata к размеру бэкапа, больше которого бэкап считать невалидным
# (косяк может быть на "очищенных" базах, где ibdata1 остался большой, а бэкапы стали весить меньше, ЕСЛИ ДЕМОН НЕ ПОДНЯТ)
# 4 - Рутовый пароль на базу
# Результат:
# 0 - все ОК
# 1 - бэкапов нет
# 2 - бэкапы невалидные по размеру (АХТУНГ!!!) - либо на базу стоит другой пароль, либо база не работает, либо бэкап был прерван
# 3 - бэкапы невалидные по дате
# 4 - не найден файл базы данных (вообще НЕРЕАЛЬНЫЙ АХТУНГ)
# 5 - запрос на базу не прошел (СУБД не поднят, или данные повреждены - хрен его знает)
# 6 - бэкапы старше 2 суток, но при этом выполняются cron-скрипты
Check_MySQL_Backups() {		# modified
	mysql_dir="$1"
	backup_dir="$2"
	temp_file="/tmp/.tmp_old_file.`date +%s`"
	[ -z "`ls -1 "$backup_dir" | grep \.bz2$`" ] && return 1
	[ ! -f "${mysql_dir}/ibdata1" ] && return 4

	touch -d "-2 days" "$temp_file"
	valid_backup_date_flag=0
# Определяем размер таблиц MySQL в мегабайтах.
# Запрос на базу может не пройти. В этом случае пытаемся определить размер ibdata1.
# Вообще предполагается, что "живость" СУБД проверяется до этого в Check_MySQL_Daemon
	tables_size="`echo "show table status" | mysql -uroot -p"${4}" pvd 2>/dev/null| awk 'BEGIN {size=0;}
		{if ($0 ~ /InnoDB/) size+=$7; }
		END {printf("%d\n", size/(1024*1024));}'`"
	[ -z "$tables_size" ] && tables_size="`du -smL "${mysql_dir}/ibdata1" | awk '{print $1}'`"

	for i in ${backup_dir}/*bz2; do
		backup_status="`ls -lF "$i" | awk -v ibdata_size="$tables_size" -v thr="$3" '{
			file_size = $5;
			if (file_size == 0) {
				print "FAIL";
				exit;
			}
			if (ibdata1_size / file_size > thr) {
				print "FAIL";
				exit;
			}
			else print "OK";
		}'`"
		if [ "$backup_status" == "FAIL" ]; then
			rm -f "$temp_file"
			return 2
		fi
		[ "$i" -nt "$temp_file" ] && ((valid_backup_date_flag++))	# если файл более новый, чем 2 суток, то +1 счетчику
	done

	rm -f "$temp_file"

	crond_daily_processes="`pgrep -f "/bin/bash /etc/cron.daily/"`"

	if ((valid_backup_date_flag == 0)); then
		if [ -n "$crond_daily_processes" ]; then
			return 6	# бэкапы старше двух суток, НО при этом скрипты сейчас выполняются
		else	return 3	# все бэкапы более старые, чем 2 суток
		fi
	fi
	return 0
}

# Функция для отслеживания того, что ночные скрипты нормально отработали
# Берет на вход файл /root/.f3c_cron.log и смотрит, были ли там ВСЕ положенные записи в пределах суток
# Коды возврата - если все ОК, то 0, если нет - см. код функции
Check_Cron_Jobs_Completed() {
	prev_day="`date -d '-1 day' +'%Y-%m-%d'`"	# строка, вхождение которой надо искать
	this_day="`date +'%Y-%m-%d'`"
	logfile="/root/.f3c_cron.log"

	[ ! -f "$logfile" ] && return 1

	jboss_ok_str="Jboss.*log backup completed OK"
	mq_removal_ok_str="MQ removal.*completed OK"
	scan_removal_ok_str="Scan.*completed OK"
	tc_log_ok_str="TC.*completed OK"
	mysql_backup_ok_str="MySQL.*backups done OK"
	mq_backup_ok_str="MQ.*MQ backups done OK"

	result=0

	[ -z "`grep -E "(${prev_day}|${this_day}).*${jboss_ok_str}" "$logfile"`" ] && ((result += 2))
	[ -z "`grep -E "(${prev_day}|${this_day}).*${mq_removal_ok_str}" "$logfile"`" ] && ((result += 4))
	[ -z "`grep -E "(${prev_day}|${this_day}).*${scan_removal_ok_str}" "$logfile"`" ] && ((result += 8))
	[ -z "`grep -E "(${prev_day}|${this_day}).*${tc_log_ok_str}" "$logfile"`" ] && ((result += 16))
	[ -z "`grep -E "(${prev_day}|${this_day}).*${mysql_backup_ok_str}" "$logfile"`" ] && ((result += 32))
	[ -z "`grep -E "(${prev_day}|${this_day}).*${mq_backup_ok_str}" "$logfile"`" ] && ((result += 64))

	return $result;
}

# Проверка наличия JBoss
# Коды возврата:
# 0 - все хорошо
# 1 - Jboss нет в списке запущенных процессов
# 2 - процессов слишком дохрена или слишком мало (<100 или >200)
# 3 - процессы есть, но порт не прослушивается
# 4 - слушающих процессов > 1
# 5 - запущен и слушает порт, но нет файла лога
# 6 - процессов меньше 100 (нормально для ядер 2.6, ошибка для ядер 2.4)
# 7 - не удалось определить версию ядра ОС
Check_Jboss_Alive() {		# modified
	result=0
	logfile="/jboss/server/default/log/formatingFile.log"
	ps_count="`pgrep -fl java.*jboss 2>/dev/null | wc -l`"
	listen_count=`netstat -vpna --tcp | grep 3528.*LISTEN.*java | wc -l`
	kernel_family="`uname -r | awk -F. '{print $1 "." $2;}'`"	# 2.4 or 2.6
	jboss_proc_max=0
	jboss_proc_min=0

	((ps_count == 0)) && return 1
	if [ "$kernel_family" == "2.4" ]; then
		jboss_proc_max=400
		jboss_proc_min=110
	elif [ "$kernel_family" == "2.6" ]; then
		jboss_proc_max=1
		jboss_proc_min=1
	else	return 7
	fi
	((ps_count > jboss_proc_max)) && return 2
	((listen_count == 0)) && return 3
	((listen_count > 1)) && return 4
	[ ! -f "$logfile" ] && return 5

### Patched 2009-08-10
#	((ps_count < 100)) && return 2
	((ps_count < jboss_proc_min)) && return 6

	return 0
}

# Проверяет наличие MQ в списке процессов, порты и т.п.
# Возвращает:
# 0 - все ОК
# 1 - MQ не слушает порт
# 2 - порт слушается, но MQ нет в списке в процессов
# 3 - процессов слишком дохрена (>200)
# 4 - есть "зомби"
Check_MQ_Alive() {
	ps_count=`pgrep -u mqm -fl mq | wc -l`
	[ -z "`netstat -vpna --tcp | grep :1414.*LISTEN`" ] && return 1
	((ps_count == 0)) && return 2
	((ps_count > 200)) && return 3
	[ -n "`ps -u mqm -o pid,args | grep defunct`" ] && return 4
	return 0
}

# Проверка состояния каналов MQ
# Коды возврата:
# 1 - недоступен pvo_manager
# 2 - нет настроенных каналов
# 3 - нет настроенного канала до ФЦОД
# Если result > 3, то (result - 3) - это количество неподнятых каналов MQ
Check_MQ_Channels() {
	MqCommand="sudo -u mqm runmqsc pvo_manager"
	depcode="`hostname | awk -F. '{print $2}'`"
	echo "end" |  $MqCommand 2>&1 >/dev/null
	[ $? -gt 0 ] && return 1
# Смотрим только каналы-отправители - с именами FMSкод_сегмент.CH
	MqChannels="`echo "dis channel(*)" | $MqCommand | awk -F. '/CHANNEL.*FMS.*_/ {str=$0; gsub(/^.*CHANNEL\(|\).*$/, "", str); print str;}'`"
	[ -z "$MqChannels" ] && return 2
	[ -z "`echo $MqChannels | grep FMS${depcode}_FCOD.CH`" ] && return 3
	for channel in $MqChannels; do
		echo "start channel($channel)" | $MqCommand 1>/dev/null 2>/dev/null
	done
	result=3
	for channel in $MqChannels; do
		[ -z "`echo "dis chstatus($channel)" | $MqCommand 2>/dev/null | grep -i running`" ] && ((result++))
	done
	((result > 0)) && return $result
	return 0
}

# Оценивает место, занимаемое логами
#Jboss
#MQ
#Wine_RCG
# /var/certparser
# /home/support/thinclients/
#а так же базой MySQL
# Аргументы:
# $1 - путь к директории
# $2 - макс. размер в мегабайтах
# Коды возврата:
# 0 - все ОК
# 1 - логов нету вообще
# 2 - команда "du" завершилась неудачей
# 3 - логов слишком дохрена
Check_Directory_Size() {
#	logdir="/jboss/server/default/log"
	logdir="$1"
	max_size="$2"
	[ ! -e "$logdir" ] && return 1
	logsize=`du -sm "$logdir" 2>/dev/null| awk '{print $1}'`
	[ $? -gt 0 ] && return 2
	((logsize >= max_size)) && return 3
	return 0
}


# Проверяет наличие DHCPD в списке процессов, порты и т.п.
# Возвращает:
# 0 - все ОК
# 1 - DHCPd не слушает порт
# 2 - порт слушается, но демона нет в списке процессов
Check_DHCPD_Alive() {
	ps_count=`pgrep -fl dhcpd | wc -l`
	[ -z "`netstat -vpna --udp | grep :67`" ] && return 1
	((ps_count == 0)) && return 2
	return 0
}

# Проверяет наличие NFS в списке процессов
# Возвращает:
# 0 - все ОК
# 1 - NFS не запущен
Check_NFS_Alive() {
	ps_count=`pgrep -fl nfs | wc -l`
	((ps_count == 0)) && return 1
	return 0
}

# Проверяет наличие crond в списке процессов
# Возвращает:
# 0 - все ОК
# 1 - crond не запущен или у /etc/init.d/crond нет прав на выполнение
Check_Crond_Alive() {
	[ -z "`LANG=C /etc/init.d/crond status 2>/dev/null | grep "is running"`" ] && return 1
	return 0
}

# Проверяет наличие certparser в списке процессов, порты и т.п.
# Возвращает:
# 0 - все ОК
# 1 - certparser не слушает порт 12457
# 2 - нет NSD на порту 12458
# 3 - порт слушается, но certparser нет в списке в процессов
# 4 - процессов слишком дохрена (>3)
Check_Cert_Alive() {
	ps_count=`pgrep  -fl certparser | wc -l`
	[ -z "`netstat -vpna --tcp | grep :12457.*LISTEN`" ] && return 1
	[ -z "`netstat -vpna --tcp | grep :12458.*LISTEN`" ] && return 2
	((ps_count == 0)) && return 3
	((ps_count > 20)) && return 4
	return 0
}

# Проверяет наличие wine в списке процессов, порты NSD и т.п.
# Возвращает:
# 0 - все ОК
# 1 - NSD не слушает порт 12456
# 2 - порт слушается, но wine нет в списке в процессов
# 3 - процессов wine слишком дохрена (>5)
Check_Wine_Alive() {
	ps_count=`pgrep  -fl wine | wc -l`
	[ -z "`netstat -vpna --tcp | grep :12456.*LISTEN`" ] && return 1
	((ps_count == 0)) && return 2
	((ps_count > 20)) && return 3
	return 0
}

# Проверяет наличие cupsd в списке процессов
# Возвращает:
# 0 - все ОК
# 1 - cupsd не запущен или у /etc/init.d/cups нет прав на выполнение
Check_Cups_Alive() {
	[ -z "`LANG=C /etc/init.d/cups status 2>/dev/null | grep "is running"`" ] && return 1
	return 0
}

# Проверяет, что в дневное время не запущены скрипты cron.daily
# Дневное время - от 9 до 20 часов.
# Возвращает:
# 0 - все ОК - скрипты не выполняются (в рабочее время)
# 1 - скрипты работают (АХТУНГ!) - красная тревога
# 2 - скрипты сейчас НЕ работают, но при этом остался lock-файл - они почему-то не отработали до конца в предыдущий раз
# 3 - все ОК - скрипты в данный момент выполняются (нерабочее время)
Check_Cron_Daily_Execution() {		# modified
	hours=`date %H`
	result=0
	this_date="`date +'%Y-%m-%d_%H:%M:%S'`"
	logfile="/root/.f3c_cron.log.day"
	lockfile="/var/lock/subsys/f3c-cron"
	crond_daily_processes="`pgrep -f "/bin/bash /etc/cron.daily/"`"
	if [ -e "$logfile" ]; then	# Если этот файл уже существует, значит, когда-то скрипты отработали неправильно
		result=1		# Чтобы в будущем не выдавалась эта же ошибка...
	fi				# ... необходимо после устранения причины удалить этот файл
	if ((hours>8 && hours <21)); then
		if [ -n "$crond_daily_processes" ]; then	# Если скрипты сейчас ТОЧНО выполняются
			result=1
			echo "$this_date : Detected running crond processes" >> "$logfile"
			pids="`echo "$crond_daily_processes" | awk '{str=$0; gsub(/$/,",",str); printf ("%s",str);}' | sed -e 's/,$//'`"
			ps -p $pids -o pid,uid,start,args -ww >> "$logfile"
			echo >> "$logfile"
		else	# Даже если скрипты сейчас не выполняются, проверить, не остался ли lock-файл
			if [ -f "$lockfile" ]; then	# если файл остался, значит, когда-то они до конца не выполнились
				result=2
			fi
		fi
	else	# Если время нерабочее - проверить, выполняются ли скрипты
		if [ -n "$crond_daily_processes" ]; then
			result=3	# Это допустимый код возврата, все в порядке - скрипты выполняются в нерабочее время
		else
			if [ -f "$lockfile" ]; then	# если файл остался, значит, когда-то они до конца не выполнились
				result=2
			fi
		fi
	fi
	return $result
}


Check_MySQL_Daemon pvofms
check_mysql_daemon=$?
Check_Jboss_Alive
check_jboss_alive=$?
Check_MQ_Alive
check_mq_alive=$?
Check_DHCPD_Alive
check_dhcpd_alive=$?
Check_NFS_Alive
check_nfs_alive=$?
Check_Crond_Alive
check_crond_alive=$?
Check_Wine_Alive
check_wine_alive=$?
Check_Cups_Alive
check_cups_alive=$?


all_services_result=0
echo -e "\nrun_date=`date +'%Y.%m.%d-%H:%M:%S'`"
for i in check_mysql_daemon check_jboss_alive check_mq_alive check_dhcpd_alive check_nfs_alive check_crond_alive check_wine_alive check_cups_alive; do
	eval result_value=\$$i
	((all_services_result += result_value))
	#echo "$i=$result_value"
	if ((result_value == 0)); then
		echo "$i: OK"
	else	echo "$i: FAIL; ERROR CODE=$result_value"
	fi
done
echo

if ((all_services_result == 0)); then
	echo "All services are working properly"
	exit 0
else
	echo "Soft wasn't started properly"
	exit 1
fi
