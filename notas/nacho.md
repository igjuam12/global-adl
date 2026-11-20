# Notas — Parte 3: Router (MikroTik)

**Responsable:** Nacho

Escribir **mientras** se trabaja, no al final. Es lo que preguntan en la presentación.

> Borrador armado con IA a partir de lo que se hizo el jue 19-nov. Tengo que revisarlo, corregirlo y completar lo que está entre [corchetes] antes de darlo por bueno.

## 1. Qué investigué

Qué es mi pieza y qué papel cumple en el proyecto.

- El router es la pieza del medio. Hacia los abonados es el **servidor PPPoE**: les pide usuario y clave y recién ahí les da una IP. Hacia el servidor es el **cliente RADIUS**: no decide solo, pregunta.
- **El que habla con el RADIUS es el router, no el abonado.** Por eso los abonados no cambian nada cuando el router pasa de usuarios locales a RADIUS.
- RADIUS resuelve tres cosas (AAA): quién sos, qué podés hacer (la velocidad del plan) y cuánto usaste (accounting).
- **RouterOS busca primero en sus usuarios locales** y recién si no encuentra al abonado le pregunta al RADIUS. Por eso hay que borrarlos para demostrar que contesta el RADIUS.
- El accounting son tres avisos del router al RADIUS: al entrar, cada minuto y al salir.
- Hay dos mensajes que van al revés, del RADIUS al router, por el puerto 3799: **Disconnect** (cortar una conexión) y **CoA** (cambiarle algo, por ejemplo la velocidad, sin cortarla).
- Para Grafana hay dos caminos distintos: las métricas las **pide** el servidor (SNMP) y los logs los **manda** el router (syslog).
- [Completar: qué leí yo y dónde: Práctica 6 y 8 de Redes, documentación de MikroTik.]

## 2. Alternativas

Qué opciones había y por qué descarté cada una.

| Opción | Por qué la descarté |
| --- | --- |
| Perfil por defecto del PPPoE con velocidad (por ejemplo 512k) | Con RADIUS, lo que el servidor no manda sale del perfil por defecto. No se podría saber si la velocidad la puso el RADIUS o el perfil |
| Que los abonados usen `admin` en el bandwidth-test | Quedaría la clave de administrador guardada en los abonados |
| Poner al usuario de pruebas en el grupo `read` de fábrica | Ese grupo permite entrar por WinBox y SSH y ver datos sensibles, como el secreto RADIUS |
| Confiar en que los abonados no llegan al servidor porque no tiene ruta de vuelta | Es un aislamiento por accidente. Un paquete UDP no necesita respuesta: un abonado podría mandarle logs falsos al servidor |
| Subir solo el `/export` del router | El export no guarda los usuarios (falta `btest`) y no se puede aplicar por etapas |
| Clonar el `CHR-base` que ya tenía de las prácticas | Ya había arrancado: los clones salen con las placas corridas, como me pasó en la P6 |
| Dejar el timeout del RADIUS en 300 ms (de fábrica) | Es poco para un servidor que antes de contestar consulta una base de datos |
| Que el router confíe en su propio reloj | Lo encontré 46 minutos adelantado, y recién reiniciado arranca con la hora mal |
| Reconectar al abonado para cambiarle la velocidad | Con un CoA el router aplica la velocidad nueva sin cortarle la conexión |
| Dejar el tablero en la misma VM que el RADIUS (lo que decía el plan) | Si esa VM se cae, se cae también el tablero que lo mostraría. Lo separamos en otra VM, `isp-monitoreo` |

## 3. Qué elegí y por qué

- **Tres archivos, uno por etapa** (PPPoE local, RADIUS, monitoreo). Se integra de a un cambio por vez y cada etapa tiene su prueba.
- **Perfil por defecto sin velocidad** (`pppoe-base`) y dos perfiles de plan solo para los usuarios locales. Si aparece la cola con RADIUS, la dictó el servidor.
- **Velocidades 512k/512k y 768k/768k**, las que midió la parte 4, por el tope de 1 Mbps por interfaz de la CHR sin licencia.
- **Usuario `btest` con un grupo propio** que solo tiene lo que el bandwidth-test exige.
- **La hora por NTP**, tomada del servidor.
- **Mínimo privilegio en todo lo que abrí:** SNMP solo desde el servidor, administración solo por la boca de gestión, abonados aislados de la red de servicios.
- [Completar: con mis palabras, por qué me cierra cada una.]

## 4. Qué hice

Los archivos que dejé en el repo y qué hace cada uno.

| Archivo | Qué hace |
| --- | --- |
| `mikrotik/01-base-pppoe.rsc` | Etapa 1: hora por NTP, VLAN 100, pool, perfiles, servidor PPPoE, usuarios locales temporales, usuario `btest` y protección mínima |
| `mikrotik/02-radius.rsc` | Etapa 2: cliente RADIUS, accounting cada minuto, aceptar corte y cambio de velocidad, borrar los usuarios locales |
| `mikrotik/03-monitoreo.rsc` | Etapa 3: SNMP de solo lectura y envío de logs por syslog, hacia la VM de monitoreo |
| `mikrotik/export/` | Los `/export` del router real: con la etapa 1 sola y con las tres |
| `mikrotik/README.md` | La receta: cómo armar la VM, cómo cargar cada etapa y cómo verificarla |

Probado el 19-nov en mi PC, con el router vuelto a fábrica, los abonados de la parte 4 y el servidor completo (creado desde cero con `vagrant up`):

