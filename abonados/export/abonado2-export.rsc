# 2026-11-19 15:45:52 by RouterOS 7.20.4
# system id = cz1t2/n++UB
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
/interface vlan
add interface=ether2 name=vlan-acceso vlan-id=100
/interface pppoe-client
add add-default-route=yes disabled=no interface=vlan-acceso name=wan-pppoe \
    password=clave2 user=abonado2
/ip dhcp-client
add interface=ether1
/system clock
set time-zone-autodetect=no time-zone-name=America/Argentina/Buenos_Aires
/system identity
set name=abonado2
