# =====================================================================
# 03-monitoreo.rsc - Router del ISP, etapa 3: datos para Grafana
# Proyecto final RADIUS - Parte 3: router MikroTik (nacho)
# RouterOS 7.20.4
#
# Qué agrega: el router deja leer su estado (CPU, memoria, interfaces) y
# manda sus logs a isp-monitoreo (10.10.50.20), donde los junta el recolector
# de la parte 5 (Alloy). Los valores salen de alloy/ y de notas/igna.md.
#
# Son dos caminos distintos:
#   - Métricas: el servidor le PREGUNTA al router cada 15 s (SNMP, 161/udp).
#   - Logs: el router los MANDA cuando ocurren (syslog, 1514/udp).
#
# Requisito: haber importado 01-base-pppoe.rsc.
# Cómo se usa:   /import file-name=03-monitoreo.rsc
# =====================================================================

# --- 1. Métricas por SNMP -------------------------------------------------

# La "comunidad" funciona como una contraseña de solo lectura. Esta es la
# que usa el recolector, y solo vale si la pregunta viene de 10.10.50.20
/snmp community add name=lab-monitoreo addresses=10.10.50.20/32 read-access=yes write-access=no comment="solo lectura y solo desde isp-monitoreo"

# RouterOS trae una comunidad "public" que cualquiera conoce. La apagamos
/snmp community set [find default=yes] disabled=yes

# Encender SNMP (viene apagado)
/snmp set enabled=yes

# --- 2. Logs por syslog ---------------------------------------------------

# Un "destino" de logs: el recolector en isp-monitoreo.
#   remote-log-format=syslog   formato clásico (RFC 3164), el que espera Alloy:
#                              <30>Nov 19 17:45:00 isp-router mensaje
#   src-address                salir siempre como 10.10.50.1
# El nombre del destino solo admite letras y números (sin guiones).
/system logging action add name=recolector target=remote remote=10.10.50.20 remote-port=1514 remote-log-format=syslog src-address=10.10.50.1

# Qué se manda: lo mismo que el router ya guarda en su memoria, menos el
# detalle de depuración. Acá entran las conexiones y desconexiones de los
# abonados, los intentos de login fallidos y los cambios de configuración.
/system logging add topics=info action=recolector
/system logging add topics=warning action=recolector
/system logging add topics=error action=recolector
/system logging add topics=critical action=recolector