- Los tres archivos importan sin errores.
- **Etapa 1:** los dos abonados conectan con usuarios locales; colas de 512k y 768k. Bajada medida: 499 y 748 kbps.
- **Etapa 2:** los abonados entran validados por el RADIUS (marca `R`), `moroso` es rechazado, y las colas salen con la velocidad que mandó el servidor. Un usuario de prueba sin plan entra pero queda sin cola.
- **Accounting:** llega un aviso por minuto por cada conexión.
- **Corte y cambio de plan:** el router confirmó el Disconnect y el CoA; con el CoA la cola cambió sin cortar la sesión.
- **Etapa 3:** las métricas llegan a Prometheus y los logs a Loki, en la VM de monitoreo (10.10.50.20).
- **Fallas:** RADIUS caído, base caída, secreto distinto, clave incorrecta, reinicio del router y reinicio del servidor. Los resultados están en `abonados/pruebas.md`.

## 5. Qué falló y cómo lo diagnostiqué

| Síntoma | Cómo lo diagnostiqué (comando o log) | Causa | Solución |
| --- | --- | --- | --- |
| El bandwidth-test con `btest` daba `authentication failed` con la clave correcta | `/log print` en el router: `login failure for user btest via bandwidth-test`. Con el usuario en los grupos `full` y `read` funcionaba. Probando los permisos de `read` por mitades quedó uno solo | El bandwidth-test exige el permiso `test` y además `winbox` | Grupo `solo-pruebas` con `test,winbox`, y la administración cerrada desde la red de abonados para que `winbox` no sirva para entrar |
| En la base las sesiones empezaban "en el futuro" y el tablero mostraba duraciones negativas | `/system clock print` en el router contra `date` en el servidor: 46 minutos de diferencia. Tras un reinicio el router registró `ntp change time ... 23:42:58 => ... 20:37:19` | El router confiaba en su reloj, que en la VM arranca mal | NTP: el servidor da la hora y el router es cliente. Además el tablero usa el reloj de la base |
| El router no contestaba un cambio de velocidad mandado desde el servidor | Log del router: `received remote request from 10.10.50.10 with bad signature (check your secret!), dropping` | El pedido de prueba salió firmado con un secreto vacío (un error de comillas al escribir el comando) | Mandarlo con el comando `servidor/isp`, que toma el secreto de la variable de entorno |
| `failure: action name can contain only letters and numbers` al crear el destino de logs | El propio mensaje de error | El nombre tenía un guion | Nombre sin guiones: `recolector` |
| El router se reinició solo durante una prueba | Log: `router was rebooted without proper shutdown` | Un `bandwidth-test` del router contra sí mismo (`address=127.0.0.1`), que probamos para cargar la CPU | No usarlo. Para cargar la CPU, un bucle de cálculo |
| Sin servidor RADIUS, el abonado que se reconecta no entra | Log: tres `server timeout` y después `authentication failed - radius timeout`. `/radius monitor 0 once`: `timeouts` subiendo | No hay nadie contestando en 10.10.50.10 | Es lo esperado; es la prueba "se cae el RADIUS" |
| [Completar con lo que me pase al repetirlo yo] | | | |

## 6. Cómo usé la IA

Qué le pregunté, qué respondió mal y cómo me di cuenta.

- Usé Claude Code. Le pedí que leyera todo el repo y el material de la cátedra, que me resumiera el proyecto y que me explicara PPPoE y RADIUS desde cero.
- Le pedí que armara la configuración de mi parte desde cero, y después que completara el proyecto entero en mi PC para verlo funcionar de punta a punta. Creó las VMs, escribió los archivos y los probó contra equipos reales antes de dármelos.
- **Qué respondió mal:**
  - Supuso que un grupo con solo el permiso `test` alcanzaba para el bandwidth-test. En la prueba real falló; el log del router mostró el `login failure` y probando permisos apareció que también hace falta `winbox`.
  - Le puso un guion al nombre del destino de logs. RouterOS lo rechazó con un mensaje claro.
  - En los comentarios del archivo de RADIUS escribió que el accounting no se manda para usuarios locales y que el router no dice por qué rechaza cuando el RADIUS no responde. El log real mostró lo contrario en los dos casos, y los comentarios se corrigieron.
  - Para cargar la CPU propuso un bandwidth-test del router contra sí mismo, y el router se reinició.
  - No previó que el reloj del router podía estar mal. Apareció al ver horarios imposibles en la base.
  - Armó un comando para cerrar conexiones colgadas en la base (`isp cerrar-fantasmas`) que también cerraba conexiones vivas si el accounting había estado cortado más de 3 minutos. Se vio al volver a prender la VM de servicios: abonado1 seguía conectado en el router y en la base figuraba "sin noticias".
  - Dio por bueno que la tabla de intentos nunca guarda claves. Con una prueba a mano por PAP quedó guardada `clave1`, a la vista.
- **Cómo se detectó:** nada de eso se vio leyendo; se vio corriéndolo y mirando el log de las dos puntas.
- **Una segunda revisión:** otro agente comparó la documentación contra la configuración y marcó 37 diferencias. No todas eran ciertas: propuso cambiar un panel para contar los rechazos con la base caída, y al probarlo ya se contaban; el cambio los contaba dos veces y se deshizo.
- [Completar: qué revisé yo línea por línea, qué no entendía y tuve que preguntar, y qué verifiqué por mi cuenta en WinBox.]
