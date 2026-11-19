# Proyecto final RADIUS — Plan de trabajo del grupo

Administración de Servicios en Linux · UTN · Presentación: **jueves 26 de noviembre**

Este documento es el punto de partida común. Junta la consigna de la cátedra, los acuerdos del grupo y el diseño de la red. Cada uno lo usa para arrancar con su parte. Si alguien cambia un dato común, avisa al grupo y lo actualiza acá.

---

## 1. Qué pide el proyecto

Tenemos que simular el problema de un ISP (una empresa que vende internet):

- Sumarle al router MikroTik un **servidor RADIUS**.
- Simular **abonados** que se conectan por **PPPoE** y generan tráfico.
- Mostrar en **Grafana** cómo está el router y qué hacen los abonados.

Todo tiene que funcionar en **una sola computadora** el día de la presentación.

| Pieza | Qué se espera |
| --- | --- |
| FreeRADIUS (en Docker) | Integrado con el MikroTik |
| PostgreSQL (en Docker) | La base de datos de FreeRADIUS |
| MikroTik (CHR) | Servidor PPPoE de los abonados, trabajando con el RADIUS |
| Abonados simulados | Al menos dos, que se conectan por PPPoE y generan tráfico |
| Grafana (en Docker) | Tablero con CPU, memoria y logs del MikroTik, y datos del accounting del RADIUS |

CPU, memoria, logs y accounting son el **mínimo** del tablero. Qué más mostramos, cómo lo presentamos y con qué herramientas lo decidimos nosotros. No hay una única solución correcta.

### Fechas

| Fecha | Qué pasa |
| --- | --- |
| Mié 18-nov | Consulta y avance: contamos qué investigamos y qué pensamos armar |
| Jue 19-nov | Consulta y avance |
| Mié 25-nov | Consulta y avance: último bloque antes de presentar |
| Jue 26-nov | Presentación con los docentes |

Las consultas sirven para mostrar ideas antes de cerrarlas. Una idea discutida temprano cuesta mucho menos que una corregida el 26.

### Cómo evalúan

Evalúan **el proceso, no el resultado**. Un tablero perfecto que nadie sabe explicar vale menos que uno a medias con decisiones bien pensadas. No se entrega nada escrito: lo contamos en la presentación, con todo funcionando. Las preguntas pueden ir a **cualquier integrante, sobre cualquier parte**.

| Qué miran | Qué cuenta |
| --- | --- |
| Investigación | Entendemos qué es RADIUS y qué papel cumple cada pieza |
| Decisiones | Elegimos con criterio y sabemos explicar las alternativas que descartamos |
| Problemas | Cómo diagnosticamos lo que falló |
| Equipo | Todos pueden responder sobre cualquier parte |
| Creatividad | Qué datos mostramos más allá del mínimo, y por qué esos |

### Uso de IA

Se puede usar todo lo que queramos. La condición: **tenemos que poder explicar qué hace cada parte de cualquier configuración y por qué está ahí**. Si una configuración la generó una IA, nos van a preguntar línea por línea. Además suma contar cómo la usamos: qué le preguntamos, qué respondió mal y cómo nos dimos cuenta.

---

## 2. Conceptos básicos

Cada vez que un abonado se conecta, un ISP necesita responder tres preguntas:

1. **¿Quién sos?** Usuario y contraseña.
2. **¿Qué podés hacer?** Qué plan pagó, por ejemplo 10 o 50 Mbps.
3. **¿Qué hiciste?** Cuánto tiempo estuvo conectado y cuánto usó.

A estas tres preguntas se las llama **AAA**: autenticación, autorización y accounting. El servidor RADIUS es el que las responde. El router no decide solo: le pregunta al RADIUS.

> **Analogía:** el router es el patovica de un boliche y el RADIUS es la lista de invitados. El patovica no conoce a nadie y consulta la lista para saber si deja entrar a alguien. Además, anota a qué hora entró y salió cada uno.

¿Por qué no guardar los usuarios directamente en el router? Porque un ISP real tiene muchos routers y miles de abonados. Con RADIUS hay **una sola lista** que consultan todos los routers. Para dar de alta, cambiar el plan o cortar a un abonado, se toca un solo lugar.

