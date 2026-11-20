# Parte 2 · FreeRADIUS

**Responsable:** Nico · **Notas:** [`../notas/nico.md`](../notas/nico.md)

FreeRADIUS **3.2.10** · Imagen propia `isp-lab/freeradius:3.2.10` (la oficial más nuestra configuración)

> Esta carpeta se armó en la integración del jue 19-nov, en la PC de nacho, porque todavía no había nada acá. Queda para que Nico la revise y la haga suya.

Esta receta explica qué hace FreeRADIUS en el proyecto, qué le cambiamos a la imagen oficial, cómo decide a quién deja entrar y cómo se prueba. Cada cosa tiene su explicación, porque en la presentación nos pueden preguntar cualquier línea a cualquiera.

---

## Índice

1. [Qué hace esta parte](#1-qué-hace-esta-parte)
2. [Archivos de esta carpeta](#2-archivos-de-esta-carpeta)
3. [Datos que usa](#3-datos-que-usa)
4. [Qué le cambiamos a la imagen oficial](#4-qué-le-cambiamos-a-la-imagen-oficial)
5. [Cómo decide FreeRADIUS, paso a paso](#5-cómo-decide-freeradius-paso-a-paso)
6. [Suspender a un abonado](#6-suspender-a-un-abonado)
7. [Accounting y registro de intentos](#7-accounting-y-registro-de-intentos)
8. [Control de salud](#8-control-de-salud)
9. [Logs](#9-logs)
10. [Cómo probarlo](#10-cómo-probarlo)
11. [Corte y cambio de plan en caliente](#11-corte-y-cambio-de-plan-en-caliente)
12. [Alternativas que descartamos](#12-alternativas-que-descartamos)
13. [Problemas que tuvimos y cómo se resolvieron](#13-problemas-que-tuvimos-y-cómo-se-resolvieron)
14. [Pendientes](#14-pendientes)
15. [Terminado cuando](#15-terminado-cuando)

---

## 1. Qué hace esta parte

FreeRADIUS recibe las preguntas del router ("¿dejo entrar a este abonado?"), busca al usuario y su plan en PostgreSQL, responde aceptando (con la velocidad del plan) o rechazando, y guarda el accounting que manda el router.

El abonado **nunca habla con FreeRADIUS**: el que pregunta es el router. Por eso el router es el "cliente RADIUS".

---

## 2. Archivos de esta carpeta

| Archivo | Qué es |
|---|---|
| `README.md` | Esta receta |
| `Dockerfile` | Arma nuestra imagen: la oficial 3.2.10 más los cambios de la sección 4 |
| `clients.conf` | Quién le puede hacer preguntas a este RADIUS: el router y una entrada para pruebas |
| `sql` | El módulo que conecta FreeRADIUS con PostgreSQL |

El contenedor se define en el bloque `freeradius` del [`docker-compose.yml`](../docker-compose.yml), que es el archivo de la VM isp-servicios: arma la imagen desde esta carpeta (`build: ./freeradius`), le pasa las dos contraseñas por variables de entorno y publica los puertos.

---

## 3. Datos que usa

| Dato | Valor |
|---|---|
| Dónde corre | En la VM `isp-servicios` (`10.10.50.10`), junto con PostgreSQL. El monitoreo está en otra VM, `isp-monitoreo` (`10.10.50.20`) |
| Router (cliente RADIUS) | `10.10.50.1` |
| Secreto compartido | `IspUtnRadius2026`. Va en `RADIUS_SHARED_SECRET` del `.env`, no en la configuración |
| Puertos | 1812/udp (autenticación) y 1813/udp (accounting), publicados solo en `10.10.50.10` |
| Base | `radius` en el contenedor `postgres`, usuario `radius`. La clave va en `RADIUS_DB_PASSWORD` del `.env` |
| Abonados | `abonado1` (`plan-512k`), `abonado2` (`plan-768k`) y `moroso` (suspendido), cargados por la Parte 1 |
| Red de Docker | La que Docker Compose crea por defecto en isp-servicios. En ese compose están FreeRADIUS, PostgreSQL y node-exporter (que solo mide al servidor), así que desde ahí no ve nada del monitoreo |

---

## 4. Qué le cambiamos a la imagen oficial

La imagen oficial trae la configuración en `/etc/freeradius` y arranca el servidor con `freeradius -f`. Le cambiamos seis cosas; todo lo demás queda de fábrica.

| # | Cambio | Cómo (en el `Dockerfile`) | Por qué |
|---|---|---|---|
| 1 | `clients.conf` propio | `COPY`, que reemplaza al de fábrica | El de fábrica trae un cliente `localhost` con el secreto `testing123`, que conoce cualquiera. El nuestro tiene solo al router y una entrada para pruebas |
| 2 | Módulo `sql` activado | `COPY` a `mods-available/sql` y un enlace en `mods-enabled/` | FreeRADIUS solo usa los módulos que tienen un enlace en `mods-enabled`. El de SQL viene sin activar y apuntando a SQLite |
| 3 | Servidor de estado activado | Enlace en `sites-enabled/status` | Lo usa Docker para saber si FreeRADIUS está vivo (sección 8) |
| 4 | Anotar cada intento de conexión | `sed` que cambia `auth = no` por `auth = yes` en `radiusd.conf`. El `grep` que sigue hace fallar la construcción si el cambio no se aplicó | De fábrica no anota los intentos |
| 5 | No guardar claves en la tabla de intentos | `sed` sobre la consulta de fábrica que escribe en `radpostauth`, con un `grep` que hace fallar la construcción si no se aplicó | De fábrica, cuando el pedido trae la clave (PAP), FreeRADIUS la copia en la columna `pass`. Lo vimos con una prueba a mano. Con PPPoE no pasa, porque usa MS-CHAPv2 y la clave no viaja |
| 6 | Log por la salida estándar | `CMD ["-l", "stdout"]` | De fábrica escribe en un archivo adentro del contenedor. Así se ve con `docker compose logs` |

**No hizo falta tocar el sitio `default`.** La configuración de fábrica ya llama a `sql` al autorizar, en el accounting, después de cada intento y en los rechazos (líneas 484, 760, 919 y 1024 de `sites-available/default`). Alcanzó con activar el módulo.

### `clients.conf`

| Entrada | Valor | Qué hace |
|---|---|---|
| `client isp-router` | `ipaddr = 10.10.50.1` | El router. Tiene que ser la misma IP que el router pone como origen (`src-address=10.10.50.1` en su `/radius`) |
| | `secret = $ENV{RADIUS_SHARED_SECRET}` | El secreto no está escrito: `$ENV{...}` lo toma de la variable de entorno |
| | `require_message_authenticator = yes` | Exige que cada pedido venga firmado. RouterOS 7.20.4 lo manda: con esta línea puesta, los abonados entran |
| `client pruebas-locales` | `ipaddr = 127.0.0.1` | Para probar con `radtest` desde adentro del propio contenedor, sin usar el router |

### `sql`

| Parámetro | Valor | Qué hace |
|---|---|---|
| `dialect` / `driver` | `postgresql` / `rlm_sql_postgresql` | Qué motor es y con qué driver hablarle |
| `server` | `postgres` | El nombre del servicio en el compose. Adentro de Docker se encuentran por nombre, no por IP |
| `login` / `password` | `radius` / `$ENV{RADIUS_DB_PASSWORD}` | Con qué usuario entra a la base. La clave viene del entorno |
| `read_groups` | `yes` | Leer los grupos: de ahí salen el plan y el bloqueo |
| `read_clients` | `no` | Los routers autorizados están en `clients.conf`, no en la tabla `nas` |
| `client_table` | `nas` | Tiene que figurar aunque no se use (ver problema 13.1) |
| `pool` | `start = 2`, `max = 8` | Conexiones que mantiene abiertas con la base, para no abrir una por pedido |
| `$INCLUDE ... queries.conf` | — | Las consultas SQL son las oficiales, sin modificar |

---

## 5. Cómo decide FreeRADIUS, paso a paso

1. **Llega un pedido** (Access-Request) del router.
2. **¿Lo conozco?** La IP de origen tiene que estar en `clients.conf`. Si no está, lo ignora sin contestar y lo anota: `Ignoring request to auth address * port 1812 bound to server default from unknown client 172.18.0.1` (lo probamos mandando un pedido desde una IP que no está en la lista).
3. **¿Viene bien firmado?** Comprueba la firma del pedido con el secreto compartido. Si no cierra, lo descarta **sin contestar**.
4. **Busca al abonado** en `radcheck`. De ahí saca su clave.
5. **Recorre sus grupos** de `radusergroup`, de menor a mayor `priority`. De cada grupo mira `radgroupcheck` (condiciones) y `radgroupreply` (qué devolver), y se queda con el primero que aplica:
   - Un grupo de plan devuelve la velocidad: `Mikrotik-Rate-Limit`.
   - El grupo `morosos` fuerza el rechazo: `Auth-Type := Reject`.
6. **Verifica la clave.** El router negocia MS-CHAPv2: el abonado no manda la clave sino la respuesta a un desafío, y FreeRADIUS repite la cuenta con la clave guardada. Por eso la base guarda `Cleartext-Password`.
7. **Contesta:** Access-Accept con la velocidad, o Access-Reject.
8. **Anota el resultado** en la tabla `radpostauth` y en su log.

Qué deja en el log en cada caso (todas las líneas son reales, del 19-nov):

| Caso | Respuesta | Línea en el log |
|---|---|---|
| Clave bien | Access-Accept | `Login OK: [abonado1] (from client isp-router port 15728642 cli 08:00:27:B2:56:4D)` |
| Clave mal | Access-Reject | `Login incorrect (mschap: MS-CHAP2-Response is incorrect): [abonado2] (from client isp-router ...)` |
| Suspendido | Access-Reject | `Login incorrect: [moroso] (from client isp-router ...)`, sin motivo entre paréntesis |
| Usuario que no existe | Access-Reject | `Login incorrect (No Auth-Type found: rejecting the user via Post-Auth-Type = Reject): [fantasma]` |
| La base está caída | Access-Reject | `rlm_sql (sql): Last connection attempt failed, waiting 30 seconds before retrying` y después dos líneas por intento: `Invalid user (sql: Error getting check attributes): [abonado2]` y `Login incorrect (sql: Error getting check attributes): [abonado2]` |
| Secreto distinto | No contesta | `Dropping packet without response because of error: Received packet from 10.10.50.1 with invalid Message-Authenticator!  (Shared secret is incorrect.)` |

`cli` es la MAC del abonado que intentó conectarse. Sirve para saber desde qué equipo vino el intento.

---

## 6. Suspender a un abonado

Suspender es **agregarle** el grupo `morosos` con prioridad 0. No se le toca el plan.

| username | groupname | priority | Qué significa |
|---|---|---|---|
| moroso | morosos | 0 | Se evalúa primero: rechazo, tenga bien o mal la clave |
| moroso | plan-512k | 1 | Su plan, guardado para cuando lo rehabiliten |

- **Suspender:** `isp suspender <abonado>` inserta la fila de `morosos` y le pide al router que corte la conexión (sección 11).
- **Rehabilitar:** `isp rehabilitar <abonado>` borra esa fila. Vuelve a valer su plan de siempre.

**Por qué agregar y no reemplazar:** si para suspender se le cambia el plan por `morosos`, al rehabilitarlo hay que acordarse de qué plan tenía. Así no se pierde.

Probado con `moroso` (viene suspendido de fábrica) y suspendiendo y rehabilitando a `abonado2`.

---

## 7. Accounting y registro de intentos

**Accounting.** El router manda tres avisos y FreeRADIUS los guarda en `radacct` con las consultas oficiales:

| Aviso | Cuándo | Qué hace en la base |
|---|---|---|
| Start | Al conectarse | Crea la fila de la conexión |
| Interim-Update | Cada minuto (`interim-update=1m` en el router) | Actualiza los contadores de esa fila |
| Stop | Al desconectarse | Le pone hora de fin y causa |

Lo que vimos:

- **Llega exacto cada minuto.** El historial de la base (`radacct_historial`) tiene una copia por minuto y por conexión.
- **Si la base se recrea vacía, las conexiones abiertas reaparecen** con el siguiente aviso del router. Nos pasó al recrear la base con los abonados conectados.
- **Si el router se reinicia, la base queda prolija.** Las conexiones que estaban abiertas quedaron cerradas con causa `Admin-Reboot`, y las que habían quedado colgadas ("fantasma") con `NAS-Reboot`.

**Registro de intentos.** Cada intento, aceptado o rechazado, queda en `radpostauth`. Grafana lo lee por la vista `v_logins`, que no muestra la columna `pass`.

La consulta oficial para PostgreSQL no guarda la MAC ni el motivo del rechazo: esas dos cosas están solo en el log (sección 9).

---

## 8. Control de salud

Docker le pregunta a FreeRADIUS cada 10 segundos si está vivo, **en idioma RADIUS**:

```
echo 'Message-Authenticator = 0x00' | radclient -q -t 2 -r 1 127.0.0.1:18121 status adminsecret
```

| Parte | Qué hace |
|---|---|
| `radclient ... status` | Manda un pedido de tipo Status-Server |
| `127.0.0.1:18121` | El "servidor de estado" que activamos en el `Dockerfile`. Solo escucha adentro del contenedor |
| `adminsecret` | El secreto de fábrica de ese servidor. No sale del contenedor |
| `-t 2 -r 1` | Espera 2 segundos y prueba una sola vez |

**Por qué así y no con un login de prueba:** no toca la base ni deja filas en `radpostauth`.

Con esto `docker compose ps` muestra `isp-freeradius ... (healthy)`.

Además, FreeRADIUS no arranca hasta que la base esté sana (`depends_on` con `condition: service_healthy`). Ese orden vale para `docker compose up`. Cuando se prende la VM, es Docker el que levanta los contenedores, sin mirar el compose. Lo vimos en los tres arranques de la VM con el diseño de dos VMs: FreeRADIUS arrancó antes de que la base aceptara conexiones, falló (`Instantiation failed for module "sql"`) y Docker lo volvió a levantar un segundo después, por el `restart: unless-stopped`. Se cura solo, y en `docker inspect` queda como 1 reinicio.

Al arrancar aparece `Warning: Shared secret for client admin is short`. Se refiere al `adminsecret` del servidor de estado y no molesta: ese servidor solo se alcanza desde adentro del contenedor.

---

## 9. Logs

FreeRADIUS escribe sus logs por la salida estándar, y desde ahí van a dos lugares:

| Dónde | Cómo se mira | Para qué |
|---|---|---|
| Docker, en isp-servicios | `sudo /opt/isp-lab/servidor/isp logs` (los últimos intentos) o `docker compose logs freeradius` (todo) | Diagnóstico rápido en el servidor |
| Loki, en isp-monitoreo | En Grafana, con la etiqueta `job="freeradius"` | Tenerlos junto a los logs del router |

El envío a Loki lo hace Docker, no FreeRADIUS: el bloque `logging` del compose usa el driver `syslog` y manda cada línea al recolector (Alloy), que está en la otra VM: `udp://10.10.50.20:1515`. Alloy les pone la etiqueta `job="freeradius"` y las guarda en Loki.

**Por qué:** cuando algo falla hay que mirar las dos puntas. El router dice "radius timeout" y es FreeRADIUS el que dice por qué.

Tres cosas a saber:

- **`docker compose logs` sigue andando** con el driver `syslog` puesto. Lo comprobamos.
- **En Loki todas sus líneas llegan con nivel `informational`,** también las de error. Para filtrar hay que buscar por texto: `Login incorrect`, `Error`, `Dropping`.
- **El envío es por UDP y no espera respuesta.** Si el recolector está apagado, FreeRADIUS sigue contestando igual (sección 14). Las líneas de ese rato no llegan a Loki; quedan las que guarda Docker (`docker compose logs`).

**Con las dos VMs** lo volvimos a mirar: las líneas llegan a Loki desde la otra máquina con las mismas etiquetas, `job="freeradius"` y `host="isp-servicios"`.

**La hora de cada línea.** El contenedor usa la hora local de la VM (el compose le monta `/etc/localtime`). Sin eso escribía en UTC, y en el tablero cada línea de FreeRADIUS aparecía tres horas adelantada respecto del log del router.

---

## 10. Cómo probarlo

### Sin el router (paso 2 del plan de integración)

```bash
vagrant ssh isp-servicios
sudo /opt/isp-lab/servidor/isp probar abonado1 clave1
```

Le pregunta al RADIUS desde adentro del propio contenedor, con el método que usa PPPoE (`radtest -t mschap`). Tiene que contestar:

```
Received Access-Accept Id 151 from 127.0.0.1:1812 to 127.0.0.1:33897 length 119
	Mikrotik-Rate-Limit = "512k/512k"
```

El mismo comando sin el atajo:

```bash
cd /opt/isp-lab
sudo docker compose exec freeradius sh -c 'radtest -t mschap abonado1 clave1 127.0.0.1 0 "$RADIUS_SHARED_SECRET"'
```

| Parte | Qué hace |
|---|---|
| `docker compose exec freeradius sh -c '...'` | Corre el comando adentro del contenedor, donde existe la variable con el secreto |
| `radtest -t mschap abonado1 clave1` | Simula el pedido de un router por ese usuario y esa clave. `-t mschap` usa el mismo método que PPPoE; sin eso prueba con PAP, que manda la clave en el pedido |
| `127.0.0.1 0` | A qué servidor preguntarle y con qué número de puerto del "router" simulado |
| `"$RADIUS_SHARED_SECRET"` | El secreto compartido |

Resultados (jue 19-nov):

| Prueba | Resultado |
|---|---|
| `abonado1` / `clave1` | Access-Accept, `Mikrotik-Rate-Limit = "512k/512k"` |
| `abonado1` / `clave1` con `-t mschap` | Access-Accept, `512k/512k` |
| `abonado2` / `clave2` | Access-Accept, `Mikrotik-Rate-Limit = "768k/768k"` |
| `abonado1` con clave equivocada | Access-Reject |
| `moroso` / `clave3` (la clave es correcta) | Access-Reject |
| Un usuario que no existe | Access-Reject |

### Con el router (paso 3)

En el router, después de importar `mikrotik/02-radius.rsc` y reconectar a los abonados:

```
/radius monitor 0 once
/ppp active print
```

Lo que obtuvimos: `requests: 6`, `accepts: 6`, `timeouts: 0`, y los dos abonados en `/ppp active print` con la marca **R** (entraron por RADIUS). Las colas salieron con 512k y 768k, dictadas por FreeRADIUS: el perfil por defecto del router no tiene velocidad.

---

## 11. Corte y cambio de plan en caliente

Casi todos los mensajes van del router al RADIUS. Estos dos van **al revés**, del servidor al router, al puerto 3799/udp:

| Mensaje | Para qué |
|---|---|
| Disconnect-Request | Cortar ya la conexión de un abonado |
| CoA-Request | Cambiarle algo a una conexión abierta, sin cortarla. Lo usamos para la velocidad |

Se mandan con `radclient` desde el contenedor de FreeRADIUS, firmados con el secreto compartido. El router los ve llegar desde 10.10.50.10, que es la dirección que tiene anotada en su `/radius`.

El comando `isp` junta el cambio en la base con el aviso al router, para que valga en el momento:

| Comando | En la base | Al router | Probado |
|---|---|---|---|
| `isp suspender <abonado>` | Le agrega el grupo `morosos` | Disconnect con `User-Name=<abonado>` | Sí |
| `isp rehabilitar <abonado>` | Le saca el grupo `morosos` | Nada: el abonado vuelve a entrar solo | Sí |
| `isp plan <abonado> <plan>` | Le cambia el grupo del plan | CoA con `User-Name=<abonado>` y la velocidad nueva | Sí |
| `isp desconectar <abonado>` | Nada | Disconnect | Sí |
| `isp cerrar-fantasmas` | Cierra las conexiones "sin noticias", si el accounting está llegando | Nada | Sí |

Lo que arma por dentro, por ejemplo para un cambio de plan:

```
echo "User-Name=abonado1,Mikrotik-Rate-Limit=768k/768k" | radclient -x -t 3 -r 2 10.10.50.1:3799 coa "$RADIUS_SHARED_SECRET"
```

`isp` informa la respuesta del router: "confirmó (ACK)", "contestó que no (NAK)" o "no contestó". El NAK lo vimos al pedir el corte de un abonado sin conexión abierta.

Resultados (jue 19-nov):

| Prueba | Qué pasó |
|---|---|
| `isp plan abonado1 plan-768k` | El router confirmó. La cola `<pppoe-abonado1>` pasó a `768k/768k` y la sesión siguió (el tiempo de conexión no se reinició) |
| `isp plan abonado1 plan-512k` | Confirmó. La cola volvió a `512k/512k` |
| `isp suspender abonado2` | Confirmó. `abonado2` desapareció de `/ppp active print`, y cada reintento quedó en el log como `Login incorrect: [abonado2]` |
| `isp rehabilitar abonado2` | Volvió a entrar solo, sin tocar nada en el abonado |

Si el router no contesta, mirar en el router `/log print where topics~"radius"` y `/radius incoming monitor once` (ver problema 13.2).

---

## 12. Alternativas que descartamos

| Opción | Por qué la descartamos |
|---|---|
| Montar archivos sueltos sobre la imagen oficial (como proponía el bloque comentado del compose) | El módulo `sql` se podía activar así, pero para cambiar `auth = no` había que copiar y mantener `radiusd.conf` entero. Con un `Dockerfile` cada cambio es una línea y se ve exactamente qué tocamos |
| Dar de alta al router en la tabla `nas` de la base (`read_clients = yes`) | Son dos lugares para lo mismo, y el secreto quedaría guardado en la base. En `clients.conf` hay un solo lugar y el secreto viene del entorno |
| Guardar la clave de los abonados como hash | PPPoE autentica por desafío (vimos MS-CHAPv2): para repetir la cuenta el servidor necesita la clave original. Queda sin probar la variante `NT-Password` |
| La etiqueta `latest-3.2` de la imagen | Es una etiqueta móvil: cambia sola con cada versión. Fijamos `3.2.10` |
| Suspender cambiándole el plan por `morosos` | Se pierde qué plan tenía (sección 6) |

---

## 13. Problemas que tuvimos y cómo se resolvieron

### 13.1 FreeRADIUS no arrancaba y se reiniciaba sin parar

**Síntoma:** `docker compose ps` mostraba `isp-freeradius   Restarting (1)`. En el log:

```
Error: /etc/freeradius/mods-config/sql/main/postgresql/queries.conf[145]: Reference "${client_table}" not found
Error: Errors reading or parsing /etc/freeradius/radiusd.conf
```

**Causa:** al escribir nuestro `sql` sacamos `client_table`, porque no leemos los clientes de la base. Pero las consultas oficiales lo referencian igual.

**Solución:** dejar `client_table = "nas"` aunque `read_clients = no`.

### 13.2 El router no contestaba el aviso de cambio de plan

**Síntoma:** `radclient` terminaba con `No reply from server`. En el log del router:

```
radius,debug received remote request from 10.10.50.10:44357 with bad signature (check your secret!), dropping
```

Y `/radius incoming monitor once` mostraba `bad-requests: 2`.

**Causa:** el pedido llegaba desde la IP correcta pero mal firmado. El comando estaba armado a mano, con varias comillas anidadas (ssh, docker y el intérprete del contenedor), y el secreto no le llegaba bien a `radclient`.

**Solución:** mandar los avisos con el script `servidor/isp`, que arma el comando siempre igual. Con el script el router confirmó a la primera.

### 13.3 Un pedido demorado, visto una sola vez

**Síntoma:** en el log de FreeRADIUS apareció una vez:

```
Error: 1 requests have been waiting in the processing queue for 21 seconds.  Check that all databases are running properly!
```

**Causa:** sin confirmar. Fue a poco de arrancar por primera vez, y el accounting de ese minuto llegó a la base en horario. No volvió a aparecer en los logs que quedaron guardados después.

### 13.4 La MAC y el motivo del rechazo no están en la base

**Síntoma:** en la tabla de intentos la MAC venía siempre vacía.

**Causa:** la consulta oficial de post-auth para PostgreSQL no la guarda.

**Solución:** no tocamos las consultas oficiales. La MAC (`cli ...`) y el motivo están en el log de FreeRADIUS, que también llega a Grafana.

---

## 14. Pendientes

- [ ] **Notas de la parte 2** (`notas/nico.md`): están en blanco.

Comprobado después de escribir este documento (jue 19-nov):

- **La columna `pass` de `radpostauth` queda vacía** en los intentos de los abonados: con MS-CHAPv2 la clave no viaja, así que no hay nada que guardar. Con una prueba a mano por PAP sí quedó guardada (`clave1`, a la vista). Por eso la imagen ya no escribe esa columna (sección 4, cambio 5) y las pruebas a mano usan `-t mschap`.
- **`isp desconectar abonado2`:** el router confirmó, el abonado volvió a entrar solo y la conexión anterior quedó cerrada con causa `NAS-Request`. Con un abonado sin conexión abierta, el router contesta que no (NAK).
- **`isp cerrar-fantasmas`:** cerró la conexión que había quedado abierta al desconectarse un abonado con el RADIUS apagado (causa `Admin-Reset`). Después le sumamos una comprobación: solo cierra si el accounting está llegando (algún aviso en cada uno de los últimos dos minutos). Si el accounting estuvo cortado más de 3 minutos, las conexiones vivas también figuran "sin noticias" hasta su próximo aviso, y cerrarlas sería un error: lo vimos al volver a prender isp-servicios. Con `isp cerrar-fantasmas forzar` se saltea la comprobación.
- **Con el recolector apagado,** FreeRADIUS siguió contestando normalmente.

---

## 15. Terminado cuando

- [x] El contenedor levanta desde el repo (`vagrant up`, que por dentro corre `docker compose up -d --build`).
- [x] `radtest` acepta a `abonado1` y devuelve el atributo `Mikrotik-Rate-Limit` de su plan.
- [x] `radtest` rechaza a `moroso` y a una contraseña incorrecta.
- [x] Un intento de login queda registrado en `radpostauth`.
- [x] El router entra por RADIUS: abonados aceptados con la velocidad de su plan y accounting cada minuto.
- [x] Corte y cambio de plan en caliente desde el servidor.
- [ ] Las notas están al día.
