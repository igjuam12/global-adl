# =====================================================================
# abonado1.rsc - Configuración del abonado1
# Proyecto final RADIUS - Parte 4: abonados y pruebas (rodri)
# RouterOS 7.20.4
#
# Cómo se usa: en un CHR recién clonado, subir este archivo por WinBox
# (menú Files) y ejecutar:   /import file-name=abonado1.rsc
#
# Requisito previo (verificar con /interface ethernet print):
#   ether1 = adaptador 1 de VirtualBox (solo-anfitrión, gestión)
#   ether2 = adaptador 2 de VirtualBox (red interna "isp-acceso")
# =====================================================================

# Nombre del equipo: aparece en WinBox y en el prompt [admin@abonado1]
/system identity set name=abonado1

# Zona horaria acordada. autodetect=no porque no hay internet para adivinarla
/system clock set time-zone-name=America/Argentina/Buenos_Aires time-zone-autodetect=no

# La hora se la pide al router por NTP. Sin esto el abonado confía en su propio
# reloj, que se corre. Al servidor de hora no puede llegar: el router no deja
# pasar a los abonados a la red de servicios.
/system ntp client set enabled=yes servers=100.64.1.1

# Apaga el cliente DHCP de fábrica: a la gestión se entra por MAC con WinBox.
# Se deshabilita en vez de borrarlo: si se borra, la CHR lo vuelve a crear al
# reiniciar y el abonado otra vez toma IP en la gestión (lo comprobamos el 24-nov).
/ip dhcp-client set [find] disabled=yes

# VLAN 100 sobre ether2: la misma etiqueta que usa el router
/interface vlan add name=vlan-acceso interface=ether2 vlan-id=100

# Cliente PPPoE: se loguea en el router por la VLAN 100 y recibe una IP del pool.
# add-default-route=yes: todo el tráfico del abonado sale por esta conexión.
# La velocidad NO se configura acá: la decide el router (o el RADIUS).
/interface pppoe-client add name=wan-pppoe interface=vlan-acceso user=abonado1 password=clave1 add-default-route=yes disabled=no