| Concepto | Qué es, en simple |
| --- | --- |
| RADIUS | Un protocolo (un "idioma" entre máquinas) para autenticar usuarios y registrar su uso. FreeRADIUS es el programa gratuito que lo implementa. |
| Cliente RADIUS | Quien le hace preguntas al RADIUS. En nuestro caso es **el router**, no el abonado. El abonado nunca habla con el RADIUS. |
| Secreto compartido | Una contraseña que conocen el router y el RADIUS. El RADIUS solo le contesta a routers que la conocen. Si no coincide, ignora el pedido sin avisar. |
| Accounting | La parte de "¿qué hiciste?": un registro de cada conexión con usuario, hora de inicio, hora de fin y datos usados. |
| PPPoE | La forma en que el abonado se loguea en el router con usuario y contraseña. Recién después de loguearse, el router le da una IP. |
| VLAN | Una forma de separar redes que viajan por el mismo cable, poniéndole una "etiqueta" (un número) a cada paquete. Usamos la VLAN 100 para el tráfico de los abonados. Las dos puntas tienen que usar el mismo número. |
| MikroTik (CHR) | El router. CHR es la versión de MikroTik que corre en una máquina virtual. |
| PostgreSQL | La base de datos donde FreeRADIUS guarda los usuarios, los planes y el accounting. |
| Docker / contenedor | Una forma de correr un programa empaquetado con todo lo que necesita, sin instalarlo a mano. Es parecido a una VM, pero más liviano. |
| Grafana | Un programa para armar tableros con gráficos a partir de datos de distintos lugares. |
| Métrica | Un número que se mide cada cierto tiempo. Ejemplo: "CPU al 35%". |
| Log | Un mensaje de texto sobre algo que pasó. Ejemplo: "10:03 el usuario juan se conectó". |
| Observabilidad | Poder ver desde afuera cómo funciona un sistema, usando métricas y logs. |

### Qué mensajes se mandan el router y el RADIUS

| Mensaje | Quién lo manda | Qué significa |
| --- | --- | --- |
| Access-Request | Router → RADIUS | "Este usuario quiere entrar, ¿lo dejo?" |
| Access-Accept | RADIUS → Router | "Sí, y este es su plan" |
| Access-Reject | RADIUS → Router | "No, rechazalo" |
| Accounting Start | Router → RADIUS | "Este usuario se conectó" |
| Accounting Interim-Update | Router → RADIUS | "Lleva este tiempo y estos datos usados". Se manda cada minuto. |
| Accounting Stop | Router → RADIUS | "Se desconectó; este es el total" |
| Disconnect-Request | RADIUS → Router | "Cortá a este usuario ahora" (sirve para cortar a un moroso en el momento) |

Ejemplo de cómo se ve el accounting:

| Usuario | Inicio | Fin | Descargó |
| --- | --- | --- | --- |
| juan | 10:00 | 10:45 | 300 MB |

---

## 3. Cómo se conecta todo

### El recorrido del abonado, paso a paso

1. El **abonado** se conecta al **router** por PPPoE con su usuario y contraseña.
2. El **router** le pregunta al **RADIUS** si lo deja pasar.
3. El **RADIUS** busca al usuario en **PostgreSQL** y le contesta al router: "sí, con plan de 10 Mbps" o "no".
4. Si es "sí", el router le da una IP al abonado y le limita la velocidad según su plan.
5. Mientras el abonado navega, el router le **informa al RADIUS** cuánto usa (cada minuto). El RADIUS lo guarda en PostgreSQL.
6. **Grafana** muestra el estado del router (CPU, memoria, logs) y el accounting que está en la base.

### La topología

Son **4 máquinas virtuales** en **3 redes**. El router está en el medio: de un lado tiene a los abonados y del otro al servidor.

