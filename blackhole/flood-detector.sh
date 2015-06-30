#!/usr/local/bin/bash

# Author:: Benjamin Sonntag (<benjamin _at_ sonntag _dot_ fr>)
# Author:: Sebastien Badia (<seb _at_ sebian _dot_ fr>)
# Author:: Philippe Le Brouster (<plb _at_ nebkha _dot_ net>)

# detect flood by first counting the number of packets per second on an interface,
# if the PPS is too high, search for a victim and add it to blackhole

if [[ "x${DEBUG}" == "x1" ]]; then
  set -e
  set -x
fi

hostname=$(hostname -s)
case $hostname in
  "zoulou")
    IFACE="em1.109"
    ;;
  "yankee")
    IFACE="em0.179"
    ;;
  "x-ray")
    IFACE="em0.3012"
    ;;
  "grimoire")
    IFACE="eth0"
    ;;
  "whiskey")
    IFACE="lagg0.3012"
    ;;
  *)
    echo "Unknown router"
    exit 1
esac

# Above this rate, trigger the flood removal process
MAXPPS=50000
# Max PPS for the victim itself :
MAXPPSVICTIM=5000
# The mail recipient to notify :
MAILRECIPIENT="root@gitoyen.net"

show_usage(){
  cat <<EOHELP
Usage: $0 [OPTION]
Flood detector and blackhole

  -e      Nmap expression.
  -i      Interface to catch (default $IFACE)
  -n      PPs that trigger tcpdump (default $MAXPPS)
  -t      PPs that trigger the blackhole (default $MAXPPSVICTIM)
  -m      Recipient (default $MAILRECIPIENT)
  -h      Show this help.

./flood-detector.sh -e 'dst net 80.67.160.0/24 or dst net 80.67.174.0/24'

EOHELP
}

while getopts "i:e:n:t:m:h" opt; do
  case $opt in
    e)
      # Filter the tcpdump on that expression then
      FILTER="$OPTARG"
      ;;
    n)
      MAXPPS="$OPTARG"
      ;;
    t)
      MAXPPSVICTIM="$OPTARG"
      ;;
    i)
      IFACE="$OPTARG"
      ;;
    m)
      MAILRECIPIENT="$OPTARG"
      ;;
    *)
      show_usage
      exit 1
      ;;
  esac
done

if [ -z "$FILTER" ]; then
  show_usage
  exit 1
fi

echo "Auto Blackholing"
echo "IFACE        $IFACE"
echo "FILTER       $FILTER"
echo "MAXPPS       $MAXPPS"
echo "MAXPPSVICTIM $MAXPPSVICTIM"

while true
do
  INPPS=`netstat -w 1 -I "$IFACE" -q 3 | tail -1 | awk '{print $1}' `
  if [ "$INPPS" -gt "$MAXPPS" ]
    then
      echo "`date` $INPPS > $MAXPPS, searching for a victim"
      # Ok, we are flooded, turn the blackhole ON for the victim
      #tcpdump -i "$IFACE" -p -n -w /tmp/flood.pcap "$FILTER" &
      tcpdump -i "$IFACE" -p -n -w - "$FILTER" | gzip - > /tmp/flood.pcap.gz  &
      ME="$!"
      sleep 2
      kill -TERM "$ME" >/dev/null 2>/dev/null
      sleep 1
      kill -KILL "$ME" >/dev/null 2>/dev/null
      # Now find the victim and add it to the blackhole :
      #BLACK="`tcpdump -r /tmp/flood.pcap -n 2>/dev/null |awk '{print $5}' |awk -F "." '{print $1 "." $2 "." $3 "." $4}' |sort | uniq -c | sort -gr | head -1`"
      BLACK="` zcat /tmp/flood.pcap.gz 2>/dev/null | tcpdump -r - -n 2>/dev/null |awk '{print $5}' |awk -F "." '{print $1 "." $2 "." $3 "." $4}' |sort | uniq -c | sort -gr | head -1`"
      BLACKCOUNT="`echo $BLACK | awk '{print $1}'`"
      BLACKME="`echo $BLACK | awk '{print $2}'|cut -d':' -f1`"
      if [ -n "$BLACKME" ] && [ -n "$BLACKCOUNT" ] && [ "$BLACKCOUNT" -gt "$MAXPPSVICTIM" ];
      then
        echo "`date` found $BLACKME that received $BLACKCOUNT pps, blackholing..."
        # we got him, add him to the blackhole :
        bash /tmp/blackhole.sh -a add -i ${BLACKME}/32
        # And we tell the admin ;)
	( echo "Automatic blackhole triggered at `date`" ; echo "PPS was $INPPS, and $BLACKCOUNT was sent to $BLACKME" ) | mail -s "Automatic Blackhole triggered on `hostname` for $BLACKME" $MAILRECIPIENT
      else
        echo "`date` Nobody found for the filtered expression, will try again later"
      fi
  fi
sleep 5
done
