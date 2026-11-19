# 2026-11-19 15:52:06 by RouterOS 7.20.4
# system id = w8mlyFYkonP
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
set [ find default-name=ether3 ] disable-running-check=no
/interface vlan
add interface=ether2 name=vlan-acceso vlan-id=100
/ip pool
add name=pool-abonados ranges=100.64.1.10-100.64.1.100
/ppp profile
add local-address=100.64.1.1 name=plan-512k rate-limit=512k/512k \
    remote-address=pool-abonados
add local-address=100.64.1.1 name=plan-768k rate-limit=768k/768k \
    remote-address=pool-abonados
/interface pppoe-server server
add default-profile=plan-512k disabled=no interface=vlan-acceso service-name=\
    isp
/ip address
add address=10.10.50.1/24 interface=ether3 network=10.10.50.0
/ppp secret
add name=abonado1 password=clave1 profile=plan-512k service=pppoe
add name=abonado2 password=clave2 profile=plan-768k service=pppoe
/system clock
set time-zone-autodetect=no time-zone-name=America/Argentina/Buenos_Aires
/system identity
set name=isp-router