```
        RED DE ACCESO                                         RED DE SERVICIOS
     red interna "isp-acceso"                              red interna "isp-servicios"
   VLAN 100 · pool 100.64.1.10-100                              10.10.50.0/24

 ┌────────────────┐                                       ┌──────────────────────────────────┐
 │   abonado1     │                                       │          isp-servicios           │
 │   (MikroTik)   ├──┐                                    │      Debian 12 + Docker          │
 │ IP: la da el   │  │    ┌───────────────────────────┐   │      IP 10.10.50.10              │
 │ router (PPPoE) │  │    │        isp-router         │   │                                  │
 └────────────────┘  │    │       (MikroTik CHR)      │   │   Contenedores:                  │
                     ├────┤ ether2            ether3  ├───┤   ├─ FreeRADIUS   1812 y 1813    │
 ┌────────────────┐  │    │ + VLAN 100   10.10.50.1   │   │   ├─ PostgreSQL   5432 (interno) │
 │   abonado2     │  │    │                           │   │   ├─ Grafana      3000           │
 │   (MikroTik)   ├──┘    │ servidor PPPoE            │   │   └─ métricas y logs (a definir) │
 │ IP: la da el   │       │ cliente RADIUS            │   │                                  │
 │ router (PPPoE) │       └─────────────┬─────────────┘   └────────────────┬─────────────────┘
 └────────────────┘                     │ ether1                           │ adaptador NAT
                                        │                                  │
 ┌──────────────────────────────────────┴──────────────────────────────────┴─────────────────┐
 │  NOTEBOOK DE LA PRESENTACIÓN (VirtualBox)                                                 │
 │  · Red de gestión (solo-anfitrión): para entrar a los MikroTik con WinBox                 │
 │  · Por el NAT, isp-servicios baja las imágenes de Docker y Grafana se abre en             │
 │    el navegador en http://localhost:3000                                                  │
 └───────────────────────────────────────────────────────────────────────────────────────────┘
```

**Cómo leer el dibujo:**

- **Red de acceso:** es "la calle" por donde llegan los abonados. Arrancan sin IP. Primero se loguean por PPPoE y recién ahí el router les da una dirección del pool. Del lado del router, la 100.64.1.1 no va en ninguna interfaz: el router la usa dentro de cada conexión PPPoE.
- **Red de servicios:** es la red interna del ISP. Solo están el router y el servidor. Por acá viajan las preguntas al RADIUS y los datos que van a Grafana.
- **Los abonados nunca ven al servidor.** Solo hablan con el router.
- **Red de gestión y NAT:** no son parte del ISP simulado. Son la forma de entrar nosotros a las máquinas desde la notebook.

### Máquinas y adaptadores de VirtualBox

Cada adaptador de VirtualBox se conecta a una red. Los nombres de las redes internas (`isp-acceso` e `isp-servicios`) se escriben exactamente igual en todas las VMs.

| VM | Qué es | Adaptador 1 | Adaptador 2 | Adaptador 3 | RAM |
| --- | --- | --- | --- | --- | --- |
| isp-router | El MikroTik | Gestión (solo-anfitrión) → `ether1` | `isp-acceso` → `ether2` | `isp-servicios` → `ether3` | 256 MB |
| abonado1 | Cliente, MikroTik | Gestión (solo-anfitrión) → `ether1` | `isp-acceso` → `ether2` | — | 256 MB |
| abonado2 | Cliente, MikroTik | Gestión (solo-anfitrión) → `ether1` | `isp-acceso` → `ether2` | — | 256 MB |
| isp-servicios | Debian 12 con Docker | NAT → `enp0s3` | `isp-servicios` → `enp0s8` | — | 2 GB |

- Son unos **3 GB** de RAM en total. Presentamos en la computadora con más RAM.
- Todas las VMs MikroTik se **clonan de un CHR base limpio**. Al clonar, elegir **"generar nuevas direcciones MAC"**: dos abonados con la misma MAC dan problemas con PPPoE.
- Docker va **adentro de la VM Debian**, no con Docker Desktop en Windows. Así todas las VMs se ven en la misma red interna.
- En Debian, el nombre `enp0s8` es el habitual. Se confirma con `ip -br a`.

---

## 4. Datos comunes

Estos datos los usamos todos iguales. Lo importante no es cuáles elegimos, sino que sean los mismos para todos.

### Direcciones IP

