# =====================================================================
# 02-radius.rsc - Router del ISP, etapa 2: el router le pregunta al RADIUS
# Proyecto final RADIUS - Parte 3: router MikroTik (nacho)
# RouterOS 7.20.4
#
# Qué cambia: el router deja de decidir solo. Cada vez que llega un
# abonado, le pregunta a FreeRADIUS si lo deja pasar y con qué velocidad,
# y después le va informando cuánto usa (accounting).
#
# Requisito: haber importado 01-base-pppoe.rsc y que FreeRADIUS ya esté
# respondiendo en 10.10.50.10 (parte 2). Si el servidor no responde,
# después de importar esto NADIE puede conectarse: es lo esperado, porque
# se borran los usuarios locales.
#
# Cómo se usa:   /import file-name=02-radius.rsc
# =====================================================================

# El "teléfono de la oficina": a quién llamar y con qué secreto.
#   service=ppp   se usa para las conexiones PPP, que incluyen PPPoE
#   address       el servidor FreeRADIUS
#   secret        el secreto compartido: tiene que ser igual en el servidor
#   src-address   el router se presenta siempre como 10.10.50.1, que es la
#                 IP con la que el servidor lo tiene anotado como cliente
#   timeout=3s    cuánto espera cada respuesta. De fábrica son 300 ms, poco
#                 para un servidor que antes de contestar consulta una base
/radius add service=ppp address=10.10.50.10 secret=IspUtnRadius2026 src-address=10.10.50.1 timeout=3s comment="FreeRADIUS en isp-servicios"

# La orden "preguntá antes de abrir y anotá el consumo":
#   use-radius=yes      si el usuario no está en el router, preguntarle al RADIUS
#   accounting=yes      avisarle cuando un abonado entra y cuando sale
#   interim-update=1m   y además, cada minuto, cuánto lleva consumido
/ppp aaa set use-radius=yes accounting=yes interim-update=1m

# Atender cuando llama la oficina: acepta los dos pedidos que manda el RADIUS
# sobre un abonado ya conectado. El de corte (Disconnect), para sacarlo en el
# momento, y el de cambio (CoA), para aplicarle otra velocidad sin cortarlo.
# Solo los acepta si vienen del servidor anotado arriba y con su secreto.
/radius incoming set accept=yes port=3799

# Dejar en el log el diálogo con el RADIUS: cada pedido que sale, cada
# timeout y cada reintento, sin el contenido de los paquetes. El rechazo
# de un abonado ya queda registrado sin esto ("authentication failed -
# radius timeout"); esta regla suma el paso a paso para diagnosticar.
/system logging add topics=radius,!packet action=memory

# Borrar los usuarios locales. RouterOS busca primero en sus propios
# usuarios: mientras existan, a esos abonados los valida el router y nunca
# le pregunta al RADIUS por ellos. Los que ya están conectados no se caen.
/ppp secret remove [find]
