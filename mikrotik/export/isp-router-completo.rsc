# 2026-11-24 17:17:52 by RouterOS 7.20.4
# system id = RuUMn0zX10P
#
/interface ethernet
set [ find default-name=ether1 ] comment="gestion: red solo-anfitrion, sin IP (WinBox por MAC)" disable-running-check=no
set [ find default-name=ether2 ] comment="acceso: red interna isp-acceso, por aca llegan los abonados" disable-running-check=no
set [ find default-name=ether3 ] comment="servicios: red interna isp-servicios, por aca se habla con el RADIUS" disable-running-check=no
/interface vlan
add comment="VLAN 100: abonados" interface=ether2 name=vlan-acceso vlan-id=100
/interface list
add comment="por donde se administra el router" name=gestion
/ip pool
add comment="IPs para los abonados" name=pool-abonados ranges=100.64.1.10-100.64.1.100
/port
set 0 name=serial0
/ppp profile
add comment="sin velocidad: la dicta el RADIUS" local-address=100.64.1.1 name=pppoe-base remote-address=pool-abonados
add comment="plan local: 512k de subida y de bajada" local-address=100.64.1.1 name=plan-512k rate-limit=512k/512k remote-address=pool-abonados
add comment="plan local: 768k de subida y de bajada" local-address=100.64.1.1 name=plan-768k rate-limit=768k/768k remote-address=pool-abonados
/snmp community
set [ find default=yes ] disabled=yes
add addresses=10.10.50.20/32 comment="solo lectura y solo desde isp-monitoreo" name=lab-monitoreo
/system logging action
add name=recolector remote=10.10.50.20 remote-log-format=syslog remote-port=1514 src-address=10.10.50.1 target=remote
/user group
add comment="lo minimo para autenticar un bandwidth-test" name=solo-pruebas policy=test,winbox,!local,!telnet,!ssh,!ftp,!reboot,!read,!write,!policy,!password,!web,!sniff,!sensitive,!api,!romon,!rest-api
/ip neighbor discovery-settings
set discover-interface-list=gestion
/interface list member
add comment="solo la boca de gestion" interface=ether1 list=gestion
/interface pppoe-server server
add comment="servidor PPPoE de los abonados" default-profile=pppoe-base disabled=no interface=vlan-acceso service-name=isp
/ip address
add address=10.10.50.1/24 comment="router en la red de servicios" interface=ether3 network=10.10.50.0
/ip dhcp-client
add disabled=yes interface=ether1
/ip firewall filter
add action=drop chain=forward comment="los abonados no llegan a la red de servicios" dst-address=10.10.50.0/24 in-interface=all-ppp
add action=drop chain=input comment="los abonados no llegan a la administracion del router" dst-port=21,22,23,80,443,8291,8728,8729 in-interface=all-ppp protocol=tcp
/ppp aaa
set interim-update=1m use-radius=yes
/radius
add address=10.10.50.10 comment="FreeRADIUS en isp-servicios" secret=IspUtnRadius2026 service=ppp src-address=10.10.50.1 timeout=3s
/radius incoming
set accept=yes
/snmp
set enabled=yes
/system clock
set time-zone-autodetect=no time-zone-name=America/Argentina/Buenos_Aires
/system identity
set name=isp-router
/system logging
add topics=radius,!packet
add action=recolector topics=info
add action=recolector topics=warning
add action=recolector topics=error
add action=recolector topics=critical
/system ntp client
set enabled=yes
/system ntp server
set enabled=yes
/system ntp client servers
add address=10.10.50.10
/tool mac-server
set allowed-interface-list=gestion
/tool mac-server mac-winbox
set allowed-interface-list=gestion