| Red | Rango | Quién está |
| --- | --- | --- |
| Gestión | Solo-anfitrión de VirtualBox | Para entrar a los MikroTik con WinBox |
| Servicios (`isp-servicios`) | 10.10.50.0/24 | Router 10.10.50.1 · isp-servicios 10.10.50.10 |
| Acceso (`isp-acceso`, VLAN 100) | Pool 100.64.1.10 a 100.64.1.100 | Router 100.64.1.1. El abonado arranca sin IP y el router le asigna una del pool |

- Evitamos 192.168.100.x para no chocar con otras redes que ya tenemos armadas.
- Dentro de Docker no hacen falta IPs: los contenedores se encuentran por nombre (`postgres`, `freeradius`, `grafana`). Solo el router necesita conocer la IP de isp-servicios.

### Secreto compartido (router ↔ RADIUS)

Unos 16 caracteres, solo letras y números, porque los símbolos a veces se interpretan distinto según dónde se escriban.

- **Secreto:** `IspUtnRadius2026`

### Abonados de prueba

| Usuario | Contraseña | Plan | Para qué sirve |
| --- | --- | --- | --- |
| abonado1 | clave1 | 10 Mbps (subida y bajada) | Caso normal |
| abonado2 | clave2 | 50 Mbps (subida y bajada) | Comparar planes en el tablero |
| moroso | clave3 | Bloqueado | Mostrar que el RADIUS lo rechaza |

Los planes se miden en **megabits por segundo** (Mbps), no en megabytes. En el MikroTik se escriben `10M/10M` y `50M/50M`.

### Base de datos

| Dato | Valor | Para qué |
| --- | --- | --- |
| Base | `radius` | Donde FreeRADIUS guarda todo |
| Usuario `radius` | Contraseña a definir | Lo usa FreeRADIUS: lee y escribe |
| Usuario `grafana_ro` | Contraseña a definir | Lo usa Grafana: solo lectura |

Grafana solo necesita mirar. Si tuviera permiso de escritura y algo sale mal, podría romper la base. Es el principio de **mínimo privilegio**.

### Puertos

Un puerto es como el "número de departamento" dentro de una IP: indica a qué programa le llega el mensaje. Son los valores por defecto; el responsable de cada parte los confirma al investigar.

| Programa | Puerto | Quién lo usa |
| --- | --- | --- |
| RADIUS, autenticación ("¿lo dejo pasar?") | 1812/udp | El router le pregunta al RADIUS |
| RADIUS, accounting ("esto usó") | 1813/udp | El router le informa al RADIUS |
| Corte en el momento (Disconnect) | 3799/udp | El RADIUS le avisa al router. Este puerto está en el router, no en el servidor |
| Grafana | 3000/tcp | Nosotros, desde el navegador de la notebook |
| PostgreSQL | 5432/tcp | Solo FreeRADIUS y Grafana, adentro de Docker. No se publica afuera |
| Métricas y logs del router | Depende de la herramienta | Por ejemplo, SNMP usa 161/udp y syslog 514/udp. Lo define la parte 5 |

### Versiones

Fijamos la versión de todo, para no terminar con versiones distintas si cada uno baja "la última".

- **RouterOS:** 7.20.4.
- **Imágenes de Docker:** una versión fija para cada una. La anota cada responsable en el repo.

### Hora

Todas las máquinas en la zona horaria **America/Argentina/Buenos_Aires**. Si una máquina tiene otra hora, Grafana muestra los datos corridos y los eventos no coinciden entre el router y el servidor.

---

## 5. División del trabajo

Una pieza por persona, pensada para que cada uno pueda arrancar **sin esperar a los demás**. Las piezas se juntan al final (ver sección 9).

| # | Parte | Qué hace | Cómo avanza solo | Responsable |
| --- | --- | --- | --- | --- |
| 1 | Base de datos | Prepara PostgreSQL para que FreeRADIUS guarde usuarios, planes y accounting. Piensa qué datos de accounting mostrar y arma esos paneles en Grafana. | Carga datos de accounting inventados para tener qué consultar | |
| 2 | FreeRADIUS | Hace funcionar el servidor RADIUS y que lea los usuarios y planes desde la base. Se ocupa del rechazo de moroso y del corte en el momento. | Usa `radtest`, una herramienta que simula el pedido de un router sin tener el MikroTik | |
| 3 | Router (MikroTik) | Hace que el router acepte conexiones PPPoE y le pregunte al RADIUS. Deja listos sus datos (CPU, memoria, logs) para que Grafana los pueda leer. | Crea usuarios PPPoE directo en el router, sin RADIUS | |
| 4 | Abonados y pruebas | Simula al menos 2 clientes que se conectan y generan tráfico. Prueba qué pasa cuando algo falla, por ejemplo si se cae el RADIUS. | Se conecta al router con los usuarios locales | |
| 5 | Grafana | Levanta Grafana, investiga cómo llevarle los datos del router y arma el tablero general. | Usa el router solo, y los datos inventados de la base | |

