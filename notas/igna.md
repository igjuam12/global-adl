# Notas — Parte 5: Grafana

**Responsable:** Igna

Escribir **mientras** se trabaja, no al final. Es lo que preguntan en la presentación.

## 1. Qué investigué

Grafana no junta datos por sí misma: lee de fuentes de datos. Para el accounting se conecta directo a PostgreSQL. Para el router hace falta algo que le pida o reciba CPU, memoria y logs y los guarde. Mi parte es elegir cómo llegan esos datos y armar el tablero.

Qué leí y probé hasta el 19/11:
- Cómo expone RouterOS sus métricas por SNMP (`hrProcessorLoad`, `hrStorage`, `ifTable`) y cómo manda logs por syslog remoto.
- Qué recolectores existen hoy y cuáles siguen vigentes (Promtail terminó su vida útil el 2/3/2026).
- Cómo cargar fuentes de datos y tableros por archivos (*provisioning*), para que Grafana arranque configurado desde el repo.

## 2. Alternativas

| Opción | Por qué la descarté |
| --- | --- |
| Promtail para los logs | Terminó su vida útil el 2/3/2026: no conviene empezar un proyecto nuevo con él |
| Telegraf (propuesto en `referencia/`) | Sirve y queda como plan B, pero habría que sumar otra pieza para los logs; Alloy lo cubre todo con un solo contenedor |
| Exportador por la API de MikroTik (por ejemplo mktxp) | Suma una pieza más y usuario/contraseña de la API en el router; SNMP es estándar y alcanza para CPU y memoria |
| Logs a una tabla de PostgreSQL | Mezcla los logs con la base del RADIUS y no es lo que usa un NOC; Loki está pensado para esto |
| Docker Desktop en Windows en lugar de Docker Engine en la VM | Agrega capas de NAT que complican saber desde qué IP llega el tráfico al diagnosticar |

## 3. Qué elegí y por qué

**Un solo recolector, Grafana Alloy**, con tres caminos:

| Dato | Camino |
| --- | --- |
| CPU, memoria, interfaces del router | SNMP v2c (exportador SNMP incluido en Alloy) → Prometheus por `remote_write` |
| Logs del router | Syslog UDP 1514 (RFC 3164) → Alloy → Loki |
| Accounting | Grafana consulta `radacct` por SQL con el usuario de solo lectura `grafana_ro` |

Por qué: un solo contenedor para métricas y logs, es el reemplazo actual de Promtail, y SNMP es estándar y fácil de explicar. Al contador de bytes (que solo sube) se lo muestra como velocidad con `rate()` en Prometheus.

Puertos que usa esto: 161/udp (isp-servicios le pregunta al router) y 1514/udp (el router manda syslog). Quedaron anotados en `plan-de-trabajo.md`.

## 4. Qué hice

Archivos que dejé en el repo:

| Archivo | Qué hace |
| --- | --- |
| `docker-compose.yml` (bloques de la Parte 5) | Alloy, Prometheus, Loki y Grafana, con versiones fijas |
| `alloy/config.alloy` | SNMP al router (10.10.50.1), scrape cada 15 s, escritura en Prometheus; receptor de syslog y envío a Loki, con etiquetas `host`, `level` y `facility` |
| `alloy/snmp-auths.yml` | Comunidad SNMP del laboratorio (`lab-monitoreo`) |
| `prometheus/prometheus.yml` | Configuración mínima; el router lo escribe Alloy, no se consulta desde acá |
| `grafana/provisioning/datasources/datasources.yml` | Fuentes de datos Prometheus, Loki y RADIUS-PostgreSQL con identificadores fijos |
| `grafana/provisioning/dashboards/dashboards.yml` | Carga los tableros de `grafana/dashboards/` en la carpeta ISP |

Probado en la VM `isp-servicios` (Debian 12, Docker 29.10.0, Compose v5.8.0): los cuatro contenedores levantan y vuelven solos tras reiniciar; un mensaje syslog de prueba llegó a Loki con sus etiquetas.

Pendiente: conectar el router real (SNMP y syslog), probar las fuentes con la base del RADIUS y armar y exportar el tablero.

## 5. Qué falló y cómo lo diagnostiqué

| Síntoma | Cómo lo diagnostiqué (comando o log) | Causa | Solución |
| --- | --- | --- | --- |
| `sudo: unable to resolve host isp-servicios` tras cambiar el nombre de la VM clonada | Mensaje al ejecutar `sudo`; `cat /etc/hosts` | `/etc/hosts` seguía con el nombre viejo (`base`) | Editar la línea `127.0.1.1` con el nombre nuevo |
| El `machine-id` seguía igual al de la VM original | `cat /etc/machine-id` | Un espacio faltante en el `rm` borraba una ruta inexistente; además `systemd-machine-id-setup` copió el ID viejo desde D-Bus | Borrar ambos archivos y generar uno nuevo con `dbus-uuidgen --ensure` |
| Un mensaje de `logger` no aparecía en Loki | `docker compose logs alloy` → `error parsing syslog stream ... [col 4]`; `.../label/job/values` de Loki vacío | `logger` manda un formato que Alloy no interpreta con `rfc3164` (causa exacta sin confirmar) | Prueba aislada con un mensaje RFC 3164 armado a mano (`echo ... > /dev/udp/10.10.50.10/1514`): llegó bien |
| Timeouts de SNMP hacia 10.10.50.1 en los logs de Alloy | `docker compose logs alloy` | Todavía no existe el router en esa IP | Esperado; se resuelve al conectar el CHR |

## 6. Cómo usé la IA

- La primera guía que me dio la IA usaba Telegraf. Al investigar vi que Promtail estaba descontinuado y que Alloy cubre métricas y logs con una sola pieza, así que cambié de diseño.
- Me propuso poner `gateway 10.10.50.1` en la interfaz de la red de servicios. Lo descartamos: el router no tiene salida a internet y rompía `apt` y `docker pull`.
- Dio por hecho que el error de syslog era un `syslog_format` mal ubicado en `config.alloy`. Revisé el archivo y estaba bien: la hipótesis era falsa. Lo resolví con la prueba aislada.
- Me dijo que había que levantar los contenedores a mano tras reiniciar la VM; vi con `docker compose ps` que ya habían arrancado solos.
- Los tags de las imágenes (Alloy, Prometheus, Loki, Grafana) los verifiqué con `docker compose pull`.
