#!/bin/bash
pw=$(pass show work/rdp-sig)
xfreerdp3 /ipv4 /v:vmk009.federtechnik.ch /u:sig /p:"$pw" /sec:tls:on /cert:ignore /kbd:layout:0x00000807 +dynamic-resolution +clipboard /drive:homedir,/home/sig


