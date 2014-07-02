#!/bin/bash

# Ricava data attuale e il percorso per un file temporaneo
NOW=$(date +%s)
TMP=$(tempfile)

# Parametri di configurazione di default
BANTIME=900
#secondi
LOGPATH="/var/log/apache2"

LOGFILE="fabio.access.log"
if [ $# -eq 1 ]; then
	if [ -f "$LOGPATH/$1" ]; then
		LOGFILE=$1
	fi
fi
PATTERNFILE="./pattern.txt"
NONPATTERNFILE="./NONpattern.txt"
BANTABLEFILE="./ban.tbl"
STATUSFILE="./status_$LOGFILE.txt"
BANCOMMAND="./ban.sh"
UNBANCOMMAND="./unban.sh"
MAILLOG="./mailtemp_$LOGFILE.txt"
LOGFILE="$LOGPATH/$LOGFILE"

# Carica la configurazione da file, se esiste
if [ -f "/etc/webguard.conf" ]; then
	. /etc/webguard.conf
fi

# Cambia directory di lavoro
cd "$(dirname $0)"

# Carica lo stato dal file
if [ -f "$STATUSFILE" ]; then
	. "$STATUSFILE"
fi

# Sanity check
STATUSCHANGED=0
if [ "$LINEPOS" == "" ]; then
	#LINEPOS=$(wc -l "$LOGFILE" | cut -f1 -d" ")
	STATUSCHANGED=1
fi

# Controlla la tabella dei ban
if [ -f "$BANTABLEFILE" ]; then
	NEWTABLE=""
	WRITETOFILE=0
	IFS=$'\n'
	
	# Controlla ciascun record della tabella
	for i in $(sort -n -k2 -r "$BANTABLEFILE" | uniq -f1); do
			EXPIRY=${i:0:10}
			IP=${i:11:16}
			
			# Se la data attuale è maggiore del campo EXPIRY il ban è scaduto
			if [ "$NOW" -gt "$EXPIRY" ]; then
				"$UNBANCOMMAND" "$IP" >>$MAILLOG
					WRITETOFILE=1
				else
					NEWTABLE="$NEWTABLE$i\n"
				fi
	done
	
	# I record non rimossi vengono riscritti nella tabella (se è stata modificata)
	if [ "$WRITETOFILE" == "1" ]; then
		echo -e "$NEWTABLE" > "$BANTABLEFILE"
	fi
fi

# Conta le righe del file di log
LN=$(wc -l "$LOGFILE" | cut -f1 -d" ")

# Il file è stato resettato
if [ $LINEPOS -gt $LN ]; then
	LINEPOS=0
fi

# Calcola la differenza
let "LINES = LN - LINEPOS"

# Restituisce le nuove linee
if [ $LINES -gt 0 ]; then
	#echo "nuove linee"
	NEWRECORDS=""

	# Cerca tra le nuove righe del log quelle che matchano uno o più pattern
	# ed estrae una copia unica dell'indirizzo ip che le ha generate 
	for i in $(tail -n "$LINES" "$LOGFILE" | grep -f "$PATTERNFILE" | grep -v -f "$NONPATTERNFILE" | cut -f1 -d" " | sort | uniq); do
		validip=`cat /var/log/auth.log | grep sshd | grep Accepted | grep publickey | awk '{ print 1}' | sort | uniq`
		if [ "`echo $validip | grep -n $i`" == 1 ]; then
		  echo "ip $i nella lista dei known hosts ">>$MAILLOG
		else
			# Calcola la scadenza sommando la data attuale al bantime		
			let "EXPIRY = NOW + BANTIME"
		
			# Inserisce il nuovo record nella tabella
			NEWRECORDS="$NEWRECORDS$EXPIRY $i\n"
		
			# Banna l'host
			TXT=`tail -n "$LINES" "$LOGFILE" | grep -f "$PATTERNFILE"`
			echo "Site: $LOGFILE\n<br />WebGuard: filtered IP $i for $TXT\n<br />Banno: $BANCOMMAND $i\n<br />Expire date: $EXPIRY">>$MAILLOG
			"$BANCOMMAND" "$i" >>$MAILLOG
		fi
	done
	
	LINEPOS=$LN
	STATUSCHANGED=1
fi

# Salva lo stato se modificato
if [ "$STATUSCHANGED" != "0" ]; then
	echo "LINEPOS=$LN" > "$STATUSFILE"
fi

# Salva la tabella se modificata
if [ "$NEWRECORDS" != "" ]; then
	echo -e "$NEWRECORDS" >> "$BANTABLEFILE"
fi

if [ -f $MAILLOG ]; then
#  clinee=`wc -l $MAILLOG | cut -d' ' -f1`
#  if [ "$clinee" -gt "0" ]; then
#    if [ "$MAILLOG" == "" ]; then
#      echo "" >/dev/null
#    else
#      cat $MAILLOG | /usr/bin/mail -s "WebGuard: filter IP" fabio.cigliano@gmail.com
#    fi
#  fi
  rm $MAILLOG
fi
