pw=$(zenity --password --title="RDP Password") && \
[ -n "$pw" ] && \
xfreerdp3 /ipv4 /v:pc02 /u:user /p:"$pw" /sec:tls:on /cert:ignore +dynamic-resolution +clipboard /drive:homedir,/home/name
