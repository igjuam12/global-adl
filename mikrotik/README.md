# Parte 3 · Router (MikroTik)

**Responsable:** Nacho · **Notas:** [`../notas/nacho.md`](../notas/nacho.md)

RouterOS **7.20.4** · Planes: **abonado1 512k/512k · abonado2 768k/768k**

El router `isp-router` cumple tres papeles:

| Papel | Qué hace | Con quién habla |
| --- | --- | --- |
| Servidor PPPoE | Atiende a los abonados: les pide usuario y clave y recién ahí les da una IP | Los abonados, por la VLAN 100 |
| Cliente RADIUS | No decide solo: le pregunta a FreeRADIUS si deja entrar a cada abonado y con qué velocidad, y le informa el consumo | FreeRADIUS (10.10.50.10) |
| Fuente de datos | Deja leer su CPU y memoria y manda sus logs | El monitoreo de la parte 5 (10.10.50.20) |

Cómo encaja con el resto del proyecto: [`../arquitectura.md`](../arquitectura.md).

---

## 1. Archivos de esta carpeta

La configuración está partida en tres archivos, uno por etapa. Se importan en orden y **una sola vez** cada uno.

| Archivo | Etapa | Qué deja andando | Depende de |
| --- | --- | --- | --- |
| `01-base-pppoe.rsc` | 1 | PPPoE con usuarios guardados en el router, hora por NTP, usuario de pruebas y protección mínima | Nada |
| `02-radius.rsc` | 2 | El router le pregunta a FreeRADIUS y le manda el accounting. Borra los usuarios locales | FreeRADIUS respondiendo (parte 2) |
| `03-monitoreo.rsc` | 3 | SNMP para las métricas y syslog para los logs | El monitoreo (parte 5), en `isp-monitoreo` |
| `export/` | — | Los `/export` del router real, como respaldo y evidencia | — |

Cada comando está explicado con un comentario en el propio archivo.

---

## 2. Armar la VM

Igual que los abonados ([`../abonados/README.md`](../abonados/README.md), sección 4), con un adaptador más:

| Adaptador | Conectado a | Será |
| --- | --- | --- |
| 1 | Adaptador solo-anfitrión | `ether1` (gestión) |
| 2 | Red interna `isp-acceso` | `ether2` (abonados) |
| 3 | Red interna `isp-servicios` | `ether3` (hacia las dos VMs Debian: RADIUS y monitoreo) |

- Clonar de una base que **nunca se arrancó**, con MACs nuevas. Si la base ya arrancó, las placas aparecen corridas (`ether2`, `ether3`, `ether4`).
- Antes de importar nada, confirmar con `/interface ethernet print` que están `ether1`, `ether2` y `ether3`, y que sus MAC coinciden con las de VirtualBox.

---

## 3. Cargar la configuración

En WinBox (se entra por MAC, usuario `admin`): menú **Files**, arrastrar el archivo y en la terminal:

```
/import file-name=01-base-pppoe.rsc
```

Tiene que contestar `Script file loaded and executed successfully`. Las etapas 2 y 3 se cargan igual, cuando el servidor ya esté arriba.

**Ojo:** el archivo 01 deshabilita el cliente DHCP de `ether1`, y el router se queda sin IP en la gestión. Si estabas conectado por IP, la sesión se corta; por MAC no pasa nada. Se deshabilita en vez de borrarlo porque a los abonados la CHR se los volvía a crear al reiniciar ([`abonados/README.md`](../abonados/README.md), sección 5).

---

## 4. Etapa 1 · PPPoE con usuarios locales

Es lo mismo que la Práctica 6 de Redes, con los datos del proyecto.

| Pieza | Para qué sirve | Valor |
| --- | --- | --- |
| Cliente NTP | Tomar la hora del servidor | 10.10.50.10 |
| Servidor NTP | Darles la hora a los abonados, que no pueden llegar al servidor | Contesta en 100.64.1.1 |
| VLAN `vlan-acceso` | El "pasillo" por donde llegan los abonados | VLAN 100 sobre `ether2` |
| Pool `pool-abonados` | Las IPs que se reparten | 100.64.1.10 a 100.64.1.100 |
| Perfil `pppoe-base` | De dónde sale la IP del abonado y cuál usa el router | Router 100.64.1.1, **sin velocidad** |
| Perfiles `plan-512k` y `plan-768k` | Los planes, para los usuarios locales | 512k/512k y 768k/768k |
| Servidor PPPoE `isp` | El "molinete": pide usuario y clave | Escucha en `vlan-acceso` |
| Secrets `abonado1` y `abonado2` | Usuarios guardados en el router. **Temporales** | `clave1` y `clave2` |
| Usuario `btest` | Para el bandwidth-test de los abonados | Clave `BtestIsp2026` |

