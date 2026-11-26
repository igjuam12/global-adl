# =====================================================================
# 01-base-pppoe.rsc - Router del ISP, etapa 1: PPPoE con usuarios locales
# Proyecto final RADIUS - Parte 3: router MikroTik (nacho)
# RouterOS 7.20.4
#
# Qué deja andando: lo mismo que la Práctica 6 de Redes. Los abonados se
# conectan por PPPoE sobre la VLAN 100 y el router los valida con usuarios
# guardados en el propio router. Todavía no hay RADIUS: eso es la etapa 2.
#
# Requisito previo (verificar con /interface ethernet print):
#   ether1 = adaptador 1 de VirtualBox (solo-anfitrión, gestión)
#   ether2 = adaptador 2 (red interna "isp-acceso")
#   ether3 = adaptador 3 (red interna "isp-servicios")
#
# Cómo se usa: en un CHR recién clonado, subir este archivo por WinBox
# (menú Files) y ejecutar:   /import file-name=01-base-pppoe.rsc
# Se importa una sola vez. Si se repite, falla porque las cosas ya existen.
# =====================================================================

# --- 1. Nombre, hora y gestión -----------------------------------------

# Nombre del equipo: aparece en WinBox, en el prompt y en cada línea de log
/system identity set name=isp-router

# Zona horaria acordada. autodetect=no porque no hay internet para adivinarla
/system clock set time-zone-name=America/Argentina/Buenos_Aires time-zone-autodetect=no

# La hora la toma del servidor (NTP), que es la única fuente de hora del ISP.
# Sin esto el router confía en su propio reloj: llegó a estar 46 minutos
# adelantado, y el accounting y los logs quedaban con horarios corridos.
# Mientras el servidor no exista, simplemente no sincroniza.
/system ntp client set enabled=yes servers=10.10.50.10

# Y el router se la da a los abonados. Ellos no pueden pedírsela al servidor:
# el firewall de abajo no los deja entrar a la red de servicios. El router
# contesta en 100.64.1.1, la dirección que los abonados ya conocen.
/system ntp server set enabled=yes

# El CHR trae de fábrica un cliente DHCP en ether1. Lo apagamos: a la gestión
# se entra por MAC con WinBox, así que el router no necesita IP en esa red.
# Se deshabilita en vez de borrarlo, igual que en los abonados: a ellos la CHR
# se los volvía a crear al reiniciar (lo comprobamos el 24-nov).
/ip dhcp-client set [find] disabled=yes

# Una etiqueta en cada boca, para que el /export se explique solo
/interface ethernet set [find default-name=ether1] comment="gestion: red solo-anfitrion, sin IP (WinBox por MAC)"
/interface ethernet set [find default-name=ether2] comment="acceso: red interna isp-acceso, por aca llegan los abonados"
/interface ethernet set [find default-name=ether3] comment="servicios: red interna isp-servicios, por aca se habla con el RADIUS"

# --- 2. Red de servicios (hacia el RADIUS y Grafana) --------------------

# La IP del router en la red interna del ISP. Ahí están los dos servidores:
# isp-servicios (10.10.50.10) e isp-monitoreo (10.10.50.20)
/ip address add address=10.10.50.1/24 interface=ether3 comment="router en la red de servicios"

# --- 3. Red de acceso: PPPoE sobre la VLAN 100 --------------------------

# La VLAN 100 viaja adentro de ether2. Tiene que ser el mismo número que en
# los abonados: si no coincide, no se encuentran y ningún log lo dice
/interface vlan add name=vlan-acceso interface=ether2 vlan-id=100 comment="VLAN 100: abonados"

# La bolsa de IPs que se reparten a los abonados
/ip pool add name=pool-abonados ranges=100.64.1.10-100.64.1.100 comment="IPs para los abonados"

# Perfil base: dice qué IP usa el router dentro de cada conexión
# (local-address) y de dónde sale la IP del abonado (remote-address).
# NO fija velocidad a propósito: con RADIUS la manda el servidor. Así, si
# un abonado tiene cola, sabemos que la velocidad se la dictó el RADIUS.
/ppp profile add name=pppoe-base local-address=100.64.1.1 remote-address=pool-abonados comment="sin velocidad: la dicta el RADIUS"

# Los dos planes, para usar con los usuarios locales. rate-limit se escribe
# subida/bajada del abonado y crea sola una cola por cada conexión.
/ppp profile add name=plan-512k local-address=100.64.1.1 remote-address=pool-abonados rate-limit=512k/512k comment="plan local: 512k de subida y de bajada"
/ppp profile add name=plan-768k local-address=100.64.1.1 remote-address=pool-abonados rate-limit=768k/768k comment="plan local: 768k de subida y de bajada"

# El servidor PPPoE (el "molinete"). Escucha en la VLAN y no directo en
# ether2: en ether2 no vería los paquetes etiquetados con la VLAN 100.
/interface pppoe-server server add service-name=isp interface=vlan-acceso default-profile=pppoe-base disabled=no comment="servidor PPPoE de los abonados"

# --- 4. Usuarios locales (temporales) -----------------------------------

# Sirven para probar el PPPoE sin depender del RADIUS. En la etapa 2 se
# borran: RouterOS busca primero acá y recién después le pregunta al RADIUS.
/ppp secret add name=abonado1 password=clave1 service=pppoe profile=plan-512k comment="TEMPORAL: se borra en la etapa 2"
/ppp secret add name=abonado2 password=clave2 service=pppoe profile=plan-768k comment="TEMPORAL: se borra en la etapa 2"

# --- 5. Usuario para las pruebas de tráfico -----------------------------

# Los abonados miden velocidad con bandwidth-test contra este router, y esa
# herramienta pide un usuario del router. Para no darles la clave de admin
# creamos un grupo con lo mínimo que exige la prueba: "test" (correr
# pruebas) y "winbox". Con "test" solo, el router lo rechaza con
# "login failure for user btest via bandwidth-test" (lo comprobamos).
/user group add name=solo-pruebas policy=test,winbox comment="lo minimo para autenticar un bandwidth-test"
/user add name=btest group=solo-pruebas password=BtestIsp2026 comment="lo usan los abonados en el bandwidth-test"

# --- 6. Protección mínima ------------------------------------------------

# La administración del router solo se alcanza por la boca de gestión.
# "gestion" es una lista con una sola interfaz, ether1.
/interface list add name=gestion comment="por donde se administra el router"
/interface list member add list=gestion interface=ether1 comment="solo la boca de gestion"

# WinBox y telnet por MAC, y el anuncio a los vecinos, solo hacia gestión.
# Así el permiso "winbox" del usuario btest no sirve para entrar al router
# desde la red de abonados.
/tool mac-server set allowed-interface-list=gestion
/tool mac-server mac-winbox set allowed-interface-list=gestion
/ip neighbor discovery-settings set discover-interface-list=gestion

# Lo que llega por una conexión PPPoE no puede seguir hacia la red de
# servicios. Sin esta regla un abonado podría mandarle paquetes UDP al
# servidor (por ejemplo, líneas de log falsas), que no necesitan respuesta.
/ip firewall filter add chain=forward in-interface=all-ppp dst-address=10.10.50.0/24 action=drop comment="los abonados no llegan a la red de servicios"

# Tampoco puede abrir las pantallas de administración del router por IP
# (ftp, ssh, telnet, web, WinBox, API). El ping y el bandwidth-test siguen.
/ip firewall filter add chain=input in-interface=all-ppp protocol=tcp dst-port=21,22,23,80,443,8291,8728,8729 action=drop comment="los abonados no llegan a la administracion del router"
