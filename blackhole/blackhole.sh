#!/usr/local/bin/bash
#
# Author:: Sebian
# Date:: 2014-02-13 04:01:56 +0100
# Contact:: Gitoyen -- http://gitoyen.net/Contact

if [[ "x${DEBUG}" == "x1" ]]; then
  set -e
  set -x
fi

hostname=$(hostname -s)
case $hostname in
  "vodka")
    BGPNEIGHBOR=""
    DAEMON="bird"
    ;;
  "whiskey")
    BGPNEIGHBOR=""
    DAEMON="bird"
    ;;
  "x-ray")
    BGPNEIGHBOR=""
    DAEMON="bird"
    ;;
  "yankee")
    BGPNEIGHBOR="80.231.79.69"
    DAEMON="quagga"
    ;;
  "zoulou")
    BGPNEIGHBOR="212.85.148.109"
    DAEMON="quagga"
    ;;
  "grimoire")
    BGPNEIGHBOR="1.1.1.1"
    DAEMON="bird"
    ;;
  *)
    echo "Unknow router"
    exit 1
esac

show_usage() {
  cat <<EOF
Usage: $0 [OPTION]
Blackhole script

    -a [add|del|list]     Action à effectuer.
    -i [a.b.c.d/n]        Petite victime.
    -h (help)             Affiche cette aide.
EOF
exit 1
}

while getopts "a:i:h" opt; do
  case $opt in
    a)
      case $OPTARG in
        "add")
          action="add"
          ;;
        "del")
          action="del"
          ;;
        "list")
          action="list"
          ;;
        *)
          echo "Not a action (add/del/list)"
          ;;
      esac
      ;;
    i)
      case $OPTARG in
        *.*.*.*/* )
          net=$OPTARG
          ;;
        * )
          echo "Not a valid ip (a.b.c.d/n), ($OPTARG)"
          exit 1
      esac
      ;;
    h)
      show_usage
      exit 2
      ;;
    *)
      echo "Bad params"
      exit 1
      ;;
  esac
done

if [[ "$action" == "add" ]]; then
  mask=`echo $net | cut -d / -f 2`
  if [ $mask -le 24 -o $mask -gt 32 ]; then
    echo To blackhole a whole /$mask is not reasonable
    exit 1
  fi
  echo "Adding $net to blackhole:"
  if [ "${DAEMON}" = "quagga" ]; then
    # then to the router blackhole :
    vtysh -d bgpd -c "conf t" -c "router bgp 20766" -c "network $net route-map blackhole"
    # then clear the out announce to our transit :
    vtysh -d bgpd -c "clear ip bgp $BGPNEIGHBOR soft out"
    #vtysh -d zebra -c "conf t" -c "ip route $net 127.0.0.1 blackhole"
  fi
  route add $net 127.0.0.1 -blackhole
elif [[ "$action" == "del" ]]; then
  echo "Removing $net from blackhole:"
  if [ "${DAEMON}" = "quagga" ]; then
    # then to the router blackhole :
    vtysh -d bgpd -c "conf t" -c "router bgp 20766" -c "no network $net"
    # then clear the out announce to our transit :
    vtysh -d bgpd -c "clear ip bgp $BGPNEIGHBOR soft out"
    #vtysh -d zebra -c "conf t" -c "no ip route $net 127.0.0.1 blackhole"
  fi
  route del $net 127.0.0.1 -blackhole
elif [[ "$action" == "list" ]]; then
  if [ "${DAEMON}" = "quagga" ]; then
    echo Those networks are black-holed by BGPD:
    vtysh -d bgpd -c 'show run' | grep 'network .* route-map blackhole' | awk '{print $2}'
    echo Those networks are black-holed by ZEBRA via kernel:
    vtysh -c 'sh ip route kernel' | grep 'lo0, bh' | awk '{print $2}'
    vtysh -c 'sh ip route static' | grep 'lo0, bh' | awk '{print $2}'
  else
    echo Those networks are black-holed by kernel:
    netstat -nr|grep UGSB
  fi
else
  echo "Action  problem"
  exit 1
fi