**Por qué el perfil por defecto no tiene velocidad.** Con RADIUS, lo que el servidor no manda se toma del perfil por defecto. Si ese perfil tuviera 512k, abonado1 mostraría 512k aunque el RADIUS no mandara nada, y no se podría saber quién puso la velocidad. Sin velocidad en el perfil, si aparece la cola es porque la dictó el RADIUS. Lo comprobamos de las dos formas en la etapa 2: con `pppoe-base` sin velocidad las colas salieron de 512k y 768k, y un usuario de prueba sin plan entró pero quedó **sin cola**.

### Cómo verificar

En el router:

```
/ppp active print
/queue simple print
```

Resultado obtenido (jue 19-nov, router vuelto a fábrica y abonados de la parte 4 sin modificar):

```
# NAME      SERVICE  CALLER-ID          ADDRESS       UPTIME
0 abonado1  pppoe    08:00:27:B2:56:4D  100.64.1.100  47s
1 abonado2  pppoe    08:00:27:F0:FF:26  100.64.1.99   33s

0  D name="<pppoe-abonado1>" ... max-limit=512k/512k
1  D name="<pppoe-abonado2>" ... max-limit=768k/768k
```

En un abonado, con el usuario de pruebas (ya no hace falta la clave de `admin`):

```
/tool bandwidth-test address=100.64.1.1 user=btest password=BtestIsp2026 protocol=tcp direction=receive duration=20s
```

| Prueba | Plan | Medido |
| --- | --- | --- |
| abonado1 bajada | 512k | 499 kbps |
| abonado2 bajada | 768k | 748 kbps |

La subida no la medimos bien desde acá; la parte 4 midió 487 y 734 kbps.

---

## 5. Etapa 2 · RADIUS

| Pieza | Para qué sirve | Valor |
| --- | --- | --- |
| `/radius` | A quién preguntarle y con qué secreto | 10.10.50.10, secreto `IspUtnRadius2026`, el router sale como 10.10.50.1 |
| `/ppp aaa` | Usar RADIUS y mandar el accounting | `use-radius=yes`, `interim-update=1m` |
| `/radius incoming` | Aceptar lo que manda el RADIUS: corte (Disconnect) y cambio de velocidad (CoA) | Puerto 3799/udp |
| Regla de log `radius` | Ver el diálogo con el RADIUS en el log | En memoria, sin el contenido de los paquetes |
| `/ppp secret remove [find]` | Borrar los usuarios locales | — |

**Por qué se borran los usuarios locales.** RouterOS busca primero en sus propios usuarios y recién si no encuentra al abonado le pregunta al RADIUS. Mientras existan, la respuesta nunca viene del RADIUS.

**Por qué `timeout=3s`.** De fábrica son 300 ms, poco para un servidor que antes de contestar consulta una base de datos.

### Cómo verificar

```
/ppp active print
/radius monitor 0 once
/log print where topics~"radius|pppoe"
```

Resultado obtenido con FreeRADIUS andando. La **R** indica que al abonado lo validó el RADIUS:

```
#   NAME      SERVICE  CALLER-ID          ADDRESS       UPTIME
0 R abonado1  pppoe    08:00:27:B2:56:4D  100.64.1.100  47s
1 R abonado2  pppoe    08:00:27:F0:FF:26  100.64.1.99   31s

requests: 6    accepts: 6    rejects: 0    timeouts: 0
```

Y en el log, el diálogo completo:

```
radius,debug new request code=Access-Request service=ppp called-id=isp
radius,debug tx to 10.10.50.10:1812 code=Access-Request id=1 service=ppp
radius,debug rx reply code=Access-Accept service=ppp
radius,debug tx to 10.10.50.10:1813 code=Accounting-Request id=2 service=ppp
radius,debug rx reply code=Accounting-Response service=ppp
```

