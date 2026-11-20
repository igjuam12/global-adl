# Parte 1 · Base de datos (PostgreSQL)

**Responsable:** Agus · **Notas:** [`../notas/agustin.md`](../notas/agustin.md)

PostgreSQL **17.12** · Base `radius` · Contenedor `isp-postgres` · VM `isp-servicios` (10.10.50.10)

> En la integración del jue 19-nov (en la PC de nacho) esta parte cambió bastante respecto de la versión original. La sección 9 resume qué cambió y por qué, para que Agus lo vea de un vistazo. Las notas de Agus todavía describen la versión anterior.

La base guarda tres cosas: quién es cada abonado y qué plan tiene, cada conexión con lo que consumió (accounting), y cada intento de conexión. FreeRADIUS, que está en la misma VM, la lee y la escribe. Grafana, que está en otra VM (isp-monitoreo), solo mira.

---

## Índice

1. [Archivos de esta carpeta](#1-archivos-de-esta-carpeta)
2. [Qué guarda cada tabla](#2-qué-guarda-cada-tabla)
3. [Los datos cargados](#3-los-datos-cargados)
4. [Los tres usuarios](#4-los-tres-usuarios)
5. [El historial del accounting](#5-el-historial-del-accounting)
6. [Las vistas: el contrato con Grafana](#6-las-vistas-el-contrato-con-grafana)
7. [Datos de prueba inventados](#7-datos-de-prueba-inventados)
8. [Cómo mirar la base](#8-cómo-mirar-la-base)
9. [Qué cambió respecto de la versión original](#9-qué-cambió-respecto-de-la-versión-original)
10. [Problemas que tuvimos y cómo se resolvieron](#10-problemas-que-tuvimos-y-cómo-se-resolvieron)
11. [Pendientes](#11-pendientes)
12. [Terminado cuando](#12-terminado-cuando)

---

## 1. Archivos de esta carpeta

| Archivo | Qué hace |
|---|---|
| `init/01-schema.sql` | Crea las tablas que usa FreeRADIUS. Es el de la versión original, sin cambios |
| `init/02-datos-acordados.sql` | Carga los abonados, los planes y la regla de bloqueo |
| `init/03-historial-y-vistas.sql` | Crea el historial del accounting y las cuatro vistas que lee Grafana |
| `init/04-roles-y-permisos.sh` | Crea los usuarios `radius` y `grafana_ro` y le da a cada uno solo lo que necesita |
| `pg_hba.conf` | La lista de quién puede entrar a la base, con qué usuario y desde dónde (sección 4) |
| `extras/datos-prueba-sinteticos.sql` | Datos inventados para probar el tablero sin router. **No se carga solo** |

**Cuándo corren los de `init/`:** una sola vez, en orden alfabético, cuando la base se crea vacía. El `docker-compose.yml` monta la carpeta en `/docker-entrypoint-initdb.d`, y la imagen de PostgreSQL ejecuta lo que encuentra ahí. Por eso `04` va último: necesita que las tablas y las vistas ya existan.

En el log del primer arranque se ve cada uno:

```
running /docker-entrypoint-initdb.d/01-schema.sql
running /docker-entrypoint-initdb.d/02-datos-acordados.sql
running /docker-entrypoint-initdb.d/03-historial-y-vistas.sql
sourcing /docker-entrypoint-initdb.d/04-roles-y-permisos.sh
Roles creados: radius (FreeRADIUS) y grafana_ro (Grafana, solo vistas).
PostgreSQL init process complete; ready for start up.
```

El `.sh` aparece como `sourcing` y no como `running`: no hace falta darle permiso de ejecución para que corra.

**Los datos no están en esta carpeta.** Viven en el volumen `pgdata` de Docker, así que sobreviven a apagar el contenedor y a reiniciar la VM. Si se cambia un archivo de `init/`, **no se aplica solo**: hay que borrar el volumen para que la base se cree de nuevo, y eso borra todos los datos:

```bash
cd /opt/isp-lab
sudo docker compose rm -sf postgres freeradius
sudo docker volume rm isp-lab_pgdata
```

Se corre en isp-servicios. Y desde la notebook, `vagrant provision` los vuelve a levantar.

**`pg_hba.conf` funciona distinto.** No corre una vez: PostgreSQL lo lee cada vez que arranca. El compose lo monta en `/etc/postgresql/pg_hba.conf` y arranca la base con `-c hba_file=/etc/postgresql/pg_hba.conf`, para que use esa lista y no la de fábrica. Si se lo cambia, `vagrant provision` lo sube a la VM y `servidor/desplegar.sh` le pide a PostgreSQL que lo relea (`SELECT pg_reload_conf()`), sin reiniciar la base ni cortar a nadie. Lo comprobamos cambiando el archivo: después del `vagrant provision` el contenedor veía el archivo nuevo, y `pg_hba_file_rules` mostraba las tres reglas cargadas, sin errores.

---

## 2. Qué guarda cada tabla

| Tabla | Qué guarda | Quién la usa |
|---|---|---|
| `radcheck` | La clave de cada abonado (`Cleartext-Password`) | FreeRADIUS, al autenticar |
| `radusergroup` | A qué grupos pertenece cada abonado, con una prioridad | FreeRADIUS, para saber su plan y si está suspendido |
| `radgroupreply` | Qué devolver para cada grupo. Acá está la velocidad de cada plan | FreeRADIUS, al armar la respuesta |
| `radgroupcheck` | Condiciones por grupo. Acá está la regla que rechaza a los morosos | FreeRADIUS, al autorizar |
| `radacct` | Una fila por conexión: abonado, IP, MAC, inicio, fin, segundos y bytes | FreeRADIUS, con cada aviso de accounting |
| `radpostauth` | Una fila por intento de conexión, aceptado o rechazado | FreeRADIUS, después de cada intento |
| `radacct_historial` | Una copia de los contadores de `radacct` cada vez que cambian | Un disparador de la base (sección 5) |
| `radreply` | Respuestas para un abonado puntual | Nadie por ahora: la velocidad va por grupo |
| `nas` | Routers autorizados | Nadie: queda vacía. El router se da de alta en `freeradius/clients.conf` |

FreeRADIUS 3.2.10 trabajó contra este esquema sin errores en las tres cosas: autenticación, accounting y registro de intentos.

Comparado con el esquema oficial de esa versión, el nuestro tiene una columna de más en `radacct` (`groupname`), no tiene la tabla `nasreload` y cambia algunos índices. Ninguna de las tres cosas dio problemas.

---

## 3. Los datos cargados

Salen de `plan-de-trabajo.md` y los carga `init/02-datos-acordados.sql`.

**Abonados** (`radcheck`):

| Usuario | Clave |
|---|---|
| abonado1 | clave1 |
| abonado2 | clave2 |
| moroso | clave3 |

**Por qué la clave va en texto plano:** PPPoE autentica por desafío. El abonado no manda la clave, manda una cuenta hecha con ella, y para repetir esa cuenta el servidor necesita conocer la clave original.

**Planes** (`radgroupreply`):

| Grupo | Atributo | Valor |
|---|---|---|
| plan-512k | `Mikrotik-Rate-Limit` | `512k/512k` |
| plan-768k | `Mikrotik-Rate-Limit` | `768k/768k` |

La velocidad está **en el plan y no en el abonado**: con 5.000 abonados en dos planes, la velocidad se escribe en dos lugares. Se escribe subida/bajada del abonado. Son menores a 1 Mbps por el tope de la licencia gratuita de la CHR.

**Regla de bloqueo** (`radgroupcheck`): el grupo `morosos` tiene `Auth-Type := Reject`. Quien pertenece a ese grupo es rechazado siempre, tenga bien o mal la clave.

**Qué plan tiene cada uno** (`radusergroup`):

| Usuario | Grupo | Prioridad |
|---|---|---|
| abonado1 | plan-512k | 1 |
| abonado2 | plan-768k | 1 |
| moroso | plan-512k | 1 |
| moroso | morosos | 0 |

FreeRADIUS recorre los grupos de menor a mayor prioridad. Suspender a alguien es **agregarle** `morosos` con prioridad 0: gana ese y el plan queda guardado debajo. Al rehabilitarlo se borra esa fila y vuelve a valer su plan.

---

## 4. Los tres usuarios

Mínimo privilegio: cada uno entra con su propio usuario y puede solo lo suyo.

| Usuario | Quién lo usa | Qué puede | Clave (en `.env`) |
|---|---|---|---|
| `postgres` | Nosotros, para administrar y operar (comando `isp`) | Todo. Es el dueño de las tablas | `POSTGRES_ADMIN_PASSWORD` |
| `radius` | FreeRADIUS | Leer abonados, grupos y planes. Leer, insertar y actualizar en `radacct` y `radpostauth`. **No puede borrar** ni crear tablas | `RADIUS_DB_PASSWORD` |
| `grafana_ro` | Grafana | Leer las cuatro vistas de la sección 6. **Ninguna tabla** | `GRAFANA_DB_PASSWORD` |

Los permisos de `radius` siguen los de la instalación oficial de FreeRADIUS (su `setup.sql`), sin los de las tablas que no usamos (`nas` y `nasreload`).

Cómo lo hace `init/04-roles-y-permisos.sh`:

| Parte | Qué hace |
|---|---|
| `: "${RADIUS_DB_PASSWORD:?falta ...}"` | Si falta una contraseña en el `.env`, se corta ahí con un mensaje claro. No hay clave por defecto |
| `psql -v clave_radius="..."` y `:'clave_radius'` | La clave entra como variable de `psql`, que le pone las comillas. Una clave con caracteres raros no rompe la consulta |
| `REVOKE ALL ON DATABASE radius FROM PUBLIC` | Nadie entra a la base por el solo hecho de existir |
| `GRANT CONNECT ...` / `GRANT USAGE ON SCHEMA public ...` | Deja entrar solo a `radius` y a `grafana_ro` |
| `GRANT SELECT ON radcheck, ... TO radius` | FreeRADIUS lee quién es cada abonado y qué plan tiene |
| `GRANT SELECT, INSERT, UPDATE ON radacct, radpostauth TO radius` | Y escribe las conexiones y los intentos |
| `GRANT SELECT ON v_abonados, ... TO grafana_ro` | Grafana lee las vistas y nada más |

Lo que comprobamos, con Grafana todavía en la misma VM que la base:

- **FreeRADIUS entra como `radius`.** En la lista de conexiones de la base aparece con ese usuario y con el nombre `FreeRADIUS 3.2.10 - radiusd (sql)`.
- **Grafana entra como `grafana_ro`** y su fuente de datos da "Database Connection OK". Las consultas del tablero funcionan leyendo solo las vistas.

El caso contrario se comprobó después (sección 11): `grafana_ro` recibe `permission denied` al leer `radcheck` y `radpostauth`, y `radius`, al querer borrar o crear una tabla.

### Desde dónde entra cada uno (`pg_hba.conf`)

Los permisos de arriba dicen **qué puede hacer** cada usuario una vez adentro. [`pg_hba.conf`](pg_hba.conf) decide algo anterior: **quién puede entrar, a qué base y desde dónde**. Hace falta porque PostgreSQL ahora publica su puerto (5432/tcp) en la red de servicios, para que Grafana llegue desde la otra VM.

PostgreSQL lee la lista de arriba hacia abajo y usa la primera línea que coincide con la conexión que llega. Si ninguna coincide, la rechaza. Cada línea tiene cinco columnas: tipo de conexión, base, usuario, desde dónde y cómo se identifica.

```
local   all      all                           trust
host    radius   radius       172.16.0.0/12    scram-sha-256
host    radius   grafana_ro   10.10.50.20/32   scram-sha-256
```

| Línea | Qué dice | Para quién es |
|---|---|---|
| `local all all trust` | Las conexiones que no pasan por la red (`local`), o sea las que se abren desde adentro del propio contenedor, entran a cualquier base y con cualquier usuario (`all all`), sin clave (`trust`) | Nosotros, al administrar: `docker compose exec postgres psql ...` y el comando `isp` |
| `host radius radius 172.16.0.0/12 scram-sha-256` | Por la red (`host`), a la base `radius`, el usuario `radius`, solo desde las direcciones 172.16 a 172.31, que son las de las redes internas de Docker. Tiene que dar su clave (`scram-sha-256`) | FreeRADIUS, que está en la misma VM y llega por la red interna de Docker |
| `host radius grafana_ro 10.10.50.20/32 scram-sha-256` | Por la red, a la base `radius`, el usuario `grafana_ro`, solo desde la 10.10.50.20 (`/32` es una única dirección). Tiene que dar su clave | Grafana, que está en isp-monitoreo |

Lo que queda afuera, porque no coincide con ninguna línea:

- **El administrador (`postgres`) por la red,** desde cualquier lado. Solo entra desde adentro del contenedor.
- **`grafana_ro` desde otra dirección** que no sea la 10.10.50.20.
- **`radius` desde la red de servicios.** Solo entra desde la red interna de Docker.
- **Cualquier otro usuario y cualquier otra base.**

Cuatro cosas a saber:

- **La clave del administrador hoy no se le pide a nadie.** Desde adentro del contenedor entra sin clave, y por la red no entra. Se sigue definiendo en el `.env` (`POSTGRES_ADMIN_PASSWORD`).
- **Entrar sin clave vale solo para quien ya está adentro del contenedor.** Para llegar ahí hay que poder usar Docker en isp-servicios, o sea, ser administrador de esa VM.
- **El puerto se publica solo en la 10.10.50.10** (`ports: "10.10.50.10:5432:5432"` en el compose), que es la IP de isp-servicios en la red interna del ISP. En esa red están solo el router y las dos VMs Debian, y el router no deja pasar a los abonados hacia ahí.
- **La conexión de Grafana no va cifrada** (`sslmode: disable` en su fuente de datos). Viaja por la red interna, entre las dos VMs.

**Comprobado con conexiones reales** (19-nov, con las dos VMs):

| Quién y desde dónde | Qué pasó |
|---|---|
| Grafana, como `grafana_ro`, desde isp-monitoreo (10.10.50.20) | Entra: la prueba de salud de la fuente de datos da "Database Connection OK" |
| FreeRADIUS, como `radius`, desde la red interna de Docker | Entra |
| El administrador (`postgres`) por la red | Rechazado: `FATAL: no pg_hba.conf entry for host "172.18.0.1", user "postgres"` |
| `grafana_ro` desde otra dirección | Rechazado, con el mismo mensaje |

Los dos rechazos se probaron desde la propia isp-servicios contra su puerto publicado (10.10.50.10:5432). Por eso la dirección de origen que figura es la 172.18.0.1: así ve Docker a la VM.

---

## 5. El historial del accounting

**El problema.** `radacct` guarda **una** fila por conexión y la va pisando con cada aviso del router. Sirve para saber cuánto lleva consumido un abonado, pero no cuánto consumía hace diez minutos. Es la última foto, no la película.

**La solución.** Cada vez que FreeRADIUS inserta o actualiza una fila de `radacct`, un disparador (*trigger*) copia los contadores a `radacct_historial` junto con la hora de la base.

| Columna | Qué guarda |
|---|---|
| `momento` | Cuándo llegó el aviso, según el reloj de la base |
| `acctuniqueid` | A qué conexión pertenece |
| `username` | El abonado |
| `bytes_subida` | Lo que el router recibió del abonado hasta ese momento |
| `bytes_bajada` | Lo que el router le mandó al abonado hasta ese momento |
| `segundos` | Cuánto lleva conectado |

Con dos copias seguidas se calcula la velocidad: bytes de diferencia sobre segundos de diferencia.

Así se ve con un abonado conectado y sin tráfico (la hora está en UTC):

```
   hora   | username | segundos | bytes_subida | bytes_bajada
----------+----------+----------+--------------+--------------
 22:40:24 | abonado1 |        0 |            0 |            0
 22:41:24 | abonado1 |       60 |         1486 |          370
 22:42:24 | abonado1 |      120 |         2230 |          370
 22:43:24 | abonado1 |      180 |         2974 |          370
```

Una fila por minuto, exacta: es el `interim-update=1m` del router.

**Dos detalles del disparador:**

- **`SECURITY DEFINER`:** la función corre con los permisos de su dueño. Así `radius`, el usuario de FreeRADIUS, no necesita ningún permiso sobre el historial.
- **FreeRADIUS no se entera.** Sus consultas son las oficiales, sin tocar. El historial es cosa de la base.

**Límite:** el historial crece una fila por minuto por cada conexión abierta y no se limpia solo. Para el laboratorio no molesta.

---

## 6. Las vistas: el contrato con Grafana

Grafana no lee las tablas del RADIUS: lee estas cuatro vistas. Si mañana cambia una tabla, se ajusta la vista y el tablero no se entera. Y por acá no sale ninguna contraseña.

| Vista | Columnas | Qué muestra |
|---|---|---|
| `v_abonados` | `abonado`, `plan`, `velocidad`, `suspendido` | Cada abonado con su plan, su velocidad y si está suspendido |
| `v_sesiones` | `sesion`, `abonado`, `ip`, `mac`, `inicio`, `ultima_noticia`, `fin`, `segundos`, `bytes_subida`, `bytes_bajada`, `causa_fin`, `estado` | Cada conexión, abierta o cerrada |
| `v_trafico` | `momento`, `abonado`, `bytes_subida`, `bytes_bajada`, `bps_subida`, `bps_bajada` | El tráfico de cada abonado en el tiempo: un tramo por cada par de avisos seguidos |
| `v_logins` | `momento`, `abonado`, `respuesta` | Cada intento de conexión: `Access-Accept` o `Access-Reject`. Sin la columna `pass` |

**El estado de una conexión** (`v_sesiones.estado`):

| Estado | Cuándo |
|---|---|
| `activa` | Abierta y con noticias en los últimos 3 minutos |
| `sin noticias` | Abierta, pero hace más de 3 minutos que el router no informa nada. El router avisa cada minuto, así que faltaron tres avisos seguidos |
| `cerrada` | El router avisó que terminó |

Lo vimos funcionar: con FreeRADIUS apagado, a los 3 minutos las dos conexiones pasaron a `sin noticias`.

**Los horarios salen del reloj de la base, no del router.** `inicio` es cuándo llegó el primer aviso de esa conexión, `ultima_noticia` cuándo llegó el último, y `fin` es el último aviso de una conexión cerrada. Los tres salen del historial. La hora que dice el router no es confiable (ver problema 10.1).

**`v_trafico` descarta** los tramos de menos de 10 segundos y los que dan negativo, para no mostrar picos falsos.

---

## 7. Datos de prueba inventados

`extras/datos-prueba-sinteticos.sql` trae tres conexiones y seis intentos de login inventados. Sirve para armar paneles con las VMs de MikroTik apagadas.

- **Ya no se carga solo.** Antes estaba en `init/` y la base arrancaba siempre con sesiones inventadas, incluida una "fantasma". Ahora la base arranca vacía y lo que se ve es real.
- **Está actualizado al diseño de ahora:** usa los planes `plan-512k` y `plan-768k`, deja vacía la columna `pass` y marca sus filas para poder borrarlas sin tocar los datos reales. En su encabezado está cómo cargarlo y cómo borrarlo.
- **Probamos cargarlo** dentro de una transacción que después se deshizo: entra sin errores y las vistas lo muestran.

---

## 8. Cómo mirar la base

Lo más rápido, en isp-servicios (`vagrant ssh isp-servicios`):

```bash
sudo /opt/isp-lab/servidor/isp abonados
sudo /opt/isp-lab/servidor/isp sesiones
```

Lo que devuelven (real, del 19-nov):

```
 abonado  |   plan    | velocidad |   estado
----------+-----------+-----------+------------
 abonado1 | plan-512k | 512k/512k | habilitado
 abonado2 | plan-768k | 768k/768k | habilitado
 moroso   | plan-512k | 512k/512k | SUSPENDIDO

 abonado  |      ip      |        mac        | estado |  inicio  | segundos | bytes_subida | bytes_bajada
----------+--------------+-------------------+--------+----------+----------+--------------+--------------
 abonado1 | 100.64.1.100 | 08:00:27:B2:56:4D | activa | 20:29:48 |      180 |         2974 |          370
 abonado2 | 100.64.1.99  | 08:00:27:F0:FF:26 | activa | 20:30:04 |      120 |         2230 |          370
```

`isp abonados` lee `v_abonados` e `isp sesiones` lee `v_sesiones` (solo las que no están cerradas).

Para entrar a la base como administrador:

```bash
cd /opt/isp-lab
sudo docker compose exec postgres psql -U postgres -d radius
```

| Parte | Qué hace |
|---|---|
| `docker compose exec postgres` | Corre el comando adentro del contenedor de la base |
| `psql` | El cliente de PostgreSQL |
| `-U postgres -d radius` | Con qué usuario y a qué base |

Algunas consultas útiles una vez adentro:

```sql
-- Los últimos intentos de conexión
SELECT * FROM v_logins ORDER BY momento DESC LIMIT 10;

-- La velocidad de cada abonado en los últimos minutos
SELECT * FROM v_trafico ORDER BY momento DESC LIMIT 10;

-- Quién está conectado a la base ahora (ahí se ve a FreeRADIUS)
SELECT usename, application_name, state FROM pg_stat_activity WHERE datname = 'radius';
```

Esta es la única forma de entrar como administrador. PostgreSQL publica el 5432/tcp en la 10.10.50.10 para Grafana, pero por la red el administrador no entra (sección 4).

---

## 9. Qué cambió respecto de la versión original

| Antes | Ahora | Por qué |
|---|---|---|
| `POSTGRES_USER: radius`: FreeRADIUS entraba como el superusuario de la base | Administrador `postgres` y un usuario `radius` con los permisos justos | Mínimo privilegio. Un programa que solo anota conexiones no tiene por qué poder borrar tablas |
| `grafana_ro` leía tablas enteras, entre ellas `nas` (con el secreto del RADIUS) y `radpostauth` (con la columna `pass`) | `grafana_ro` lee solo cuatro vistas | Lo mismo: el tablero no tiene que poder ver secretos |
| Cinco filas en `nas`, con subredes enteras y redes del diseño viejo (192.168.56.x) | `nas` vacía. El router se da de alta en `freeradius/clients.conf` | Un solo lugar para los clientes del RADIUS, y el secreto fuera de la base |
| Planes `plan-10m` y `plan-50m` con `256k/512k` y `512k/768k`, más los alias `plan-basico` y `plan-plus` | `plan-512k` (`512k/512k`) y `plan-768k` (`768k/768k`) | Las velocidades que midió la parte 4 y eligió el grupo (opción B). El nombre dice lo que el plan da |
| Los planes devolvían también `Framed-Protocol` y `Service-Type` | Solo `Mikrotik-Rate-Limit` | Es lo único que el router necesita. Con eso solo, las colas se crean bien |
| `moroso` pertenecía solo al grupo `morosos`. Para rehabilitarlo había que escribirle un plan a mano | `moroso` tiene su plan y además `morosos` con prioridad 0 | Al rehabilitar no se pierde qué plan tenía. Se sacó el grupo `bloqueado`, que no se usaba |
| `ON CONFLICT DO NOTHING` en cada carga | Sin esa cláusula | Las tablas no tienen restricciones únicas, así que no hacía nada. Los archivos corren una sola vez |
| Los datos inventados se cargaban siempre (`init/04-...`) | Pasaron a `extras/` | Para que el tablero no muestre sesiones que no existen |
| `03-seguridad-grafana.sh` usaba una clave por defecto si faltaba la variable | `04-roles-y-permisos.sh` se corta con un mensaje | Mejor que falle a que arranque con una clave que nadie eligió |
| — | `radacct_historial`, su disparador y las cuatro vistas | Poder graficar la velocidad de cada abonado en el tiempo, y un contrato claro con Grafana |
| Imagen `postgres:17` | `postgres:17.12` | Versión fija, como pide el plan |
| PostgreSQL no publicaba ningún puerto. Era una decisión de seguridad de Agus: FreeRADIUS y Grafana llegaban por la red interna de Docker, porque estaban en la misma VM | Publica el 5432/tcp, solo en la IP de isp-servicios en la red de servicios (10.10.50.10) | Grafana pasó a otra VM (isp-monitoreo), para que el tablero no se caiga junto con la base y el RADIUS, y tiene que llegar por la red. Hacia Windows sigue sin publicarse |
| La lista de accesos de fábrica de la imagen: por la red entraba cualquier usuario que supiera su clave, desde cualquier dirección, incluido el administrador | `pg_hba.conf` propio: `radius` solo desde Docker, `grafana_ro` solo desde la 10.10.50.20 y el administrador solo desde adentro del contenedor | Con el puerto publicado, la base tiene que decidir quién entra y desde dónde. Queda más restringida que antes |

Lo que **no** cambió: `init/01-schema.sql`.

---

## 10. Problemas que tuvimos y cómo se resolvieron

### 10.1 Los horarios de las conexiones no cerraban

**Síntoma:** en el tablero una conexión abierta mostraba una duración negativa (−1558 segundos). Y una conexión que había empezado a las 20:18 figuraba como iniciada a las 23:05.

**Diagnóstico:** comparando relojes. El servidor y la notebook marcaban 19:43; el router, 20:29.

**Causa:** la hora de inicio que guarda `radacct` es la que dice el router, y el reloj del router no es confiable. Lo vimos 46 minutos adelantado. Y recién reiniciado manda los primeros avisos antes de haber sincronizado su hora.

**Solución:** dos cosas. El router ahora sincroniza su reloj con isp-servicios por NTP (parte 3). Y las vistas dejaron de usar la hora del router: `inicio`, `ultima_noticia` y `fin` salen del historial, que usa el reloj de la base.

### 10.2 La MAC de los intentos venía siempre vacía

**Síntoma:** la primera versión de `v_logins` tenía una columna `mac`, y en todos los registros venía vacía.

**Causa:** la consulta oficial de FreeRADIUS para PostgreSQL no guarda la MAC al anotar un intento.

**Solución:** se sacó la columna de la vista. La MAC y el motivo del rechazo están en el log de FreeRADIUS, que también llega a Grafana.

### 10.3 `psql` no reemplazaba las variables

**Síntoma:** en el comando `isp`:

```
ERROR:  syntax error at or near ":"
LINE 1: SELECT count(*) FROM radcheck WHERE username = :'a'
```

**Causa:** `psql` no reemplaza las variables (`:'a'`) cuando la consulta se le pasa con `-c`.

**Solución:** `servidor/isp` le pasa la consulta por la entrada estándar (`-f -`). Así el nombre que escribe el operador entra como variable y nunca pegado dentro del SQL.

---

## 11. Pendientes

- [ ] **Actualizar `notas/agustin.md`** con el diseño actual (sección 9). Entre otras cosas, el punto "Aislamiento de puertos": ahora la base publica el 5432 en la red de servicios.
- [ ] **Decidir si el historial se limpia** cada tanto.

Comprobado después de escribir este documento (jue 19-nov):

- **`grafana_ro` lee las vistas y nada más:** `SELECT` sobre `radcheck` y sobre `radpostauth` le devuelve `permission denied`.
- **`radius` no puede borrar ni crear:** `DELETE FROM radacct` y `CREATE TABLE` le devuelven `permission denied`.
- **La columna `pass` de `radpostauth` está vacía** en los intentos de los abonados (MS-CHAPv2: la clave no viaja). Una prueba a mano por PAP sí la dejaba escrita; la imagen de FreeRADIUS ya no escribe esa columna (`freeradius/README.md`, sección 4).
- **Los datos sobreviven a borrar y recrear el contenedor:** el historial tenía 57 filas antes y 58 después.

---

## 12. Terminado cuando

- [x] La base levanta desde el repo con las tablas, los abonados y los planes cargados.
- [x] FreeRADIUS lee y escribe con su propio usuario (`radius`).
- [x] Grafana lee con `grafana_ro`, solo las vistas. (Comprobado también con Grafana en isp-monitoreo: sección 4.)
- [x] El accounting queda guardado y se puede graficar en el tiempo.
- [x] Probado que los datos no se pierden al recrear el contenedor.
- [ ] Las notas están al día.