- Las partes **1 y 5 comparten Grafana**: la 5 arma la base del tablero y la 1 suma los paneles de accounting. Así la carga queda pareja.
- Aunque cada uno tenga su parte, **todos investigan lo básico** (sección 2), porque nos pueden preguntar cualquier cosa a cualquiera.

### Qué tiene que investigar cada parte

**Todos:**

- Qué problema le resuelve RADIUS a un ISP.
- Por qué el cliente RADIUS es el router y no el abonado.
- Los mensajes de la sección 2.
- Qué información deja el accounting.
- Qué pasa si el RADIUS se cae.
- La diferencia entre una métrica y un log.

**1 · Base de datos**

- Qué tablas usa FreeRADIUS y qué guarda cada una:
  - `radcheck`: usuarios y contraseñas.
  - `radusergroup` y `radgroupreply`: planes.
  - `radacct`: accounting.
  - `radpostauth`: intentos de login, aceptados y rechazados.
- Cómo crear el usuario de solo lectura `grafana_ro`.
- Cómo hacer que los datos no se pierdan al recrear el contenedor (volúmenes de Docker).

**2 · FreeRADIUS**

- Cómo se organiza la configuración de FreeRADIUS.
- Cómo conectarlo a PostgreSQL (el módulo `sql`).
- Cómo dar de alta al router como cliente.
- Cómo devolver la velocidad del plan (atributo `Mikrotik-Rate-Limit`).
- Cómo rechazar a moroso.
- Cómo mandar un Disconnect con `radclient`.

**3 · Router**

- Cómo se configura en RouterOS 7.20.4:
  - El cliente RADIUS: `/radius` y `/ppp aaa`.
  - El envío de accounting cada minuto (`interim-update`).
  - Que el router acepte cortes desde el RADIUS (`/radius incoming`).
- Cómo exponer CPU, memoria y logs para que se puedan leer desde afuera, junto con la parte 5.

**4 · Abonados y pruebas**

- Cómo configurar el cliente PPPoE sobre la VLAN 100.
- Cómo generar tráfico. Por ejemplo, `/tool bandwidth-test` del propio MikroTik.
- Qué esperamos ver en cada prueba de falla (sección 10).

**5 · Grafana**

- Cómo conectar Grafana a PostgreSQL, a las métricas y a los logs.
- Qué herramienta usar para llevarle los datos del router (sección 7).
- Cómo guardar el tablero y las conexiones como archivos en el repo.

---

## 6. Configuración base (punto de partida)

Con esto queda armada la red y el PPPoE con usuarios locales, para que las partes 3 y 4 puedan arrancar. Es un **boceto**: cada responsable lo revisa, entiende cada línea y lo deja en el repo.

### isp-router

```
# Nombre y hora del router
/system identity set name=isp-router
/system clock set time-zone-name=America/Argentina/Buenos_Aires

# Red de acceso: la VLAN 100 viaja sobre ether2
/interface vlan add name=vlan-acceso interface=ether2 vlan-id=100

# Red de servicios: la IP del router hacia isp-servicios
/ip address add address=10.10.50.1/24 interface=ether3

# El rango de IPs que se reparte a los abonados
/ip pool add name=pool-abonados ranges=100.64.1.10-100.64.1.100

# Los planes: qué IP toma el router, de dónde salen las de los abonados y la velocidad
/ppp profile add name=plan-10m local-address=100.64.1.1 remote-address=pool-abonados rate-limit=10M/10M
/ppp profile add name=plan-50m local-address=100.64.1.1 remote-address=pool-abonados rate-limit=50M/50M

# El servidor PPPoE escucha en la VLAN de acceso
/interface pppoe-server server add service-name=isp interface=vlan-acceso default-profile=plan-10m disabled=no

# Usuarios locales, SOLO para probar antes de tener el RADIUS (después se borran)
/ppp secret add name=abonado1 password=clave1 service=pppoe profile=plan-10m
/ppp secret add name=abonado2 password=clave2 service=pppoe profile=plan-50m
```