### Lo que el RADIUS le manda al router

Probado con el comando de operación del servidor (`servidor/isp`):

| Acción | Mensaje | Qué hizo el router |
| --- | --- | --- |
| `isp plan abonado1 plan-768k` | CoA con la velocidad nueva | Confirmó (ACK) y la cola pasó a 768k/768k **sin cortar la sesión** |
| `isp suspender abonado2` | Disconnect | Confirmó (ACK) y la sesión desapareció; cada reintento fue rechazado |

Si el pedido llega mal firmado, el router lo descarta y lo dice: `received remote request from 10.10.50.10 with bad signature (check your secret!), dropping`.

### Qué se ve si el RADIUS no responde

```
radius,debug tx to 10.10.50.10:1812 code=Access-Request id=4 service=ppp
radius,debug server timeout code=Access-Request id=4 service=ppp
radius,debug resending
radius,debug server timeout code=Access-Request id=4 service=ppp
radius,debug resending
radius,debug server timeout code=Access-Request id=4 service=ppp
pppoe,ppp,error <0004>: user abonado2 authentication failed - radius timeout
```

- El router prueba **3 veces, 3 segundos cada una**, y recién ahí rechaza al abonado.
- **El que ya estaba conectado sigue conectado y navegando.**
- Con un secreto distinto el router ve exactamente lo mismo; la diferencia está en el log de FreeRADIUS.

Todas las pruebas de falla están en [`../abonados/pruebas.md`](../abonados/pruebas.md).

---

## 6. Etapa 3 · Datos para Grafana

Los valores salen de la parte 5 ([`../notas/igna.md`](../notas/igna.md)). El monitoreo vive en `isp-monitoreo` (10.10.50.20), una VM aparte de la del RADIUS: si se cae la de servicios, el tablero sigue recibiendo los datos del router.

| Dato | Quién inicia | Pieza en el router | Valor |
| --- | --- | --- | --- |
| CPU, memoria, interfaces | El exportador SNMP de isp-monitoreo pregunta cada 15 s, a pedido de Prometheus (SNMP, 161/udp) | `/snmp community` | `lab-monitoreo`, solo lectura, solo desde 10.10.50.20 |
| Logs | El router los manda cuando ocurren (syslog) | `/system logging action` | A 10.10.50.20, puerto 1514/udp |

La comunidad `public` que trae RouterOS queda apagada.

Probado contra el monitoreo real: las métricas llegan a Prometheus y los logs a Loki. Así sale un log del router:

```
<30>Nov 19 17:45:00 isp-router prueba de formato: linea escrita a mano
<28>Nov 19 17:45:02 isp-router prueba de formato: advertencia
<27>Nov 19 17:45:03 isp-router prueba de formato: error
```

- Es syslog clásico (RFC 3164), el que espera Alloy. El número entre `< >` lleva la severidad: 30 = info, 28 = warning, 27 = error.
- La hora va en **hora local y sin zona horaria**. El recolector usa la hora de llegada y no la del mensaje, así que no hay corrimiento.
- El mensaje no trae los "topics" de RouterOS (`pppoe`, `system`, etc.), solo el texto.

---

## 7. Protección

Cuatro cosas, todas en `01-base-pppoe.rsc`:

| Qué se cerró | Cómo | Cómo lo probamos |
| --- | --- | --- |
| Los abonados no llegan a la red de servicios | Regla `forward` que descarta lo que entra por una conexión PPPoE y va a 10.10.50.0/24 | `ping 10.10.50.10` desde los dos abonados: 4 paquetes descartados en el contador |
| Los abonados no llegan a la administración del router por IP | Regla `input` que descarta ftp, ssh, telnet, web, WinBox y API desde las conexiones PPPoE | `/tool fetch` a `http://100.64.1.1/` no conecta: 6 paquetes descartados |
| WinBox por MAC y el anuncio a vecinos, solo por gestión | Lista de interfaces `gestion` con `ether1` | Desde un abonado, `/ip neighbor print` ya no muestra al router por `ether2` ni por la VLAN |
| El usuario de pruebas no puede administrar | Grupo `solo-pruebas` con lo mínimo | Ver problema 8.1 |

