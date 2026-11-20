# Parte 5 · Grafana

**Responsable:** Igna (los paneles de accounting los suma Agus) · **Notas:** [`../notas/igna.md`](../notas/igna.md)

Grafana **13.2.1** · Prometheus **v3.13.1** · snmp-exporter **v0.29.0** · node-exporter · Alloy **v1.21.0** · Loki **3.7.0** · VM `isp-monitoreo` (10.10.50.20)

Grafana arma el tablero del ISP: estado del router (CPU, memoria, logs) y lo que hacen los abonados (accounting). Esta parte también decide cómo llegan los datos del router hasta Grafana.

> El stack (Alloy, Prometheus, Loki y Grafana) es el que armó Igna. En la integración del jue 19-nov, en la PC de nacho, se le sumaron el tablero, los logs de FreeRADIUS y la conexión con el router real, y después se lo pasó a una VM propia. Más tarde las métricas pasaron al modelo estándar de Prometheus: es Prometheus el que pregunta, a exportadores, y Alloy quedó solo para los logs. Queda para que Igna lo revise; sus notas todavía no cubren estos cambios.

---

## Índice

1. [Qué va en esta carpeta](#1-qué-va-en-esta-carpeta)
2. [Datos que usa](#2-datos-que-usa)
3. [El camino de cada dato](#3-el-camino-de-cada-dato)
4. [Las fuentes de datos](#4-las-fuentes-de-datos)
5. [Qué llega de verdad](#5-qué-llega-de-verdad)
6. [El tablero](#6-el-tablero)
7. [Cómo verlo y cómo cambiarlo](#7-cómo-verlo-y-cómo-cambiarlo)
8. [Problemas que tuvimos y cómo se resolvieron](#8-problemas-que-tuvimos-y-cómo-se-resolvieron)
9. [Pendientes](#9-pendientes)
10. [Terminado cuando](#10-terminado-cuando)

---

## 1. Qué va en esta carpeta

```
grafana/
├── provisioning/
│   ├── datasources/   ← las fuentes de datos (Prometheus, Loki y PostgreSQL)
│   └── dashboards/    ← el archivo que carga los tableros
└── dashboards/        ← el tablero como JSON (isp-noc.json)
```

El archivo de Compose del monitoreo, [`docker-compose.monitoreo.yml`](../docker-compose.monitoreo.yml), monta `./grafana/provisioning` y `./grafana/dashboards` en el contenedor. Así Grafana arranca con todo configurado, sin tocar nada a mano.

Las herramientas que llevan los datos del router hasta Grafana van cada una en su carpeta en la raíz del repo: [`alloy/`](../alloy/) (recibe los logs por syslog) y [`prometheus/`](../prometheus/) (a quién le pregunta Prometheus, y la comunidad SNMP). Loki usa la configuración por defecto de su imagen. Por qué se eligió Alloy: ver [`../notas/igna.md`](../notas/igna.md).

**Dónde corre.** Los seis contenedores (Prometheus, snmp-exporter, node-exporter, Alloy, Loki y Grafana) viven en una VM propia, `isp-monitoreo`. La base y el RADIUS están en otra, `isp-servicios`.

- **Por qué separadas:** el monitoreo va en otra máquina que lo monitoreado. Si se cae isp-servicios, el tablero sigue vivo y lo muestra. Con todo en una sola VM se caían juntos el RADIUS y el tablero.
- **Cómo llega el archivo a la VM:** Vagrant sube `docker-compose.monitoreo.yml` a isp-monitoreo con el nombre `docker-compose.yml`, junto con `alloy/`, `prometheus/` y `grafana/`. Adentro de esa VM se usa `docker compose` sin aclarar el archivo.

---

## 2. Datos que usa

| Dato | Valor |
|---|---|
| Dónde corre | VM `isp-monitoreo`, `10.10.50.20` en la red de servicios |
| Grafana | 3000/tcp, se abre en `http://localhost:3000` desde la notebook (el `Vagrantfile` reenvía ese puerto desde isp-monitoreo). Usuario `admin`, clave `GRAFANA_ADMIN_PASSWORD` del `.env` |
| PostgreSQL | Está en la otra VM: `10.10.50.10:5432`. Base `radius`, usuario de solo lectura `grafana_ro` (clave `GRAFANA_DB_PASSWORD` del `.env`). Solo puede leer cuatro vistas, y la base lo acepta solo si viene de `10.10.50.20` |
| Router | `10.10.50.1`. Se lo lee por SNMP v2c con la comunidad `lab-monitoreo`, que el router acepta solo desde `10.10.50.20`. Manda sus logs a `10.10.50.20:1514` por UDP |
| FreeRADIUS | Está en la otra VM. Docker manda sus logs a `10.10.50.20:1515` por UDP |
| Red de Docker | La que Docker Compose crea por defecto en isp-monitoreo. Ahí los contenedores se encuentran por nombre: Prometheus llega a `snmp-exporter` y a `node-exporter`, Alloy a `loki`, y Grafana a `prometheus` y a `loki` |

---

## 3. El camino de cada dato

| Dato | Camino | Quién empieza |
|---|---|---|
| CPU, memoria e interfaces del router | **Prometheus** le pide las métricas del router a `snmp-exporter` cada 15 segundos. `snmp-exporter` le pregunta al router por **SNMP** (161/udp) y traduce la respuesta | El monitoreo pregunta |
| CPU, memoria y disco de los dos servidores | **Prometheus** le pregunta a `node-exporter`, que corre en cada VM Debian. Al de isp-servicios le llega por `10.10.50.10:9100` | El monitoreo pregunta |
| Logs del router | El router los manda por **syslog** a `10.10.50.20:1514` (udp). Ahí escucha Alloy, que los guarda en **Loki** | El router manda |
| Logs de FreeRADIUS | Docker, en isp-servicios, manda por syslog a `10.10.50.20:1515` (udp) lo que escribe el contenedor de FreeRADIUS. Alloy lo guarda en **Loki** | Docker manda |
| Accounting, planes e intentos de conexión | FreeRADIUS los guarda en **PostgreSQL**, en isp-servicios. Grafana los consulta por SQL en `10.10.50.10:5432` | Grafana pregunta |

Los caminos del router son entre el router e isp-monitoreo. Tres cruzan de una VM Debian a la otra: las métricas de isp-servicios y la consulta de Grafana van hacia allá, y los logs de FreeRADIUS vienen de ahí.

### Las métricas: Prometheus pregunta a exportadores

Prometheus trabaja preguntando. Cada 15 segundos le pide sus números a cada **exportador**, que es un programa que los publica en un formato que Prometheus entiende. A quién le pregunta está en [`../prometheus/prometheus.yml`](../prometheus/prometheus.yml):

| Trabajo (`job`) | A quién le pregunta | Qué trae |
|---|---|---|
| `router` | A `snmp-exporter`, pidiéndole los datos de `10.10.50.1`. Queda como `instance="isp-router"` | CPU, memoria, tiempo encendido e interfaces del router |
| `servidores` | A `node-exporter` de cada VM Debian. Quedan como `instance="isp-servicios"` e `instance="isp-monitoreo"` | CPU, memoria y disco de cada servidor |
| `prometheus` | A sí mismo | Sus propias métricas |

- **`snmp-exporter` es el intermediario del router.** El router no habla el idioma de Prometheus, habla SNMP. Prometheus le pide las métricas del router a `snmp-exporter`; él le pregunta al router por SNMP y traduce la respuesta. Usa cuatro grupos de datos que ya trae de fábrica (`system`, `if_mib`, `hrDevice` y `hrStorage`) y la comunidad de [`../prometheus/snmp-auths.yml`](../prometheus/snmp-auths.yml).
- **`node-exporter` mide al propio servidor.** Hay uno en cada VM Debian.
- **La métrica `up`** la arma Prometheus sola: vale 1 si el equipo contestó y 0 si no. Con eso el panel "Equipos" dice qué máquina no responde.

**Por qué así:** es el modelo que Prometheus trae de fábrica, y cada pieza hace una sola cosa. Antes Alloy hacía también el SNMP y le escribía los valores a Prometheus (escritura remota). Funcionaba, pero Prometheus quedaba solo como depósito.

**¿Y el patrón "sidecar"?** Un sidecar es un contenedor auxiliar pegado a uno principal. El MikroTik no es un contenedor, así que no se le puede pegar nada. Lo que le corresponde es un exportador intermediario, y eso es `snmp-exporter`.

### Los logs: Alloy

Alloy quedó solo para los logs. Lo que hace está en [`../alloy/config.alloy`](../alloy/config.alloy):

| Bloque | Qué hace |
|---|---|
| `loki.source.syslog "router"` | Dos puertas de entrada: la 1514 para el router (`job="mikrotik-syslog"`) y la 1515 para FreeRADIUS (`job="freeradius"`). Las dos esperan syslog clásico (RFC 3164) |
| `loki.relabel "syslog"` | Guarda el equipo, la severidad y la *facility* como etiquetas: `host`, `level` y `facility` |
| `loki.write "local"` | Escribe las líneas en Loki |

**Por qué los logs de FreeRADIUS también:** cuando algo falla hay que mirar las dos puntas. El router dice "radius timeout" y es FreeRADIUS el que dice por qué. Con los dos en Loki se ven uno al lado del otro.

Lo que tiene que tener el router para que esto ande está en `mikrotik/03-monitoreo.rsc`.

---

## 4. Las fuentes de datos

Las carga [`provisioning/datasources/datasources.yml`](provisioning/datasources/datasources.yml), con identificadores fijos para que el tablero las encuentre siempre:

| Nombre | `uid` | Adónde apunta |
|---|---|---|
| Prometheus | `ds-prometheus` | `http://prometheus:9090`. Es la fuente por defecto |
| Loki | `ds-loki` | `http://loki:3100` |
| RADIUS-PostgreSQL | `ds-radius` | `10.10.50.10:5432`: la base está en la otra VM. Base `radius`, usuario `grafana_ro`. La clave sale de la variable `GRAFANA_DB_PASSWORD`. Sin cifrado (`sslmode: disable`) |

Prometheus y Loki están en la misma VM que Grafana y se alcanzan por nombre. La base no: Grafana le llega por la red de servicios, y del otro lado la base solo acepta a `grafana_ro` si viene de `10.10.50.20` (ver [`../postgres/README.md`](../postgres/README.md), sección 4).

Las tres dan bien en la prueba de salud de Grafana, también con la base en la otra VM: "Successfully queried the Prometheus API", "Data source successfully connected" y "Database Connection OK".

---

## 5. Qué llega de verdad

Los nombres reales, mirados en la instancia andando. Sirven para escribir consultas nuevas.

Se miraron con todo en una sola VM y otra vez con las dos: no cambiaron. Los logs de FreeRADIUS siguen llegando con `host="isp-servicios"`, ahora desde la otra máquina.

**Prometheus (métricas del router):**

| Qué | Cómo se llama |
|---|---|
| Etiqueta `job` | `router`, con `instance="isp-router"`. Es el nombre del trabajo en `prometheus/prometheus.yml` |
| CPU | `hrProcessorLoad` |
| Memoria | `hrStorageUsed` y `hrStorageSize` con `hrStorageDescr="main memory"`. También está `"system disk"` |
| Tiempo encendido | `sysUpTime`, en centésimas de segundo |
| Interfaces | `ifHCInOctets`, `ifHCOutOctets` e `ifOperStatus`, con la etiqueta `ifName` |
| Valores de `ifName` | `ether1`, `ether2`, `ether3`, `vlan-acceso`, `lo`, y una por cada abonado conectado: `<pppoe-abonado1>`, `<pppoe-abonado2>` |

**Prometheus (métricas de los servidores):** las de `node-exporter`, con `job="servidores"` e `instance="isp-servicios"` o `instance="isp-monitoreo"`. Y para cualquier equipo, `up`: 1 si contestó, 0 si no.

Con el diseño anterior, sin los servidores, Prometheus tenía 385 métricas distintas contando las suyas propias.

**Loki (logs):**

| Etiqueta | Valores vistos |
|---|---|
| `job` | `mikrotik-syslog` (router) y `freeradius` |
| `host` | `isp-router` e `isp-servicios` |
| `level` | `informational` y `error` en el router. En FreeRADIUS, siempre `informational`, también en sus líneas de error |
| `facility` | `daemon` |

Así manda el router cada línea (capturado con su propio sniffer):

```
<30>Nov 19 17:45:00 isp-router prueba de formato: linea escrita a mano
```

Y así quedan en Loki, ya sin el encabezado:

```
abonado2 logged in, 100.64.1.100 from 08:00:27:F0:FF:26
user abonado2 authentication failed - radius timeout
log rule added by console:admin+cet1024w@ttyS0 (*6 = /system logging add action=recolector topics=info)
```

Tres cosas a saber del log del router:

- **No trae los "topics" de RouterOS** (`pppoe`, `system`, etc.), solo el texto. Para filtrar se busca por texto o por `level`.
- **El número entre `< >` lleva la severidad:** vimos 30 para info, 28 para warning y 27 para error. De ahí sale la etiqueta `level`.
- **La hora viene en hora local y sin zona horaria.**

**PostgreSQL:** Grafana solo ve cuatro vistas, `v_abonados`, `v_sesiones`, `v_trafico` y `v_logins`. Qué columnas tiene cada una está en [`../postgres/README.md`](../postgres/README.md), sección 6.

---

## 6. El tablero

Un solo tablero, **"ISP · Centro de operaciones"** (`uid` `isp-noc`), en la carpeta **ISP**. Se actualiza cada 10 segundos y abre mostrando los últimos 30 minutos. El archivo es [`dashboards/isp-noc.json`](dashboards/isp-noc.json).

Tiene dos filtros arriba: **Abonado** (sale de `v_abonados`) y **Nivel de log** (los valores de `level` que hay en Loki).

Cada panel lleva una frase que dice para qué le sirve a quien opera el ISP. Es la que figura en la columna de la derecha.

**Fila "Estado general"**

| Panel | De dónde sale | Para qué sirve |
|---|---|---|
| Equipos | Prometheus | Muestra de un vistazo qué equipo responde y cuál no: el router, isp-servicios e isp-monitoreo |

**Fila "Router"**

| Panel | De dónde sale | Para qué sirve |
|---|---|---|
| Encendido hace | Prometheus | Avisa si el router se reinició: un tiempo corto sin haberlo reiniciado nosotros es una caída |
| CPU ahora | Prometheus | Muestra de un vistazo si el router está exigido en este momento |
| Memoria usada | Prometheus | Indica si al router le queda memoria libre para seguir aceptando conexiones |
| Conectados según el router | Prometheus | Cuenta las conexiones PPPoE que el router tiene abiertas ahora, leídas por SNMP |
| Conectados según el accounting | PostgreSQL | Cuenta las sesiones abiertas en el accounting que dieron noticias en los últimos 3 minutos; si no coincide con lo que dice el router, hay avisos de accounting que no están llegando |
| CPU | Prometheus | Permite ver cuándo se cargó el router y relacionarlo con el tráfico de ese momento |
| Memoria | Prometheus | Muestra si el uso de memoria crece con el tiempo, que es la señal de un problema antes de que el router se caiga |
| Tráfico por interfaz | Prometheus | Muestra cuánto tráfico pasa por cada boca del router; la línea punteada es el tope de 1 Mbps que la licencia gratuita de la CHR le pone a lo que transmite cada interfaz |

**Fila "Abonados"**

| Panel | De dónde sale | Para qué sirve |
|---|---|---|
| Sesiones abiertas | PostgreSQL | Responde quién está conectado ahora, con qué IP, desde qué equipo, con qué plan y cuánto lleva consumido |
| Bajada por abonado | PostgreSQL | Muestra la velocidad de descarga de cada abonado según el accounting, para comprobar que cada uno recibe el plan que paga |
| Subida por abonado | PostgreSQL | Muestra la velocidad de subida de cada abonado según el accounting, para detectar usos fuera de lo común |
| Consumo en el período | PostgreSQL | Compara cuánto consumió cada abonado en el período elegido, que es el dato con el que se factura o se detecta al que más usa |
| Abonados y planes | PostgreSQL | Muestra qué plan y qué velocidad tiene cada abonado y quién está suspendido, sin entrar a la base |
| Sesiones sin noticias | PostgreSQL | Cuenta las conexiones abiertas de las que el router no informa hace más de 3 minutos, señal de que se apagó el router o se cortó la red de servicios |

**Fila "Autenticación"**

| Panel | De dónde sale | Para qué sirve |
|---|---|---|
| Intentos por minuto | PostgreSQL | Muestra cuántos intentos de conexión acepta y rechaza el RADIUS, para notar enseguida una ola de rechazos |
| Últimos rechazos | PostgreSQL | Es lo primero que mira soporte cuando un cliente llama porque no navega: si intentó entrar y fue rechazado |
| Rechazos por motivo | Loki (FreeRADIUS) | Separa los rechazos por clave incorrecta, por abonado suspendido o por otro motivo, que es lo que define si el problema es del cliente o del ISP. En "otro motivo" entran también los rechazos con la base caída (`Login incorrect (sql: Error getting check attributes)`) |
| RADIUS sin respuesta | Loki (router) | Cuenta las veces que el router rechazó a un abonado porque el RADIUS no contestó, que es la falla que deja a todos sin poder conectarse |

**Fila "Sesiones cerradas"**

| Panel | De dónde sale | Para qué sirve |
|---|---|---|
| Por qué se desconectan | PostgreSQL | Distingue si las desconexiones las pidió el abonado, las provocó un corte del enlace o las hizo el ISP |
| Duración promedio | PostgreSQL | Sesiones muy cortas son señal de conexiones inestables que se caen y se vuelven a levantar |
| Últimas sesiones cerradas | PostgreSQL | Deja el historial de cada conexión terminada, con cuánto duró, cuánto consumió y por qué se cerró |

**Fila "Logs"**

| Panel | De dónde sale | Para qué sirve |
|---|---|---|
| Logs del router | Loki (router) | Muestra lo que el router va registrando (conexiones, rechazos, cambios de configuración) para diagnosticar sin entrar al equipo |
| Decisiones del RADIUS | Loki (FreeRADIUS) | Muestra qué decidió el RADIUS en cada intento y por qué, al lado de lo que registró el router, porque cuando algo falla se miran los logs de las dos puntas |

**El mínimo de la consigna** (CPU, memoria, logs y accounting) está en las filas "Router", "Abonados" y "Logs". Lo demás es lo que sumamos. Los que más se apoyan en lo que aprendimos probando:

- **Los dos "Conectados" lado a lado.** Uno sale del router y el otro del accounting. Si no dan lo mismo, se están perdiendo avisos.
- **La línea de 1 Mbps en "Tráfico por interfaz".** Hace visible el tope de la licencia, que es la "opción B" del grupo.
- **"Sesiones sin noticias".** En la base lo vimos: a los tres minutos de apagar FreeRADIUS, las dos conexiones quedaron "sin noticias".
- **"RADIUS sin respuesta" y "Rechazos por motivo".** Usan las líneas reales de las pruebas de falla: `radius timeout` del router, y `Login incorrect` de FreeRADIUS con o sin motivo.

**Qué necesita cada panel.** La columna "De dónde sale" dice también de qué máquina depende:

| De dónde sale | Dónde está | Paneles |
|---|---|---|
| Prometheus | isp-monitoreo | 8: "Equipos" y los de la fila "Router", menos "Conectados según el accounting" |
| Loki | isp-monitoreo | 4: "Rechazos por motivo", "RADIUS sin respuesta" y los dos de la fila "Logs" |
| PostgreSQL | isp-servicios | 12: los de accounting, planes e intentos. También el filtro "Abonado" |

Por eso el monitoreo está en otra VM: si se cae isp-servicios, lo que sale de Prometheus y de Loki no depende de ella. Los logs de FreeRADIUS dejan de llegar, porque FreeRADIUS está en la VM caída, y el panel "Equipos" la marca caída.

**Lo probamos** (19-nov): con isp-servicios apagada (`vagrant halt isp-servicios`), el tablero siguió abierto y actualizándose.

| Qué | Cómo se vio |
|---|---|
| Los 7 paneles de Prometheus | Igual que siempre. "Conectados según el router" bajó a 1, porque el abonado que se reconectó no pudo entrar |
| Los 4 paneles de Loki | "RADIUS sin respuesta" se puso en rojo y fue contando los intentos. "Logs del router" mostró cada `authentication failed - radius timeout`. "Decisiones del RADIUS" quedó en las últimas líneas de FreeRADIUS antes de apagarse (`Signalled to terminate`, `Exiting normally`) |
| Los 12 paneles de PostgreSQL | "No data", con un triángulo rojo de error en la esquina |
| El filtro "Abonado" | Queda en "All", con un triángulo rojo. Los paneles de logs siguen filtrando bien |

La consulta a la base falla rápido (unos 3 segundos, `connect: no route to host`), así que el tablero no se queda esperando. Al prender isp-servicios, los paneles se recuperan solos.

---

## 7. Cómo verlo y cómo cambiarlo

**Verlo:** <http://localhost:3000>, usuario `admin`, carpeta **ISP**. Para que tenga movimiento, los abonados tienen que estar generando tráfico (`abonados/trafico.rsc`).

**Cambiarlo:** el tablero es el archivo `dashboards/isp-noc.json`. Grafana vuelve a leer esa carpeta cada 30 segundos, así que un cambio en el archivo aparece solo, sin reiniciar nada. Lo configura [`provisioning/dashboards/dashboards.yml`](provisioning/dashboards/dashboards.yml):

| Línea | Qué hace |
|---|---|
| `folder: ISP` | En qué carpeta de Grafana aparecen los tableros |
| `path: /var/lib/grafana/dashboards` | De dónde los lee. Es nuestra carpeta `grafana/dashboards/`, montada en el contenedor |
| `updateIntervalSeconds: 30` | Cada cuánto revisa si cambió algún archivo |
| `allowUiUpdates: true` | Deja editar desde la pantalla. Lo que se cambie así hay que exportarlo a este archivo para que quede en el repo |

Para llevar un cambio del repo a isp-monitoreo: `vagrant provision` desde la notebook.

**Páginas de diagnóstico.** Alloy (12345) y Prometheus (9090) quedan en `127.0.0.1` de isp-monitoreo salvo que se defina `GESTION_IP` en el `.env`. Se consultan desde adentro de esa VM (`vagrant ssh isp-monitoreo`), por ejemplo:

```bash
curl -s http://127.0.0.1:9090/api/v1/label/__name__/values
```

Devuelve la lista de métricas que tiene Prometheus.

---

## 8. Problemas que tuvimos y cómo se resolvieron

### 8.1 Todos los paneles de Prometheus salían vacíos

**Síntoma:** CPU, memoria y tráfico sin datos, aunque Prometheus tenía las métricas.

**Diagnóstico:** mirando en Prometheus qué etiquetas traen de verdad las métricas.

**Causa:** las consultas filtraban por `job="mikrotik-snmp"`, que era el `job_name` puesto en `prometheus.scrape`. Pero la etiqueta real es `job="integrations/snmp/isp_router"`: la pone el exportador de Alloy y ese `job_name` no la cambia.

**Solución:** las consultas del tablero no filtran por `job` (hay un solo router y los nombres de las métricas son propios de SNMP). Y se sacó el `job_name` de `config.alloy`, que no hacía nada.

**Hoy:** ese exportador ya no está adentro de Alloy. Las métricas del router llegan con `job="router"`, que es el nombre del trabajo en `prometheus/prometheus.yml`.

### 8.2 Una sesión abierta mostraba duración negativa

**Síntoma:** en "Sesiones abiertas", −1558 segundos de duración.

**Causa:** la hora de inicio venía del reloj del router, que estaba adelantado.

**Solución:** se arregló en la base. Las vistas ahora sacan los horarios del reloj de la base, y el router sincroniza su hora por NTP con isp-servicios. Está contado en [`../postgres/README.md`](../postgres/README.md), problema 10.1.

### 8.3 "Últimos rechazos" no podía mostrar la MAC

**Síntoma:** la columna de la MAC venía vacía en todos los registros.

**Causa:** FreeRADIUS no la guarda en la tabla de intentos.

**Solución:** el panel agrupa por usuario. La MAC y el motivo se ven en "Decisiones del RADIUS", que lee el log de FreeRADIUS.

### 8.4 Las líneas de FreeRADIUS traían tres horas de más

**Síntoma:** en "Decisiones del RADIUS", el texto de cada línea decía `Fri Nov 20 00:49:30` mientras Grafana la ubicaba a las 21:49:30 del 19.

**Causa:** el contenedor de FreeRADIUS no sabe en qué zona horaria está la VM y escribe en UTC.

**Solución:** el compose le monta `/etc/localtime` de la VM, de solo lectura. Ahora el texto y la hora de Grafana coinciden.

### 8.5 Dos tablas no entraban en su panel

**Síntoma:** en "Últimos rechazos" la fecha salía cortada, y en "Últimas sesiones cerradas" la columna del motivo quedaba fuera de la vista.

**Solución:** fechas más cortas (día, mes y hora) y un ancho fijo para las columnas angostas, así el motivo tiene lugar.

---

## 9. Pendientes

- [x] **Mirarlo dibujado.** Se sacó una captura del tablero completo con datos reales y se revisó: la línea punteada de 1 Mbps, la dona, las tablas coloreadas y los paneles de logs se ven bien. De esa revisión salieron dos arreglos: las barras de "Rechazos por motivo" no tenían nombre, y los paneles de logs resaltaban cada línea entera.
- [ ] **Probar a mano el filtro "Abonado"** eligiendo un solo abonado en el navegador. Con "Todos" funciona.
- [ ] **Repasar las consultas de la última versión.** La prueba consulta por consulta (22 de paneles y las 2 de los filtros, todas sin error y con datos) se hizo sobre una versión anterior. Después se sumaron "Rechazos por motivo" y "Decisiones del RADIUS" y se simplificaron las de sesiones.
- [ ] **Causas de desconexión:** solo se ejercitaron algunas (`User-Request`, `NAS-Request`, `Admin-Reboot`, `NAS-Reboot`). Las que no estén traducidas se muestran tal cual.
- [ ] **Notas de la parte 5:** sumar estos cambios a `notas/igna.md`. Ahí todavía dice que el que le pregunta al router es isp-servicios; ahora es isp-monitoreo.
- [x] **Comentario viejo de `provisioning/datasources/datasources.yml`:** corregido. Ahora dice que la base está en la otra VM.
- [x] **Pruebas con las dos VMs:** hechas el 19-nov. Los resultados están en las secciones 4, 5 y 6.

---

## 10. Terminado cuando

- [x] Grafana levanta desde el repo con las fuentes de datos ya cargadas.
- [x] El tablero muestra CPU, memoria y logs del router, y el accounting. (Comprobado con datos reales por la API y en una captura del tablero completo.)
- [x] Hay 3 o 4 paneles extra, cada uno con una frase de por qué le sirve a quien opera el ISP.
- [x] El tablero está exportado en esta carpeta.
- [ ] Las notas están al día.

Las dos primeras se comprobaron con el stack en la misma VM que el RADIUS y otra vez con el stack en isp-monitoreo, con una captura del tablero completo en cada caso.