### abonado1

En abonado2 cambian el nombre, el usuario y la clave.

```
/system identity set name=abonado1
/system clock set time-zone-name=America/Argentina/Buenos_Aires

# La misma VLAN que el router: si el número no coincide, no hay conexión
/interface vlan add name=vlan-acceso interface=ether2 vlan-id=100

# El cliente PPPoE: se loguea con usuario y contraseña y recibe su IP
/interface pppoe-client add name=wan-pppoe interface=vlan-acceso user=abonado1 password=clave1 add-default-route=yes disabled=no
```

### isp-servicios

En `/etc/network/interfaces`, la IP fija hacia la red de servicios:

```
allow-hotplug enp0s8
iface enp0s8 inet static
    address 10.10.50.10/24
```

En la notebook, para abrir Grafana en `http://localhost:3000` (con la VM encendida):

```
VBoxManage controlvm isp-servicios natpf1 "grafana,tcp,127.0.0.1,3000,,3000"
```

### Prueba de que la red quedó bien

- [ ] Desde isp-router, `/ping 10.10.50.10` responde.
- [ ] Desde isp-servicios, `ping 10.10.50.1` responde.
- [ ] Los dos abonados aparecen en `/ppp active print` del router, con una IP 100.64.1.x.
- [ ] En `/queue simple print` aparecen las colas `<pppoe-abonado1>` (10M) y `<pppoe-abonado2>` (50M), creadas solas por el plan.

---

## 7. Cómo llevar los datos a Grafana (a decidir por la parte 5)

Grafana no junta datos por sí misma: lee de "fuentes de datos". Para el accounting es fácil, porque Grafana se conecta directo a PostgreSQL. Para el router hace falta algo que le pida o reciba los datos y los guarde. Esta es una de las decisiones que más nos van a preguntar: hay que elegir una opción y saber por qué se descartaron las otras.

| Qué dato | Algunas opciones para investigar |
| --- | --- |
| Accounting | Grafana conectado a PostgreSQL con consultas SQL, usando el usuario `grafana_ro` |
| CPU y memoria del router | Leerlos por **SNMP** (protocolo estándar de monitoreo) o por la **API de MikroTik**, y guardarlos en una base de métricas como **Prometheus** o **InfluxDB** |
| Logs del router | El router los manda por **syslog remoto** a isp-servicios. Desde ahí van a una base de logs como **Loki**, o a una tabla de PostgreSQL |

Preguntas que ayudan a decidir:

- ¿Quién inicia la comunicación: el servidor le pregunta al router, o el router le manda los datos?
- ¿Cuántas piezas nuevas suma cada opción, y cuánto cuesta explicarlas?
- Un contador de bytes solo sube. ¿Cómo se muestra la velocidad (bytes por segundo) en lugar del total?

Lo que se elija se suma al `docker-compose.yml` de isp-servicios y a la tabla de puertos.

---

## 8. Repositorio y cómo documentar

Usamos un repositorio Git del grupo, con una carpeta por parte:

```
plan-de-trabajo.md   ← este documento
acuerdos.md          ← los datos comunes (sección 4), si se separan
docker/              ← el docker-compose.yml
postgres/
freeradius/
mikrotik/            ← la configuración exportada del router (/export)
abonados/
grafana/             ← el tablero exportado
notas/               ← un archivo de decisiones por persona
```

**Regla clave:** todo lo que se configura tiene que quedar en un archivo del repo. No alcanza con "lo hice a mano en mi compu": si no está en el repo, no se puede juntar ni rearmar en la máquina de la presentación.

**Plantilla de notas**, igual para todos (`notas/<nombre>.md`). Las secciones salen de lo que evalúan:

