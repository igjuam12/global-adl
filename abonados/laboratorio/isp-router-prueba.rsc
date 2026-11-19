# =====================================================================
# isp-router-prueba.rsc - Router de PRUEBA de la parte 4
# Proyecto final RADIUS - Parte 4: abonados y pruebas (rodri)
# RouterOS 7.20.4
#
# OJO: este NO es el router oficial. La configuración oficial del router
# es de nacho (carpeta mikrotik/). Este archivo es el "reemplazo trucho"
# que usó la parte 4 para probar los abonados sin esperar al router real
# ni al RADIUS. Usa usuarios locales (/ppp secret) en lugar del RADIUS.
#
# Requisito previo (verificar con /interface ethernet print):
#   ether1 = adaptador 1 (solo-anfitrión, gestión)
#   ether2 = adaptador 2 (red interna "isp-acceso")
#   ether3 = adaptador 3 (red interna "isp-servicios")
# =====================================================================

/system identity set name=isp-router
/system clock set time-zone-name=America/Argentina/Buenos_Aires time-zone-autodetect=no
/ip dhcp-client remove [find]

# Red de acceso: la VLAN 100 viaja sobre ether2
/interface vlan add name=vlan-acceso interface=ether2 vlan-id=100

# Red de servicios (en el laboratorio de la parte 4 no hay nada del otro lado)
/ip address add address=10.10.50.1/24 interface=ether3

# Bolsa de IPs para los abonados
/ip pool add name=pool-abonados ranges=100.64.1.10-100.64.1.100

# Planes acordados por el grupo (opción B): 512k y 768k
# local-address = IP del router dentro de cada conexión PPPoE
# remote-address = de dónde sale la IP del abonado
# rate-limit = subida/bajada del abonado; crea una cola dinámica por abonado
/ppp profile add name=plan-512k local-address=100.64.1.1 remote-address=pool-abonados rate-limit=512k/512k
/ppp profile add name=plan-768k local-address=100.64.1.1 remote-address=pool-abonados rate-limit=768k/768k

# Servidor PPPoE escuchando en la VLAN (no directo en ether2)
/interface pppoe-server server add service-name=isp interface=vlan-acceso default-profile=plan-512k disabled=no

# Usuarios LOCALES, solo mientras no hay RADIUS. Con el RADIUS real se borran.
/ppp secret add name=abonado1 password=clave1 service=pppoe profile=plan-512k
/ppp secret add name=abonado2 password=clave2 service=pppoe profile=plan-768k

# El servidor de bandwidth-test viene encendido de fábrica
# (/tool bandwidth-server: enabled=yes, authenticate=yes). No hace falta configurarlo.
