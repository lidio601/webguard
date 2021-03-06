#!/bin/bash

# Ricava data attuale e il percorso per un file temporaneo
NOW=$(date +%s)

# Parametri di configurazione di default
BANTIME=900

LOGFILE='/var/log/auth.log'
TEMP=$(tempfile)
TEMP2=$(tempfile)
TEMP3=$(tempfile)
MAILLOG=$(tempfile)
STATUSFILE='/root/webguard/status_ssh_guard'
BANTABLEFILE='/root/webguard/ban.tbl'
RECIDIVI='/root/webguard/recidivi.log'

if [ -f $MAILLOG ]; then
	rm $MAILLOG
fi

# Carica lo stato dal file
if [ -f "$STATUSFILE" ]; then
	. "$STATUSFILE"
	#echo "Carico le linee precedenti: $LINEPOS"
else
	LINEPOS=0
fi

# Sanity check
STATUSCHANGED=0
if [ "$LINEPOS" == "" ]; then
	#LINEPOS=$(wc -l "$LOGFILE" | cut -f1 -d" ")
	STATUSCHANGED=1
fi

# Controlla la tabella dei ban
#lo fa il webguard.sh che rimuovera' anche i miei ban

# Conta le righe del file di log
LN=$(wc -l "$LOGFILE" | cut -f1 -d" ")
#echo "LINEE DEL FILE DI LOG: $LN"

# Il file è stato resettato
if [ $LN -lt $LINEPOS ]; then
	#echo "$LN < $LINEPOS: azzero LINEPOS"
	LINEPOS=0
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

                        # Se la data attuale � maggiore del campo EXPIRY il ban � scaduto
                        if [ "$NOW" -gt "$EXPIRY" ]; then
                                "$UNBANCOMMAND" "$IP" >>$MAILLOG
                                        WRITETOFILE=1
                                else
                                        NEWTABLE="$NEWTABLE$i\n"
                                fi
        done

        # I record non rimossi vengono riscritti nella tabella (se � stata modificata)
        if [ "$WRITETOFILE" == "1" ]; then
                echo -e "$NEWTABLE" > "$BANTABLEFILE"
        fi
fi

# Calcola la differenza
let "LINES = LN - LINEPOS"
#echo "prendo le ultime $LINES righe"
#echo "Controllo le ultime $LINES linee"

# Restituisce le nuove linee
if [ $LINES -gt 0 ]; then
	#echo "nuove linee"
	NEWRECORDS=""
	
	tail -n $LINES $LOGFILE | grep -v "CRON" | grep -v "su" | grep -v "smbd"| grep -v "Accepted" | grep -v "session opened for user fabio" >$TEMP
	cat $TEMP | grep "Invalid user" | cut -d"]" -f2- | cut -c3- | uniq | cut -d" " -f5 | uniq | sort >$TEMP2
	cat $TEMP | grep "not allowed because" | cut -d"]" -f2- | cut -c3- | uniq | cut -d" " -f4 | uniq | sort >>$TEMP2
	cat $TEMP2 | sort | uniq >$TEMP3
	#echo "trovati `cat $TEMP3 | wc -l` indirizzi da bannare"
	
	for ip in `cat $TEMP3`; do
		echo "$ip" >>$RECIDIVI
		
		if [ `cat $BANTABLEFILE | grep -c $ip` -gt 0 ]; then
			echo "salto $ip: gia bannato" >>$MAILLOG
		else
			
			#Calcolo il numero di ban eseguiti per questo host
			let quanti=`grep -c 193.238.28.222 $BANTABLEFILE`+1
			let "tempo = BANTIME*quanti"
		
			# Calcola la scadenza sommando la data attuale al bantime		
			let "EXPIRY = NOW + tempo"
	
			# Inserisce il nuovo record nella tabella
			NEWRECORDS="$NEWRECORDS$EXPIRY $ip\n"
	
			#echo "Banno l'host: $ip"
			TXT=`tail -n "$LINES" "$LOGFILE" | grep $ip`
			PATTERN='------------------------------------\n'
			echo -e "\nfiltered IP $ip for\n$PATTERN\n$TXT\n$PATTERN Banno: $ip sulla porta 22 e 80\nQuante volte ha attaccato: $quanti\n Expire date: $EXPIRY\n">>$MAILLOG
		
			#"$BANCOMMAND" "$i" >>$MAILLOG
			/sbin/iptables -A INPUT -p tcp -s "$ip" --dport 80 -j REJECT >>$MAILLOG
			/sbin/iptables -A INPUT -p tcp -s "$ip" --dport 22 -j REJECT >>$MAILLOG
		fi
	done
	
	LINEPOS=$LN
	STATUSCHANGED=1

fi

# Salva lo stato se modificato
if [ "$STATUSCHANGED" != "0" ]; then
  echo "LINEPOS=$LN" > "$STATUSFILE"
  #echo "Salvo LINEPOS = $LN"
fi

# Salva la tabella se modificata
if [ "$NEWRECORDS" != "" ]; then
  echo -e "$NEWRECORDS" >> "$BANTABLEFILE"
fi

if [ -f $MAILLOG ]; then
  clinee=`wc -l $MAILLOG | cut -d' ' -f1`
  if [ "$clinee" -gt "0" ]; then
    if [ "$MAILLOG" == "" ]; then
      echo "" >/dev/null
    else
      cat $MAILLOG | /usr/bin/mail -s "SSHGuard: filter IP" root
    fi
  fi
  #rm $MAILLOG
fi

rm $TEMP $TEMP2 $TEMP3
