# Parte 4 · Abonados y pruebas

**Responsable:** Rodri · **Notas:** [`../notas/rodri.md`](../notas/rodri.md)

Receta de armado e integración, para cualquiera del grupo que integre en su PC (y para nacho, que arma el router).
RouterOS **7.20.4** · Planes (los de la base, `postgres/init/02-datos-acordados.sql`): **abonado1 `plan-10m` = 256k subida / 512k bajada · abonado2 `plan-50m` = 512k subida / 768k bajada**

Esta receta explica cómo armar los dos abonados desde cero, qué tiene que tener el router para que se conecten, y cómo integrarlos con el router oficial (el de `mikrotik/`) paso a paso. Cada comando tiene su explicación, porque en la presentación nos pueden preguntar cualquier línea a cualquiera.

---

## Índice

1. [Qué hace esta parte](#1-qué-hace-esta-parte)
2. [Archivos de esta carpeta](#2-archivos-de-esta-carpeta)
3. [Qué necesitan los abonados del router](#3-qué-necesitan-los-abonados-del-router)
4. [Crear las VMs de los abonados](#4-crear-las-vms-de-los-abonados)
5. [Configurar los abonados](#5-configurar-los-abonados)
6. [Verificar la conexión](#6-verificar-la-conexión)
7. [Integración con el router oficial](#7-integración-con-el-router-oficial)
8. [Pruebas de tráfico](#8-pruebas-de-tráfico)
9. [Problemas que tuvimos y cómo se resolvieron](#9-problemas-que-tuvimos-y-cómo-se-resolvieron)
10. [Pendientes](#10-pendientes)
11. [Terminado cuando](#11-terminado-cuando)

---

## 1. Qué hace esta parte

Simula **dos clientes del ISP** (abonado1 y abonado2). Cada uno es un MikroTik CHR que se conecta al router por **PPPoE** sobre la **VLAN 100**, recibe una IP del pool y genera tráfico. También corre las **pruebas de falla** (qué pasa si se cae el RADIUS, si se conecta moroso, etc.).

Los abonados **nunca hablan con el RADIUS**: solo hablan con el router. Por eso **la configuración de los abonados no cambia** cuando el router pasa de usuarios locales a RADIUS. Esa es la clave de la integración.

---

## 2. Archivos de esta carpeta

| Archivo | Qué es |
|---|---|
| `README.md` | Esta receta |
| `abonado1.rsc` | Configuración de abonado1, comentada, lista para importar en un CHR nuevo |
| `abonado2.rsc` | Igual, para abonado2 |
| `laboratorio/isp-router-prueba.rsc` | El router **de prueba** que usó la parte 4 (con usuarios locales). **No es el router oficial** (ese está en `mikrotik/`): sirve para probar los abonados sin RADIUS y como referencia |
| `export/` | Los `/export` reales de las VMs, tal como quedaron. Respaldo y evidencia |
| `pruebas.md` | Resultados de las pruebas hechas y tabla de pruebas de falla |

---

## 3. Qué necesitan los abonados del router

Esto es el "contrato" entre la parte 4 y la parte 3. Si el router cumple esto, los abonados conectan.

| Qué | Valor | Por qué |
|---|---|---|
| Red de acceso | Adaptador conectado a la red interna `isp-acceso` → `ether2` | Es el "cable" que comparten con los abonados |
| VLAN | **ID 100** sobre `ether2` | Los abonados mandan sus paquetes con la etiqueta 100. Si el número no coincide, no hay conexión y **ningún log dice "VLAN"** |
| Servidor PPPoE | Escuchando **en la interfaz VLAN**, no directamente en `ether2` | Si escucha en `ether2`, no ve los paquetes etiquetados |
| Pool | `100.64.1.10` a `100.64.1.100` | De acá salen las IPs de los abonados |
| local-address | `100.64.1.1` | La IP del router dentro de cada conexión PPPoE |
| Planes | `plan-10m` con `rate-limit=256k/512k` · `plan-50m` con `rate-limit=512k/768k` | Mismos nombres y valores que los grupos de la base. El formato es **subida/bajada del abonado**: abonado1 sube a 256k y baja a 512k |
| Usuarios | `abonado1`/`clave1` (`plan-10m`) · `abonado2`/`clave2` (`plan-50m`) · `moroso`/`clave3` (rechazado) | Primero como `/ppp secret`, después desde el RADIUS |
| Servidor de bandwidth-test | `/tool bandwidth-server` encendido (viene así de fábrica) | Para las pruebas de tráfico |

**Con RADIUS:** la velocidad la manda el RADIUS en el atributo `Mikrotik-Rate-Limit`, con los valores de la tabla `radgroupreply` de la base: `256k/512k` para el grupo `plan-10m` y `512k/768k` para `plan-50m` (nico lo comprobó con `radtest`). El router crea la cola igual que con un perfil local. Por eso los perfiles locales usan los mismos valores: así la velocidad no cambia al pasar de usuarios locales a RADIUS.

---

## 4. Crear las VMs de los abonados

### 4.1 La VM base

1. Bajar la imagen **VDI** de **CHR 7.20.4** desde mikrotik.com → Downloads.
2. En VirtualBox, **Máquina → Nueva**:
   - Nombre: `chr-base` · Tipo: `Linux` · Versión: `Other Linux (64-bit)`
   - Memoria: `256 MB` · Procesadores: `1` · EFI: **desactivado**
   - Disco: **usar un archivo existente** → el `.vdi`.
3. **Configuración → Red**:

| Adaptador | Conectado a | Nombre | Será |
|---|---|---|---|
| 1 | Adaptador solo-anfitrión | el de gestión | `ether1` |
| 2 | Red interna | `isp-acceso` (escrito exacto) | `ether2` |

4. ⚠️ **No arrancar `chr-base`.** Ver el problema 9.1: si la base ya arrancó alguna vez, los clones aparecen con las placas mal nombradas.

### 4.2 Clonar

Clic derecho en `chr-base` → **Clonar**:
- Nombre: `abonado1` (y después `abonado2`).
- **Política de MAC: "Generar nuevas direcciones MAC para todos los adaptadores"**. Imprescindible: PPPoE distingue a cada abonado por su MAC; dos abonados con la misma MAC se pisan.
- Tipo: **Clon completo**.

### 4.3 Primer arranque

En la consola de VirtualBox:
1. Usuario `admin`, contraseña vacía (Enter).
2. `n` para no leer la licencia.
3. Poner la contraseña nueva de admin (la que acordó el grupo).

El resto se hace desde **WinBox**: pestaña **Neighbors**, clic en la **MAC** (no en la IP), usuario `admin`. La consola de VirtualBox usa teclado en inglés y los símbolos `/ - =` salen en otras teclas; en WinBox no pasa.

### 4.4 Verificar las placas antes de configurar

```
/interface ethernet print
```

Muestra las placas de red con su nombre y MAC. Tiene que haber **`ether1` y `ether2`**. Comparar las MAC con VirtualBox (Configuración → Red → Adaptador → Avanzado): **adaptador 1 = ether1** y **adaptador 2 = ether2**. VirtualBox muestra la MAC sin separadores (`0800272C383E`) y MikroTik con dos puntos (`08:00:27:2C:38:3E`).

Si aparecen como `ether2`, `ether3`… ver el problema 9.1.

---

## 5. Configurar los abonados

Dos formas, dan el mismo resultado:

**Opción A, importar el archivo:** en WinBox, menú **Files**, arrastrar `abonado1.rsc` y en la terminal:

```
/import file-name=abonado1.rsc
```

`/import` ejecuta, en orden, todos los comandos del archivo. Las líneas que empiezan con `#` son comentarios y se ignoran.

**Opción B, pegar los comandos uno por uno** (cada comando va **en una sola línea**; ver el problema 9.2):

```
/system identity set name=abonado1
/system clock set time-zone-name=America/Argentina/Buenos_Aires time-zone-autodetect=no
/ip dhcp-client remove [find]
/interface vlan add name=vlan-acceso interface=ether2 vlan-id=100
/interface pppoe-client add name=wan-pppoe interface=vlan-acceso user=abonado1 password=clave1 add-default-route=yes disabled=no
```

Para abonado2 cambian `name=abonado2`, `user=abonado2` y `password=clave2`.

### Qué hace cada comando

**`/system identity set name=abonado1`**

| Parte | Qué hace |
|---|---|
| `/system identity` | Sección del nombre del equipo |
| `set name=abonado1` | Le pone el nombre. Aparece en WinBox y en el prompt `[admin@abonado1] >` |

**`/system clock set time-zone-name=America/Argentina/Buenos_Aires time-zone-autodetect=no`**

| Parte | Qué hace |
|---|---|
| `/system clock set` | Configura el reloj |
| `time-zone-name=...` | Zona horaria acordada. Si las máquinas tienen zonas distintas, en Grafana los datos aparecen corridos 3 horas |
| `time-zone-autodetect=no` | RouterOS 7 intenta adivinar la zona por internet; no hay internet, así que lo apagamos |

**`/ip dhcp-client remove [find]`**

| Parte | Qué hace |
|---|---|
| `/ip dhcp-client` | Sección de clientes DHCP (piden una IP automática) |
| `remove [find]` | Borra todos. `[find]` sin condiciones encuentra todos los de la lista |

El CHR trae de fábrica un cliente DHCP. No lo usamos: a la gestión se entra por MAC.

**`/interface vlan add name=vlan-acceso interface=ether2 vlan-id=100`**

| Parte | Qué hace |
|---|---|
| `/interface vlan add` | Crea una interfaz VLAN: una "placa virtual" que viaja adentro de una real |
| `name=vlan-acceso` | Su nombre |
| `interface=ether2` | La placa real por la que viaja (la de `isp-acceso`) |
| `vlan-id=100` | La etiqueta. **Tiene que ser la misma que en el router** |

**`/interface pppoe-client add name=wan-pppoe interface=vlan-acceso user=abonado1 password=clave1 add-default-route=yes disabled=no`**

| Parte | Qué hace |
|---|---|
| `/interface pppoe-client add` | Crea el cliente PPPoE: busca un servidor y se loguea |
| `name=wan-pppoe` | Nombre de la conexión ("WAN": la salida del abonado) |
| `interface=vlan-acceso` | Busca el servidor por la VLAN 100 |
| `user=... password=...` | Las credenciales. El router las verifica (con usuarios locales o preguntándole al RADIUS) |
| `add-default-route=yes` | Al conectar, todo el tráfico del abonado sale por esta conexión |
| `disabled=no` | Lo enciende. Sin esto queda creado pero apagado |

**La velocidad no se configura en el abonado:** la decide el router (o el RADIUS). Igual que en un ISP real, el cliente no elige su plan.

---

## 6. Verificar la conexión

**En el abonado:**

```
/interface pppoe-client monitor wan-pppoe
```

Muestra la conexión en vivo (se sale con **Ctrl+C**). Lo esperado, con lo que obtuvimos:

```
        status: connected
  service-name: isp
       ac-name: isp-router
           mtu: 1492
 local-address: 100.64.1.100
remote-address: 100.64.1.1
```

- `local-address`: la IP que recibió el abonado.
- `remote-address`: la del router (local-address del perfil).
- `ac-name`: el nombre del router al que se conectó.
- `mtu: 1492`: PPPoE agrega 8 bytes de encabezado a cada paquete, por eso es 1492 y no 1500.

```
/ping 100.64.1.1 count=4
```

Ping al router por adentro del túnel PPPoE. Tienen que volver 4 de 4.

**En el router:**

```
/ppp active print
/queue simple print
```

- `/ppp active print`: quién está conectado ahora. `CALLER-ID` es la MAC de `ether2` del abonado; con RADIUS, esa MAC le llega al RADIUS y queda en el accounting.
- `/queue simple print`: las colas de velocidad, creadas solas (flag **D** = dinámica): `<pppoe-abonado1>` con `max-limit=256k/512k` y `<pppoe-abonado2>` con `max-limit=512k/768k` (subida/bajada).

Lo que obtuvimos en el laboratorio:

```
# NAME      SERVICE  CALLER-ID          ADDRESS       UPTIME
0 abonado1  pppoe    08:00:27:02:90:91  100.64.1.100  3m3s
1 abonado2  pppoe    08:00:27:4E:2E:2D  100.64.1.99   23s
```

Las IPs empiezan desde el final del pool (.100, .99): RouterOS reparte así. No es un error.

---

## 7. Integración con el router oficial

Según el plan de trabajo (sección 9), **cada uno integra en su propia PC**: clona el repo, arma las 4 VMs igual y conecta las piezas en el mismo orden. Esta sección es la parte de ese recorrido que toca a los abonados.

Se hace **de a un cambio por vez**. Si algo falla, **mirar el log de las dos puntas antes de tocar nada** (`/log print` en el router y en el abonado). Si hay que corregir algo de otra parte, se le avisa a su responsable en vez de cambiarlo por cuenta propia.

### Etapa 1 · Abonados ↔ router oficial, con usuarios locales

Objetivo: comprobar que el router oficial (`mikrotik/`) cumple el "contrato" de la sección 3, sin RADIUS de por medio.

1. En tu VM `isp-router`, cargar la configuración oficial de `mikrotik/` (subirla por WinBox → **Files** y `/import file-name=...`).
2. Arrancar los dos abonados (configurados como en la sección 5).
3. Si el router todavía no los tiene, crear los usuarios locales:
   ```
   /ppp secret add name=abonado1 password=clave1 service=pppoe profile=plan-10m
   /ppp secret add name=abonado2 password=clave2 service=pppoe profile=plan-50m
   ```
   `/ppp secret add` crea un usuario PPP en el propio router; `profile` le asigna el plan.
4. Verificar como en la sección 6: los dos en `/ppp active print` y sus colas en `/queue simple print`.

✅ **Prueba de que anda:** los dos abonados conectados, con IP 100.64.1.x y la cola de su plan.

### Etapa 2 · Router ↔ RADIUS (paso 3 del plan de integración)

La configuración del cliente RADIUS en el router es de nacho y la de FreeRADIUS es de nico. **En los abonados no se toca nada.**

1. Con `isp-servicios` levantada y el RADIUS respondiendo, **borrar los usuarios locales** del router, para estar seguros de que la respuesta viene del RADIUS:
   ```
   /ppp secret remove [find]
   ```
2. Forzar que los abonados se reconecten. En cada abonado:
   ```
   /interface pppoe-client disable wan-pppoe
   /interface pppoe-client enable wan-pppoe
   ```
   `disable` corta la conexión y `enable` la vuelve a levantar, así el router tiene que autenticar de nuevo, ahora contra el RADIUS.
3. Verificar como en la sección 6. Además, en el router:
   ```
   /log print where topics~"radius|pppoe"
   ```
   Muestra solo las líneas del log cuyo "tema" incluye radius o pppoe.

✅ **Prueba de que anda:**
- abonado1 y abonado2 conectan **sin** usuarios locales.
- `/queue simple print` muestra `256k/512k` y `512k/768k`: **la velocidad la mandó el RADIUS**.
- **moroso es rechazado** (se prueba con el cliente extra de moroso; ver Pendientes).

### Etapa 3 · Abonados navegando (paso 4 del plan)

1. Generar tráfico desde los abonados (sección 8).
2. Mirar la tabla `radacct` en `isp-servicios`:
   ```
   docker exec isp-postgres psql -U radius -d radius -c "SELECT username, acctupdatetime, acctinputoctets, acctoutputoctets FROM radacct ORDER BY radacctid;"
   ```
   Muestra, por cada sesión, el usuario, la hora de la última actualización y los bytes que subió (`input`) y bajó (`output`). Ojo: la base trae **sesiones inventadas** para probar Grafana (`04-datos-prueba-sinteticos.sql`); las reales son las que se actualizan cada minuto.

✅ **Prueba de que anda:** las filas de abonado1 y abonado2 se actualizan **cada minuto** (interim-update) y sus contadores suben mientras hay tráfico.

### Etapa 4 · Pruebas de falla (paso 6 del plan)

Se corren las pruebas de `pruebas.md` sobre el sistema completo y se anota qué pasó de verdad.

---

## 8. Pruebas de tráfico

Usamos `bandwidth-test`, la herramienta de MikroTik: manda datos "a lo bruto" contra otro MikroTik y mide la velocidad. El otro extremo es el router, que trae el servidor de pruebas encendido de fábrica.

**En el router**, comprobar que está encendido:

```
/tool bandwidth-server print
```

Tiene que decir `enabled: yes` y `authenticate: yes` (pide usuario y contraseña **del router**, no los del PPPoE).

**En el abonado:**

```
/tool bandwidth-test address=100.64.1.1 user=admin password=CLAVE_ADMIN_ROUTER protocol=tcp direction=receive duration=30s
```

| Parte | Qué hace |
|---|---|
| `/tool bandwidth-test` | Arranca la prueba |
| `address=100.64.1.1` | Contra el router, por adentro del túnel PPPoE |
| `user=... password=...` | Credenciales **del router** (las pide el servidor de pruebas) |
| `protocol=tcp` | TCP se adapta solo a la velocidad disponible; es lo más parecido a una descarga real |
| `direction=receive` | El abonado **recibe**: mide la **bajada**. Con `transmit` mide la **subida** |
| `duration=30s` | Dura 30 segundos |

Mientras corre, en WinBox del router, ventana **Queues**, se ve la cola del abonado moviéndose en vivo.

### Resultados

| Prueba | Plan | Medido |
|---|---|---|
| abonado1 bajada | 512k | 497 kbps (97 %) |
| abonado1 subida | 256k | 240,7 kbps (94 %) |
| abonado2 bajada | 768k | 746 kbps (97 %) |
| abonado2 subida | 512k | 486 kbps (95 %) |
| **Los dos juntos, bajada** | 512k + 768k = 1280k | 351 + 606 = **≈ 957 kbps** |
| Los dos juntos, subida | 256k + 512k = 768k | 240,7 + 486,7 = **≈ 727 kbps**: cada uno llega a su plan |

Las bajadas se midieron el 19-nov con perfiles de 512k/512k y 768k/768k; las subidas, el 20-nov con los planes ya alineados. Al alinear los planes con la base cambió solo la subida, así que las bajadas siguen valiendo.

- **Por qué da 95-97 % y no 100 %:** el límite del plan cuenta todo lo que pasa por el cable, incluidos los encabezados de PPPoE, IP y TCP. El bandwidth-test mide solo los datos útiles.
- **Por qué juntos no llegan al bajar:** la licencia gratuita del CHR limita a **1 Mbps lo que manda cada interfaz**. Al bajar, la que manda es la `ether2` del router, una sola para los dos abonados, que no puede pasar de ~1 Mbps: los abonados se reparten ese "caño". Descartamos la CPU como causa porque no pasó del 16 %.
- **Por qué al subir sí llegan:** cada abonado manda por su propia `ether2`, con su propio límite, y el router solo recibe. Juntos suman 768k y cada uno llega a su plan.
- **Decisión del grupo (opción B):** mantener los planes y explicar el límite en la presentación. Si en la demo los dos **bajan** a la vez, en Grafana se va a ver que se reparten ~1 Mbps. Al **subir**, juntos suman 768k, así que deberían entrar los dos.

---

## 9. Problemas que tuvimos y cómo se resolvieron

### 9.1 Las placas aparecieron como `ether2`, `ether3`, `ether4`

**Síntoma:** después de clonar, `/interface ethernet print` mostraba `ether2`-`ether4` en vez de `ether1`-`ether3`.

**Causa:** la `chr-base` ya se había arrancado antes. RouterOS asocia cada nombre de placa a su MAC; al clonar con MACs nuevas, ve placas "desconocidas" y les da el siguiente nombre libre.

**Solución:** confirmar con las MAC de VirtualBox qué placa es cada adaptador y renombrar **eligiéndolas por MAC**, en orden (primero la que va a `ether1`, así se libera el nombre siguiente):

```
/interface ethernet set [find mac-address=08:00:27:XX:XX:XX] name=ether1
/interface ethernet set [find mac-address=08:00:27:YY:YY:YY] name=ether2
```

| Parte | Qué hace |
|---|---|
| `set` | Modifica algo que ya existe |
| `[find mac-address=...]` | Elige la placa que tiene esa MAC; así no hay forma de renombrar la equivocada |
| `name=ether1` | El nombre nuevo |

Quedó además un cliente DHCP apuntando a la placa vieja, que ya no existía (en el `/export` aparecía como `interface=*2`, "Interface not active"). Se borró con `/ip dhcp-client remove [find]`.

**Cómo evitarlo:** clonar desde una base que **nunca** se haya arrancado.

### 9.2 Comando partido en dos

**Síntoma:** `expected end of command (line 1 column 9)` y después `failure: already have interface with such name`.

**Causa:** el comando del cliente PPPoE se pegó en dos partes. La primera mitad era un comando válido y **creó** `wan-pppoe` sin contraseña y apagada. La segunda mitad suelta no es un comando (no empieza con `/`). Al pegar el comando entero, falló porque `wan-pppoe` ya existía.

**Solución:** completar la interfaz existente con `set`, en lugar de crearla de nuevo con `add`:

```
/interface pppoe-client set wan-pppoe password=clave1 add-default-route=yes disabled=no
```

Y verificar con `/interface pppoe-client print detail`, que muestra todas las opciones.

**Regla:** cada comando va en **una sola línea**. Antes de repetir un `add`, revisar con `print` qué quedó creado.

### 9.3 Límite de 1 Mbps de la licencia

Ver la sección 8.

### 9.4 Los planes no coincidían con la base

**Síntoma:** al revisar el repo el 20-nov, la base de la parte 1 tenía `plan-10m` = `256k/512k` y `plan-50m` = `512k/768k`, pero el router de prueba de esta parte usaba `plan-512k` = `512k/512k` y `plan-768k` = `768k/768k`. `radtest` (parte 2) confirmó que el RADIUS manda los valores de la base.

**Por qué importa:** con el RADIUS, la velocidad la decide la base. Con perfiles distintos, el abonado cambiaría de velocidad al pasar de usuarios locales a RADIUS y las pruebas no coincidirían. Además, con otros nombres de perfil los comandos de la receta fallarían en el router oficial.

**Solución:** se alinearon los perfiles del router de prueba (mismos nombres y valores que la base) y se repitieron solo las pruebas de subida: 240,7k (abonado1) y 486k (abonado2), los dos dentro de su plan. En el router:

```
/ppp profile set plan-512k name=plan-10m rate-limit=256k/512k
/ppp profile set plan-768k name=plan-50m rate-limit=512k/768k
```

`set` modifica el perfil que ya existe: le cambia el nombre y la velocidad. Los usuarios y el servidor PPPoE que lo usan se actualizan solos. Después hay que reconectar los abonados para que tomen la cola nueva.

---

## 10. Pendientes

- [ ] **Usuario de pruebas en el router** (`btest`, grupo de solo lectura), para no guardar la clave de `admin` en los abonados. Hay que proponérselo a nacho para la configuración oficial.
- [ ] **Script de tráfico + `/system scheduler`** en cada abonado, para que el tablero tenga movimiento en la demo.
- [ ] **Cliente PPPoE extra para `moroso`** en abonado1, apagado, para mostrar el rechazo sin tocar la conexión normal.
- [ ] **Pruebas de falla** (ver `pruebas.md`).

---

## 11. Terminado cuando

- [x] Los dos abonados se conectan a la vez y reciben una IP 100.64.1.x.
- [x] Se puede generar tráfico a demanda y se ve el límite de cada plan (subida y bajada medidas con los planes de la base).
- [ ] Las pruebas de falla están hechas y anotadas en `pruebas.md`.
- [x] La configuración exportada está en esta carpeta y las notas están al día.
