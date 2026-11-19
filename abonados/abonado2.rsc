# =====================================================================
# abonado2.rsc - Configuración del abonado2
# Proyecto final RADIUS - Parte 4: abonados y pruebas (rodri)
# RouterOS 7.20.4
#
# Cómo se usa: en un CHR recién clonado, subir este archivo por WinBox
# (menú Files) y ejecutar:   /import file-name=abonado2.rsc
#
# Requisito previo (verificar con /interface ethernet print):
#   ether1 = adaptador 1 de VirtualBox (solo-anfitrión, gestión)
#   ether2 = adaptador 2 de VirtualBox (red interna "isp-acceso")
# =====================================================================

# Nombre del equipo: aparece en WinBox y en el prompt [admin@abonado2]
/system identity set name=abonado2

# Zona horaria acordada. autodetect=no porque no hay internet para adivinarla
/system clock set time-zone-name=America/Argentina/Buenos_Aires time-zone-autodetect=no

# Borra el cliente DHCP de fábrica. A la gestión se entra por MAC con WinBox
/ip dhcp-client remove [find]

# VLAN 100 sobre ether2: la misma etiqueta que usa el router
/interface vlan add name=vlan-acceso interface=ether2 vlan-id=100

# Cliente PPPoE: se loguea en el router por la VLAN 100 y recibe una IP del pool.
# add-default-route=yes: todo el tráfico del abonado sale por esta conexión.
# La velocidad NO se configura acá: la decide el router (o el RADIUS).
/interface pppoe-client add name=wan-pppoe interface=vlan-acceso user=abonado2 password=clave2 add-default-route=yes disabled=no