Se ven con `/ip firewall filter print stats`.

Lo que **no** está cerrado: un abonado puede hacerle ping a 10.10.50.1, porque es una IP del propio router. Y la red de gestión une a las tres VMs MikroTik, pero no es parte del ISP simulado. Mientras `admin` no tenga clave, por ahí se puede entrar al router.

---

## 8. Problemas que tuvimos y cómo se resolvieron

### 8.1 El usuario `btest` no podía autenticar

**Síntoma:** `status: authentication failed` en el bandwidth-test, con la clave correcta.

**Diagnóstico:** el log del router decía `system,error,critical login failure for user btest via bandwidth-test`. Con el mismo usuario en los grupos de fábrica `full` y `read` la prueba funcionaba, así que era un tema de permisos. Probamos los permisos del grupo `read` por mitades hasta encontrar cuál faltaba.

**Causa:** el bandwidth-test exige el permiso `test` **y además `winbox`**. Con `test` solo, falla.

**Solución:** grupo `solo-pruebas` con `test,winbox`. Como `winbox` permitiría entrar al router, se cerró la administración desde la red de abonados (sección 7).

### 8.2 El reloj del router estaba corrido

**Síntoma:** en la base, las sesiones figuraban empezando en el futuro. El tablero calculaba duraciones negativas.

**Diagnóstico:** comparamos `/system clock print` del router con la hora del servidor: 46 minutos de diferencia. Después de un reinicio fue peor; el propio router lo registró al corregirse: `ntp change time Nov/19/2026 23:42:58 => Nov/19/2026 20:37:19`.

**Causa:** el router confiaba en su propio reloj, y en la VM ese reloj arranca mal.

**Solución:** el servidor da la hora por NTP y el router es su cliente (`/system ntp client`, en `01-base-pppoe.rsc`). Además, el tablero usa el reloj de la base y no la hora que informa el router.

### 8.3 El nombre del destino de logs

**Síntoma:** `failure: action name can contain only letters and numbers` al crear el destino con un guion en el nombre.

**Solución:** nombre sin guiones (`recolector`).

### 8.4 `/export` no guarda los usuarios

El usuario `btest` no aparece en el `/export`. Por eso la configuración se reparte como archivos por etapa y no como un export: con el export solo, los demás quedarían sin usuario de pruebas.

### 8.5 Placas corridas al clonar

Lo mismo que el problema 9.1 de la parte 4: clonar de una base que ya arrancó deja las placas como `ether2`, `ether3`. Con una base que nunca arrancó salen en orden.

### 8.6 Un bandwidth-test del router contra sí mismo lo reinició

Buscando una forma de cargar la CPU probamos `/tool bandwidth-test address=127.0.0.1`. El router se reinició solo (`router was rebooted without proper shutdown`). No usarlo. Lo bueno: se recuperó sin tocar nada (ver la prueba "se reinicia el router").

---

## 9. Para la demo: cómo cargar la CPU

El tráfico de los abonados casi no mueve la CPU del router (5 % como máximo), porque la licencia no deja pasar más de 1 Mbps. Para ver reaccionar el panel de CPU sirve un bucle de cálculo, que tarda cerca de un minuto y no rompe nada:

```
:for i from=1 to=30000000 do={ :local x ($i * $i) }
```

Con 10 millones de vueltas tardó 18 segundos y el panel marcó 23 %.

---

## 10. Pendientes

- [ ] **Entrar por WinBox y ponerle clave a `admin`** en las tres VMs MikroTik. Hoy está sin clave.
- [ ] **Avisar a la parte 4** que las pruebas se pueden correr con `user=btest password=BtestIsp2026`.
- [ ] **Acordar con el grupo** el nombre de la comunidad SNMP (usamos `lab-monitoreo`, el que propuso la parte 5).

---

## 11. Terminado cuando

- [x] Los dos abonados se conectan por PPPoE con usuarios locales y aparecen en `/ppp active print`.
- [x] Con los usuarios locales borrados, los abonados entran gracias al RADIUS y `moroso` es rechazado.
- [x] El accounting llega cada minuto (`interim-update`).
- [x] CPU, memoria y logs se pueden leer desde la VM de monitoreo (junto con la Parte 5).
- [ ] La configuración exportada está en esta carpeta y las notas están al día.
