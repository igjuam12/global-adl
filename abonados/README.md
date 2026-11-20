# Parte 4 · Abonados y pruebas

**Responsable:** Rodri · **Notas:** [`../notas/rodri.md`](../notas/rodri.md)

Receta de armado e integración. Para **nacho** (router) y el resto del grupo.
RouterOS **7.20.4** · Planes acordados: **abonado1 512k/512k · abonado2 768k/768k** (opción B)

Esta receta explica cómo armar los dos abonados desde cero, qué tiene que tener el router para que se conecten, y cómo integrarlos con el router real paso a paso. Cada comando tiene su explicación, porque en la presentación nos pueden preguntar cualquier línea a cualquiera.

---

## Índice

1. [Qué hace esta parte](#1-qué-hace-esta-parte)
2. [Archivos de esta carpeta](#2-archivos-de-esta-carpeta)
3. [Qué necesitan los abonados del router](#3-qué-necesitan-los-abonados-del-router)
4. [Crear las VMs de los abonados](#4-crear-las-vms-de-los-abonados)
5. [Configurar los abonados](#5-configurar-los-abonados)
6. [Verificar la conexión](#6-verificar-la-conexión)
7. [Integración con el router real](#7-integración-con-el-router-real)
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
| `trafico.rsc` | Tráfico automático, para que el tablero tenga movimiento. Se carga en los dos abonados, después del archivo de cada uno |
| `moroso.rsc` | Una segunda conexión PPPoE con el usuario `moroso`, apagada. Se carga solo en abonado1, para mostrar el rechazo sin tocar la conexión normal |
| `laboratorio/isp-router-prueba.rsc` | El router **de prueba** que usó la parte 4 (con usuarios locales). **No es el router oficial**: sirve como referencia para nacho |
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
| Usuarios | `abonado1`/`clave1` (512k/512k) · `abonado2`/`clave2` (768k/768k) · `moroso`/`clave3` (rechazado) | Primero como `/ppp secret`, después desde el RADIUS |
| Servidor de bandwidth-test | `/tool bandwidth-server` encendido (viene así de fábrica) | Para las pruebas de tráfico |
| Usuario de pruebas | `btest` / `BtestIsp2026` | El bandwidth-test pide un usuario del router. Con este no hace falta guardar la clave de `admin` en los abonados. Lo crea el router oficial (`mikrotik/01-base-pppoe.rsc`) |

**Con RADIUS:** la velocidad la manda el RADIUS en el atributo `Mikrotik-Rate-Limit` con los valores `512k/512k` y `768k/768k` (esto es de la parte 2, nico). El router crea la cola igual que con un perfil local. En la base, los planes son los grupos `plan-512k` y `plan-768k`.

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

### Archivos extra

Después del archivo del abonado se cargan igual, con `/import`:

| Archivo | En cuál | Qué agrega |
|---|---|---|
| `trafico.rsc` | Los dos | Un script (`generar-trafico`) que baja datos del router 30 segundos y después le sube 20, con el usuario `btest`. Y un scheduler (`trafico`), el cron de RouterOS, que lo corre cada 2 minutos en abonado1 y cada 3 en abonado2 |
| `moroso.rsc` | Solo abonado1 | El cliente PPPoE `wan-moroso` (usuario `moroso`, clave `clave3`), apagado y sin ruta por defecto |

```
/system scheduler disable trafico
/system scheduler enable trafico
```

`disable` frena el tráfico automático y `enable` lo sigue. **Conviene frenarlo antes de las pruebas de falla:** con la cola del plan llena, hasta un `ping` al router se pierde y parece que el abonado no navega.

```
/interface pppoe-client enable wan-moroso
/interface pppoe-client disable wan-moroso
```

`enable` hace que `moroso` intente entrar (y lo rechacen); `disable` lo deja apagado otra vez.

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
- `/queue simple print`: las colas de velocidad, creadas solas (flag **D** = dinámica): `<pppoe-abonado1>` con 512k/512k y `<pppoe-abonado2>` con 768k/768k.

Lo que obtuvimos en el laboratorio:

```
# NAME      SERVICE  CALLER-ID          ADDRESS       UPTIME
0 abonado1  pppoe    08:00:27:02:90:91  100.64.1.100  3m3s
1 abonado2  pppoe    08:00:27:4E:2E:2D  100.64.1.99   23s
```

Las IPs empiezan desde el final del pool (.100, .99): RouterOS reparte así. No es un error.

---

## 7. Integración con el router real

Se hace **de a un cambio por vez**. Si algo falla, **mirar el log de las dos puntas antes de tocar nada** (`/log print` en el router y en el abonado).

### Etapa 1 · Abonados ↔ router de nacho, con usuarios locales

Objetivo: comprobar que el router de nacho cumple el "contrato" de la sección 3, sin RADIUS de por medio.

1. Arrancar el router de nacho y los dos abonados (configurados como en la sección 5).
2. En el router, si todavía no los tiene, crear los usuarios locales:
   ```
   /ppp secret add name=abonado1 password=clave1 service=pppoe profile=plan-512k
   /ppp secret add name=abonado2 password=clave2 service=pppoe profile=plan-768k
   ```
   `/ppp secret add` crea un usuario PPP en el propio router; `profile` le asigna el plan. Los nombres de los perfiles tienen que ser los que use nacho. El router oficial usa estos mismos (`plan-512k` y `plan-768k`), y `mikrotik/01-base-pppoe.rsc` ya crea los dos usuarios: con ese archivo importado, este paso no hace falta.
3. Verificar como en la sección 6: los dos en `/ppp active print` y sus colas en `/queue simple print`.

✅ **Prueba de que anda:** los dos abonados conectados, con IP 100.64.1.x y la cola de su plan.

### Etapa 2 · Router ↔ RADIUS (paso 3 del plan de integración)

Esto lo configuran nacho (cliente RADIUS en el router) y nico (FreeRADIUS). **En los abonados no se toca nada.**

1. Con el RADIUS ya respondiendo, nacho **borra los usuarios locales**, para estar seguros de que la respuesta viene del RADIUS:
   ```
   /ppp secret remove [find]
   ```
   En el router oficial esto lo hace `mikrotik/02-radius.rsc` al importarse.
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
- `/queue simple print` muestra 512k y 768k: **la velocidad la mandó el RADIUS**.
- **moroso es rechazado** (se prueba con el cliente extra de `moroso.rsc`; ver "Archivos extra" en la sección 5).

### Etapa 3 · Abonados navegando (paso 4 del plan)

1. Generar tráfico desde los abonados (sección 8).
2. Agus verifica que en la tabla `radacct` aparecen filas de abonado1 y abonado2 y que **se actualizan cada minuto** (interim-update).

✅ **Prueba de que anda:** los contadores de bytes de `radacct` suben minuto a minuto mientras hay tráfico.

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
/tool bandwidth-test address=100.64.1.1 user=btest password=BtestIsp2026 protocol=tcp direction=receive duration=30s
```

| Parte | Qué hace |
|---|---|
| `/tool bandwidth-test` | Arranca la prueba |
| `address=100.64.1.1` | Contra el router, por adentro del túnel PPPoE |
| `user=... password=...` | Credenciales **del router** (las pide el servidor de pruebas). En el router oficial es `btest`, un usuario creado solo para esto. El router de prueba de la parte 4 no lo tiene: ahí va `admin` con su clave |
| `protocol=tcp` | TCP se adapta solo a la velocidad disponible; es lo más parecido a una descarga real |
| `direction=receive` | El abonado **recibe**: mide la **bajada**. Con `transmit` mide la **subida** |
| `duration=30s` | Dura 30 segundos |

Mientras corre, en WinBox del router, ventana **Queues**, se ve la cola del abonado moviéndose en vivo.

### Resultados

| Prueba | Plan | Medido |
|---|---|---|
| abonado1 bajada | 512k | 497 kbps (97 %) |
| abonado1 subida | 512k | 487 kbps (95 %) |
| abonado2 bajada | 768k | 746 kbps (97 %) |
| abonado2 subida | 768k | 734 kbps (96 %) |
| **Los dos juntos, bajada** | 512k + 768k = 1280k | 351 + 606 = **≈ 957 kbps** |

- **Por qué da 95-97 % y no 100 %:** el límite del plan cuenta todo lo que pasa por el cable, incluidos los encabezados de PPPoE, IP y TCP. El bandwidth-test mide solo los datos útiles.
- **Por qué juntos no llegan:** la licencia gratuita del CHR limita a **1 Mbps por interfaz**. La `ether2` del router no puede mandar más de ~1 Mbps en total, así que los abonados se reparten ese "caño". Descartamos la CPU como causa porque no pasó del 16 %.
- **Decisión del grupo (opción B):** mantener 512k/768k y explicar el límite en la presentación. Si en la demo los dos generan tráfico a la vez, en Grafana se va a ver que se reparten ~1 Mbps.

**Con el router oficial y el usuario `btest`** (jue 19-nov, en la PC de nacho, pruebas de 20 segundos): 499 kbps de bajada en abonado1 y 748 kbps en abonado2. La subida no quedó bien medida en esa pasada.

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

---

## 10. Pendientes

- [x] **Usuario de pruebas en el router** (`btest`, grupo de solo lectura), para no guardar la clave de `admin` en los abonados. Hay que sumarlo a la configuración de nacho. **Hecho** en `mikrotik/01-base-pppoe.rsc`. No quedó en un grupo de solo lectura sino en uno propio, `solo-pruebas`, con lo mínimo que pide el bandwidth-test.
- [x] **Script de tráfico + `/system scheduler`** en cada abonado, para que el tablero tenga movimiento en la demo. **Hecho:** `trafico.rsc`.
- [x] **Cliente PPPoE extra para `moroso`** en abonado1, apagado, para mostrar el rechazo sin tocar la conexión normal. **Hecho:** `moroso.rsc`. Probado: FreeRADIUS lo rechazó y la conexión normal de abonado1 siguió conectada.
- [ ] **Pruebas de falla** (ver `pruebas.md`). Hechas y anotadas las del sistema completo (tabla 3). De la tabla 2 quedaron sin probar con usuarios locales "contraseña incorrecta" y "cambio de plan"; las dos se probaron con RADIUS (tabla 3).
- [x] **Alinear la subida de los planes con la base:** `postgres/init/02-datos-acordados.sql` (agus) manda `Mikrotik-Rate-Limit` = `256k/512k` (abonado1) y `512k/768k` (abonado2): subida/bajada. La bajada coincide con la de esta parte; la subida no (acá se probó 512k y 768k). Con el RADIUS, manda la base. Charlarlo en el grupo. **Hecho:** la base ahora manda `512k/512k` y `768k/768k`.

---

## 11. Terminado cuando

- [x] Los dos abonados se conectan a la vez y reciben una IP 100.64.1.x.
- [x] Se puede generar tráfico a demanda y se ve el límite de cada plan.
- [ ] Las pruebas de falla están hechas y anotadas en `pruebas.md`. (Dos de la tabla 2 se probaron solo con RADIUS; las del sistema completo están.)
- [x] La configuración exportada está en esta carpeta y las notas están al día.