1. Qué investigué: qué es mi pieza y qué papel cumple.
2. Alternativas: qué opciones había y por qué descarté cada una.
3. Qué elegí y por qué.
4. Qué falló y cómo lo diagnostiqué (con el comando o el log que lo mostró).
5. Cómo usé la IA: qué le pregunté, qué respondió mal y cómo me di cuenta.

Anotamos **mientras** trabajamos, no al final: dos semanas después nadie se acuerda, y es justo lo que van a preguntar.

---

## 9. Cómo integrar las partes

Juntamos las piezas de a una conexión por vez, siguiendo el recorrido del abonado. Lo hacemos en una reunión o llamada con todos, en la máquina de la presentación.

Cada uno "termina" su parte cuando:

- Su parte arranca desde el repo, no solo en su compu.
- Tiene una prueba que demuestra que anda.
- Sus notas están al día.

| Paso | Qué se conecta | Prueba de que anda | Lideran |
| --- | --- | --- | --- |
| 1 | Levantar todo desde el repo | Prenden las VMs y los contenedores | 1 y 2 |
| 2 | FreeRADIUS ↔ PostgreSQL | `radtest` acepta a abonado1 y rechaza a moroso, sin router | 1 y 2 |
| 3 | Router ↔ RADIUS | Se borran los usuarios locales del router: abonado1 igual entra y moroso es rechazado | 2 y 3 |
| 4 | Abonados navegando | Los 2 abonados generan tráfico y aparecen filas en la tabla de accounting, que se actualizan cada minuto | 3 y 4 |
| 5 | Grafana | Se ven CPU, memoria, logs y accounting cambiando en vivo | 5 y 1 |
| 6 | Pruebas de falla | Apagar el RADIUS y ver qué les pasa a los abonados | 4 |

**Reglas para que salga bien:**

- **Un cambio por vez.** Si conectamos tres cosas juntas y falla, no sabemos cuál fue.
- **Si algo falla, miramos los logs de las dos puntas** antes de cambiar nada. Por ejemplo, el log del router (`/log print`) y el del RADIUS (`freeradius -X` lo muestra en detalle).
- **Anotamos cada problema y cómo lo resolvimos.** "Cómo diagnosticaron lo que falló" es un criterio de evaluación: los errores de la integración son material para la presentación.
- **Al final sacamos una "foto":** un snapshot de las VMs y un commit marcado como versión de la presentación. Si el 26 algo se rompe, volvemos ahí.

### Cronograma propuesto

| Día | Objetivo |
| --- | --- |
| Mié 18 | Leer este documento, repartir las partes y crear el repo |
| Jue 19 (consulta) | Mostrar la topología y las dudas. Cada uno arranca con su parte |
| Vie 20 a dom 22 | Cada parte anda sola, desde el repo |
| Dom 22 o lun 23 | Integración, pasos 1 a 5 |
| Lun 23 | Extras del tablero |
| Mar 24 | Pruebas de falla, snapshot y primer ensayo con preguntas cruzadas |
| Mié 25 (consulta) | Mostrar la demo completa, ajustar y segundo ensayo |
| Jue 26 | Presentación |

---

## 10. Pruebas de falla

Las hacemos antes de la presentación y anotamos qué pasó. Responder "¿qué pasa si...?" con algo que ya probamos vale mucho más que con una suposición.

| Prueba | Cómo se provoca | Qué esperamos ver |
| --- | --- | --- |
| Se cae el RADIUS | Apagar el contenedor de FreeRADIUS | Los abonados ya conectados siguen navegando, porque el router ya los autorizó. Uno que se reconecta no puede entrar. El accounting deja de actualizarse. |
| Se cae la base | Apagar el contenedor de PostgreSQL, con FreeRADIUS prendido | FreeRADIUS no puede verificar a nadie. Comparar con la prueba anterior. |
| Secreto distinto | Cambiar el secreto en un solo lado | El RADIUS ignora los pedidos y el router dice que no responde. Es un buen ejemplo de diagnóstico para contar. |
| Contraseña incorrecta | Cambiar la clave en un abonado | Rechazo, y queda registrado como intento fallido |
| Moroso | Conectar con el usuario moroso | Rechazo |
| Cambio de plan | Pasar a abonado1 de 10 a 50 Mbps en la base, y reconectar | La velocidad cambia sin tocar el router |
| Corte en el momento | Bloquear a un abonado conectado y mandar un Disconnect | Se desconecta al instante y no puede volver a entrar |
| Router cargado | Generar tráfico desde los dos abonados | La CPU del router sube en el tablero |

