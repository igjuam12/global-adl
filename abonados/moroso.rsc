# =====================================================================
# moroso.rsc - Segunda conexión de prueba, con el usuario "moroso"
# Proyecto final RADIUS - Parte 4: abonados y pruebas
# RouterOS 7.20.4
#
# Se carga solo en abonado1:   /import file-name=moroso.rsc
#
# Sirve para mostrar el rechazo sin tocar la conexión normal del abonado.
# Queda apagada. Para la prueba:
#   /interface pppoe-client enable wan-moroso     (intenta entrar y lo rechazan)
#   /interface pppoe-client disable wan-moroso    (dejarla apagada otra vez)
# =====================================================================

# add-default-route=no: aunque algún día entrara, no le cambia la salida al abonado
/interface pppoe-client add name=wan-moroso interface=vlan-acceso user=moroso password=clave3 add-default-route=no disabled=yes comment="prueba de rechazo: se enciende a mano"