---

## 11. Ideas para el tablero

El mínimo es CPU, memoria, logs y accounting. Lo que suma en "Creatividad" es mostrar más y saber **por qué** eso le sirve a quien opera el ISP. Algunas ideas:

- **Abonados conectados ahora** y desconectados.
- **Top de consumo:** quién usa más.
- **Tráfico de cada abonado** a lo largo del tiempo.
- **Intentos de login fallidos:** lo primero que mira soporte cuando un cliente llama porque no navega.
- **Por qué se desconectan los abonados:** si cortó el usuario, si se perdió el enlace o si lo cortó el ISP.
- **Duración promedio de las conexiones.**
- **Una alerta** cuando el router avisa que el RADIUS no responde.

Conviene elegir 3 o 4, hacerlos bien y tener una frase que justifique cada uno.

---

## 12. Decisiones pendientes

| Decisión | Opciones | Quién la propone |
| --- | --- | --- |
| Cómo se bloquea a moroso | Un grupo "bloqueado" en la base, o marcar al usuario para que siempre se rechace | Partes 1 y 2 |
| Cómo llevar CPU, memoria y logs del router a Grafana | Ver sección 7 | Partes 5 y 3 |
| Contraseñas de la base | — | Parte 1 |
| Versiones de las imágenes de Docker | — | Cada responsable |
| Responsables de cada parte | — | Todos, hoy |

**Grafana en la misma VM que el RADIUS:** lo elegimos así para ahorrar RAM y simplificar. Es probable que nos pregunten qué pasa si se cae esa VM: se caen el RADIUS y también el tablero que lo mostraría. Respuesta preparada: en un ISP real, el monitoreo va en otra máquina, separado de lo que vigila.

---

## 13. Lo que todos tenemos que poder responder

Antes del 26, cualquiera del grupo tiene que poder contestar sin ayuda:

1. ¿Qué es RADIUS? ¿Qué problema le resuelve a un ISP?
2. ¿Qué papel cumple cada pieza del proyecto?
3. ¿Qué es el accounting? ¿Qué información deja?
4. ¿Qué es la observabilidad? ¿Qué diferencia hay entre una métrica y un log?
5. ¿Cómo lee Grafana el estado del router? ¿Y sus logs? ¿Y la base de datos?
6. Si fuéramos quienes operan el ISP, ¿qué querríamos ver en el tablero?
7. ¿Qué les pasa a los abonados si el RADIUS se cae?

---

## 14. Problemas comunes y dónde mirar

| Síntoma | Causa probable | Dónde mirar |
| --- | --- | --- |
| El abonado no se conecta y las credenciales están bien | La VLAN no coincide en las dos puntas. Ningún log dice "VLAN" | `/interface vlan print` en el router y en el abonado |
| El router dice que el RADIUS no responde | Secreto distinto, IP equivocada, o el RADIUS no conoce al router | `freeradius -X` muestra si el pedido llega y desde qué IP |
| El pedido llega al RADIUS con una IP rara (172.x) | Docker cambia la dirección de origen | Anotarlo y buscar cómo publicar el puerto sin que cambie el origen |
| El accounting no muestra datos hasta que el abonado se desconecta | Falta el envío cada minuto (`interim-update`) | `/ppp aaa print` en el router |
| Un gráfico sube siempre, sin bajar nunca | Se está mostrando un total acumulado en lugar de la velocidad | Investigar cómo calcular la variación en el tiempo |
| Los datos aparecen corridos 3 horas | Zona horaria distinta entre máquinas | `timedatectl` en Debian, `/system clock print` en el router |
| Se perdió la base al recrear el contenedor | PostgreSQL sin volumen | El `docker-compose.yml` |
| Dos abonados no pueden conectarse a la vez | Clonados con la misma MAC | Regenerar la MAC en VirtualBox |
