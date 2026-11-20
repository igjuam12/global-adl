# Arquitectura · Cómo está armado y por qué

Este documento explica el proyecto completo: qué pieza hace qué, cómo se conectan, qué decidimos y qué descartamos. Está pensado para estudiarlo antes de la presentación: cualquiera del grupo tiene que poder explicar cualquier parte.

Todo lo que dice acá está probado, salvo donde se indica lo contrario. Los resultados de las pruebas están en [`abonados/pruebas.md`](abonados/pruebas.md).

---

## 1. La idea en un párrafo

Simulamos un ISP chico. Los abonados se conectan por PPPoE a un router MikroTik. El router no decide solo: le pregunta a un servidor RADIUS si deja entrar a cada abonado y con qué velocidad, y después le informa cada minuto cuánto consume. El RADIUS guarda todo en una base de datos, y un tablero muestra cómo está el router y qué hacen los abonados.

Con la analogía del gimnasio: el router es el **molinete** de la sucursal, FreeRADIUS es el **empleado de la oficina central** que atiende el teléfono, PostgreSQL es el **fichero**, y Grafana son las **pantallas del gerente**.

---

## 2. El recorrido de una conexión

```
abonado1 ─┐
          ├─ PPPoE ─► isp-router ─ RADIUS ─► FreeRADIUS ─► PostgreSQL ◄─ Grafana
abonado2 ─┘  VLAN 100   (molinete)           (empleado)     (fichero)   (pantallas)
```

1. **El abonado busca al router.** Grita por la VLAN 100 buscando un servidor PPPoE. Contesta el del router, que se llama `isp`.
2. **El abonado se presenta.** Manda su usuario y una prueba de que sabe la clave. La clave en sí no viaja (MS-CHAPv2).
3. **El router le pregunta al RADIUS** (`Access-Request`, puerto 1812): "me llegó abonado1, ¿lo dejo pasar?".
4. **FreeRADIUS busca en la base** si el usuario existe, si la clave coincide, si está suspendido y qué plan tiene.
5. **FreeRADIUS contesta.** `Access-Accept` con la velocidad del plan adentro (`Mikrotik-Rate-Limit = 512k/512k`), o `Access-Reject`.
6. **El router lo deja entrar.** Le da una IP de su pool y crea sola una cola con la velocidad que dictó el RADIUS.
7. **El router informa el consumo** (`Accounting-Request`, puerto 1813): un aviso al entrar, uno por minuto y uno al salir. FreeRADIUS los guarda en la base.
8. **Grafana lo muestra.** Lee el accounting de la base, las métricas del router de Prometheus y los logs de Loki.

Dos caminos van **al revés**, hacia el router:

- **El corte y el cambio de plan en el momento** (puerto 3799): el RADIUS le avisa al router que desconecte a alguien o que le cambie la velocidad ya.
- **Las métricas** (SNMP, puerto 161): cada 15 segundos Prometheus pide las métricas del router, y un intermediario (`snmp-exporter`) le hace la pregunta al router por SNMP y traduce la respuesta.

---

## 3. Las cinco máquinas y las tres redes

| VM | Qué es | Cómo se crea |
| --- | --- | --- |
| `isp-router` | MikroTik CHR 7.20.4. Servidor PPPoE y cliente RADIUS | Clon de una base limpia + [`mikrotik/`](mikrotik/) |
| `abonado1`, `abonado2` | MikroTik CHR 7.20.4. Clientes PPPoE | Clon de una base limpia + [`abonados/`](abonados/) |
| `isp-servicios` | Debian 12 con Docker. Lo que hace funcionar al ISP: la base y el RADIUS | `vagrant up` |
| `isp-monitoreo` | Debian 12 con Docker. Lo que lo mira: las métricas, los logs y el tablero | `vagrant up` |

| Red | Para qué | Quién está |
| --- | --- | --- |
| `isp-acceso` (VLAN 100) | La "calle": por donde llegan los abonados | Router y abonados |
| `isp-servicios` (10.10.50.0/24) | El "pasillo interno" del ISP | Router (10.10.50.1), servicios (10.10.50.10) y monitoreo (10.10.50.20) |
| Gestión (solo-anfitrión) y NAT | Para entrar nosotros a las máquinas. No son parte del ISP | Todas |

**Los abonados nunca ven a los servidores.** Solo hablan con el router, y el router tiene una regla que les corta el paso hacia la red de servicios.

**El monitoreo va en otra máquina que lo monitoreado.** Si se cae `isp-servicios` (la base y el RADIUS), el tablero sigue vivo en `isp-monitoreo` y muestra lo que está pasando. Con todo en una sola VM, el tablero se caería justo cuando más hace falta.

---

## 4. Qué hay adentro de las dos VMs Debian

Cada VM tiene su propio archivo de Docker Compose y un `vagrant up` levanta las dos.

**`isp-servicios`** (10.10.50.10) · [`docker-compose.yml`](docker-compose.yml)

| Qué corre | Qué hace | Puerto publicado |
| --- | --- | --- |
| `postgres` (contenedor) | Guarda abonados, planes y accounting | 5432/tcp, solo en la red de servicios |
| `freeradius` (contenedor) | Contesta al router y escribe el accounting | 1812 y 1813/udp |
| `node-exporter` (contenedor) | Publica CPU y memoria de esta VM, para que Prometheus las lea | 9100/tcp, solo en la red de servicios |
| `chrony` (servicio del sistema) | Da la hora por NTP. El router se la pide | 123/udp |

**`isp-monitoreo`** (10.10.50.20) · [`docker-compose.monitoreo.yml`](docker-compose.monitoreo.yml)

| Qué corre | Qué hace | Puerto publicado |
| --- | --- | --- |
| `prometheus` | Cada 15 segundos les pide las métricas a los exportadores y las guarda | Ninguno hacia la red |
| `snmp-exporter` | Intermediario del router: recibe el pedido de Prometheus, le pregunta al router por SNMP y traduce | Ninguno |
| `node-exporter` | Publica CPU y memoria de esta VM | Ninguno |
| `alloy` | Recolector de logs: recibe el syslog del router y el de FreeRADIUS | 1514 y 1515/udp |
| `loki` | Guarda los logs | Ninguno |
| `grafana` | El tablero | 3000/tcp |

Lo que cruza de una VM a la otra son tres cosas:

- **Grafana lee la base** (5432). Entra con un usuario que solo puede leer cuatro vistas, y la base solo lo acepta si viene de 10.10.50.20 ([`postgres/pg_hba.conf`](postgres/pg_hba.conf)).
- **Los logs de FreeRADIUS** viajan al recolector (1515/udp).
- **Prometheus le pide sus métricas a isp-servicios** (9100/tcp). Si no contesta, sabe que ese servidor se cayó.

---

## 5. Las decisiones, y lo que descartamos

| Decisión | Qué elegimos | Qué descartamos y por qué |
| --- | --- | --- |
| Dónde corre Docker | Dentro de la VM Debian | Docker Desktop en Windows: mete capas de NAT, no queda en la red interna del router y no se ve desde qué IP llega cada pedido |
| Dónde va el monitoreo | En su propia VM (`isp-monitoreo`) | En la misma VM que el RADIUS: si esa VM se cae, se cae también el tablero que lo mostraría |
| Cómo se crean los servidores | Vagrant: `vagrant up` levanta las dos VMs | Clonar VMs y configurarlas a mano: depende de que nadie se saltee un paso (lo de las prácticas 7 y 8 de Servidores) |
| Configuración de FreeRADIUS | Imagen propia: la oficial más seis cambios, todos a la vista en un archivo (`freeradius/Dockerfile`) | Montar archivos sueltos sobre la imagen oficial: funciona, pero no queda a la vista qué se cambió respecto de fábrica |
| Quién puede consultar al RADIUS | `clients.conf`, con el secreto en una variable de entorno | La tabla `nas` de la base: dejaba el secreto en una tabla y había dos lugares donde definir lo mismo |
| Usuarios de la base | Tres: administrador, `radius` y `grafana_ro` | Uno solo para todo: FreeRADIUS entraba como superusuario |
| Qué ve Grafana de la base | Solo cuatro vistas | Las tablas del RADIUS: `grafana_ro` podía leer el secreto compartido y la columna de claves de los intentos |
| Quién entra a la base por la red | Solo FreeRADIUS (desde Docker) y Grafana (desde 10.10.50.20), con una lista propia (`pg_hba.conf`) | La lista de fábrica, que deja entrar desde cualquier lado a cualquier usuario que sepa su clave, incluido el administrador |
| Cómo se guarda la clave | En texto plano (`Cleartext-Password`) | Guardar un hash: PPPoE autentica por desafío (MS-CHAPv2) y el servidor necesita la clave original para repetir la cuenta |
| Cómo se suspende a un moroso | Se le **agrega** el grupo `morosos` con prioridad 0 | Cambiarle el grupo: se perdía qué plan tenía |
| Perfil por defecto del PPPoE | Sin velocidad | Con velocidad: no se sabría si la cola la puso el RADIUS o el perfil |
| Configuración del router | Tres archivos, uno por etapa | Un solo `/export`: no guarda los usuarios y no se puede integrar de a un cambio por vez |
| Cómo llegan las métricas | SNMP: el monitoreo pregunta | La API de MikroTik: suma una pieza y un usuario con clave en el router |
| Cómo llegan los logs | Syslog: el router los manda | Guardarlos en la base del RADIUS: mezcla cosas distintas |
| Quién junta las métricas | Prometheus pregunta a exportadores (`snmp-exporter` para el router, `node-exporter` para cada servidor) | Que las junte Alloy y se las empuje a Prometheus (lo tuvimos así): anda, pero Prometheus queda como un simple depósito y no se ve el modelo que trae de fábrica. Telegraf: hay que armarle la salida hacia Prometheus |
| Quién junta los logs | Alloy, que recibe syslog y escribe en Loki | Telegraf: hay que armarle la lectura del syslog de RouterOS. Promtail: Grafana lo reemplazó por Alloy |
| La hora | NTP: las dos VMs Debian toman la hora de internet (chrony) e `isp-servicios` se la da al router | Que cada equipo confíe en su reloj: el router llegó a estar 46 minutos adelantado |
| Velocidades de los planes | 512k y 768k | 10M y 50M: la CHR sin licencia no pasa de 1 Mbps por interfaz, así que la cola nunca entraría en juego |

---

## 6. Lo que sumamos más allá del mínimo

La consigna pide CPU, memoria, logs y accounting. Esto es lo que agregamos y para qué le sirve a quien opera el ISP:

| Agregado | Qué resuelve |
| --- | --- |
| **El monitoreo en otra máquina.** El tablero y sus datos no viven donde vive el RADIUS | Si se cae la VM de servicios, el tablero sigue mostrando el router y avisa que el RADIUS no responde |
| **Historial del accounting.** Un disparador de la base guarda una copia de los contadores cada vez que llega un aviso | La tabla del RADIUS guarda solo el último total de cada conexión. Con el historial se puede graficar la velocidad de cada abonado minuto a minuto |
| **Operar con un comando** (`servidor/isp`): suspender, rehabilitar o cambiar de plan | Junta el cambio en la base con el aviso al router. Suspender corta en el momento; cambiar de plan aplica la velocidad nueva **sin desconectar** al abonado |
| **Los logs de las dos puntas juntos.** El del router y el de FreeRADIUS llegan al mismo lugar | Cuando algo falla hay que mirar los dos. El del RADIUS dice el motivo de cada rechazo |
| **La hora sincronizada** (NTP), y el tablero usa el reloj de la base | Los horarios del accounting y de los logs coinciden aunque el router arranque con el reloj mal. El contenedor de FreeRADIUS usa además la hora local de la VM, para que sus logs no salgan en UTC |
| **Control de salud que habla RADIUS.** Docker le pregunta a FreeRADIUS si está vivo en su propio idioma (Status-Server) | Distingue "el proceso está corriendo" de "el RADIUS contesta" |
| **Sesiones sin noticias.** El tablero marca las conexiones abiertas de las que no llegan avisos hace 3 minutos | Detecta que se cortó el accounting, o conexiones que quedaron "fantasma" |
| **Dos conteos de abonados conectados**, según el router y según el accounting | Si no coinciden, hay avisos que no están llegando |
| **El tope de la licencia dibujado** en el gráfico de tráfico | Explica a simple vista por qué los dos abonados juntos no llegan a su plan |
| **Tráfico automático** en los abonados | El tablero tiene movimiento sin que nadie lo genere a mano |

---

## 7. Seguridad: quién puede llegar a qué

El criterio es el mismo en todos lados: cada uno puede hacer solo lo que necesita.

| Quién | Qué puede | Qué no puede |
| --- | --- | --- |
| Un abonado | Conectarse por PPPoE, hacer ping al router, correr pruebas de velocidad | Llegar a la red de servicios; abrir la administración del router |
| Usuario `btest` del router | Autenticar un bandwidth-test | Leer o cambiar la configuración |
| El router, frente al RADIUS | Consultar, si viene de 10.10.50.1 y firma con el secreto | Nada si el secreto no coincide: FreeRADIUS descarta el pedido |
| El RADIUS, frente al router | Cortar o cambiar la velocidad de una conexión | Nada si no viene de 10.10.50.10 con el secreto |
| FreeRADIUS, en la base | Leer abonados y planes; escribir accounting | Borrar; crear tablas |
| Grafana, en la base | Leer cuatro vistas, y solo si viene de 10.10.50.20 | Ver claves, el secreto o cualquier tabla |
| El administrador de la base | Entrar desde adentro del contenedor | Entrar por la red, desde ningún lado |
| El exportador SNMP, en el router | Leer por SNMP con la comunidad `lab-monitoreo`, desde 10.10.50.20 | Escribir; la comunidad `public` está apagada |

Las contraseñas de los contenedores (las tres de la base, la de Grafana y el secreto RADIUS del lado del servidor) no están escritas en la configuración: entran por variables de entorno desde `.env`, y cada VM recibe solo las que usa. Del lado de los MikroTik sí van escritas en los `.rsc`, con valores de laboratorio: el secreto RADIUS, la comunidad SNMP, la clave de `btest` y las de los abonados. Las claves de los abonados también están en los datos iniciales de la base.

---

## 8. Qué pasa cuando algo falla

Todas probadas el jueves 19-nov con el sistema completo.

| Falla | El que ya estaba conectado | El que intenta entrar | Qué dice el router | Qué dice FreeRADIUS |
| --- | --- | --- | --- | --- |
| Se cae el RADIUS | Sigue navegando | No entra | `authentication failed - radius timeout` (3 intentos de 3 s) | Nada: está apagado |
| Se cae la base | Sigue navegando | No entra | `authentication failed` | `rlm_sql: Last connection attempt failed` |
| Secreto distinto | Sigue navegando | No entra | `authentication failed - radius timeout` | `invalid Message-Authenticator! (Shared secret is incorrect.)` |
| Clave incorrecta | — | No entra | `authentication failed` | `Login incorrect (mschap: MS-CHAP2-Response is incorrect)` |
| Abonado suspendido | — | No entra | `authentication failed` | `Login incorrect: [moroso]` |
| Se reinicia el router | Se cae y vuelve solo | — | — | Cierra las sesiones viejas (`Admin-Reboot`, `NAS-Reboot`) |
| Se apaga la VM de servicios entera | Sigue navegando | No entra | `authentication failed - radius timeout` | Nada: está apagada. **El tablero sigue vivo** en la otra VM y lo muestra |
| Vuelve la VM de servicios | Sigue navegando | Entra solo | — | Los contenedores arrancan solos, en menos de un minuto |
| Se reinicia la VM de monitoreo | Sigue navegando | Entra normalmente | Nada: no depende del monitoreo | Nada. Los contenedores del monitoreo vuelven solos (58 s) |

Lo más útil para explicar:

- **Con la VM de servicios apagada, el tablero siguió funcionando.** Siguió midiendo al router cada pocos segundos, recibió sus logs y el panel "RADIUS sin respuesta" contó los intentos fallidos. Los 12 paneles que leen la base mostraron "No data" con un aviso rojo, porque la base estaba apagada: es lo esperado. Los otros 11 siguieron andando. Con todo en una sola VM, en ese momento no habría tablero.
- **Para el router, un secreto mal escrito se ve igual que un RADIUS apagado.** La diferencia está en el log de FreeRADIUS. Por eso hay que mirar las dos puntas.
- **RADIUS caído y base caída no son lo mismo.** Con el RADIUS caído el router espera y se rinde (timeout). Con la base caída el RADIUS contesta, pero que no (rechazo).
- **Mientras el RADIUS está caído se pierden avisos de accounting.** Si un abonado se desconecta en ese rato, su conexión queda abierta en la base: una sesión fantasma. El tablero la marca "sin noticias"; se cierra sola cuando el router se reinicia, o a mano con `isp cerrar-fantasmas`.

---

## 9. Cómo se opera

En la PC, parado en la raíz del repo:

| Comando | Qué hace |
| --- | --- |
| `vagrant up` | Crea las dos VMs, instala Docker y levanta todo |
| `vagrant provision` | Vuelve a subir el proyecto y aplica los cambios (después de un `git pull`) |
| `vagrant ssh isp-servicios` | Entra a una VM (o `isp-monitoreo`) |
| `vagrant halt` / `vagrant destroy` | Las apaga / las borra |

Adentro de `isp-servicios` (`vagrant ssh isp-servicios`), siempre con `sudo` adelante: `sudo isp estado`. `isp` es un atajo a `/opt/isp-lab/servidor/isp` que deja el despliegue.

| Comando | Qué hace |
| --- | --- |
| `isp estado` | Contenedores, abonados y conexiones abiertas |
| `isp suspender abonado2` | Lo marca como moroso y lo desconecta en el momento |
| `isp rehabilitar abonado2` | Le saca la marca; vuelve a entrar solo |
| `isp plan abonado1 plan-768k` | Le cambia el plan y aplica la velocidad sin desconectarlo |
| `isp probar abonado1 clave1` | Le pregunta al RADIUS sin pasar por el router |
| `isp logs` | Últimos intentos de conexión |
| `isp cerrar-fantasmas` | Cierra las conexiones que quedaron abiertas sin noticias. Antes comprueba que el accounting esté llegando, para no cerrar una conexión viva que todavía no avisó |

El tablero: `http://localhost:3000`, usuario `admin`, clave en `.env`.

---

## 10. Límites que conocemos

- **La CHR sin licencia transmite 1 Mbps por interfaz.** Los dos abonados bajando a la vez se reparten ese tope (957 kbps medidos por la parte 4). Por lo mismo, el tráfico de los abonados casi no carga la CPU del router: 5 % como máximo con el tráfico automático (la parte 4 había visto 16 % en su router de prueba, con los dos abonados a tope a la vez).
- **Las dos VMs Debian están en la misma notebook.** Separan el monitoreo del RADIUS, pero si se apaga la notebook se apaga todo. En un ISP real serían dos equipos distintos.
- **Hay un solo RADIUS y una sola base.** Si `isp-servicios` se cae, nadie nuevo puede entrar hasta que vuelva. Lo que sí queda es el tablero para verlo.
- **Las claves de los abonados están en texto plano en la base.** Es lo que exige la autenticación por desafío. Se compensa con que esa tabla solo la leen el usuario de FreeRADIUS y el administrador de la base, que entra únicamente desde adentro del contenedor.
- **Los valores de `.env.example` son de laboratorio** y están en el repo a propósito.
- **Los abonados no sincronizan su reloj.** No hace falta: sus logs no se recolectan.
- **El router arranca con el reloj mal** y lo corrige por NTP a los pocos segundos. Por eso el tablero no usa la hora del router.
- **La red de gestión une a las tres VMs MikroTik.** No es parte del ISP simulado. Mientras `admin` no tenga clave, por ahí se puede entrar al router.
- **Grafana y las dos entradas de syslog escuchan en toda la red de servicios.** Grafana pide usuario y clave; el syslog (1514 y 1515/udp) acepta lo que le llegue de esa red, sin autenticar. Los abonados no llegan hasta ahí: el router no los deja pasar.
- **Las métricas de isp-servicios (9100/tcp) no piden clave.** Las puede leer cualquiera que esté en la red de servicios. Los abonados no llegan hasta ahí.
- **FreeRADIUS arranca una vez de más cuando se prende la VM.** Docker levanta los contenedores sin esperar a la base; FreeRADIUS falla, y Docker lo vuelve a levantar un segundo después. Se cura solo.

---

## 11. Guion para mostrarlo (5 minutos)

1. **El tablero andando:** arriba, el panel "Equipos" con los tres en verde; los dos abonados conectados, cada uno con su velocidad, CPU y memoria del router, logs entrando.
2. **Un abonado suspendido:** `sudo isp suspender abonado2`. Desaparece del router al instante, y en "Decisiones del RADIUS" se ve el rechazo en cada reintento. `sudo isp rehabilitar abonado2` y vuelve solo.
3. **Cambio de plan en caliente:** `sudo isp plan abonado1 plan-768k`. En el router, la cola pasa a 768k sin que la sesión se corte.
4. **Se cae todo el servidor del ISP:** `vagrant halt isp-servicios`. El conectado sigue; el que se reconecta no entra; el tablero sigue vivo, "Equipos" marca a isp-servicios en rojo y el panel "RADIUS sin respuesta" se pone en rojo. `vagrant up isp-servicios` y se recupera solo. Dos minutos después, `sudo isp cerrar-fantasmas` cierra la conexión que quedó colgada.
5. **El tope de la licencia:** los dos abonados bajando a la vez contra la línea punteada de 1 Mbps.

---

## 12. Las siete preguntas de la consigna, en corto

1. **¿Qué es RADIUS y qué le resuelve a un ISP?** Un protocolo para centralizar quién entra, con qué servicio y cuánto usó. Sin él, usuarios y planes viven en cada router.
2. **¿Qué papel cumple cada pieza?** Secciones 2 y 4.
3. **¿Qué es el accounting y qué deja?** Los avisos del router sobre cada conexión: quién, desde cuándo, con qué IP y MAC, cuánto subió y bajó, y por qué terminó.
4. **¿Qué es la observabilidad? ¿Métrica o log?** Poder saber qué le pasa al sistema mirándolo desde afuera. Una métrica es un número que se mide cada tanto (CPU 5 %). Un log es un texto que se escribe cuando pasa algo ("abonado2 logged in").
5. **¿Cómo lee Grafana cada cosa?** El router: Prometheus le pide las métricas a un exportador, que le pregunta al router por SNMP. Los logs: el router los manda por syslog y quedan en Loki. La base: se conecta directo con un usuario de solo lectura.
6. **¿Qué querría ver quien opera el ISP?** Sección 6 y las frases de cada panel en [`grafana/README.md`](grafana/README.md).
7. **¿Qué les pasa a los abonados si el RADIUS se cae?** Sección 8: los conectados siguen, los nuevos no entran y se pierde accounting.

---

## 13. Lo que evaluamos después de la devolución del profesor

El profesor marcó que Grafana no tenía que estar en el servidor del ISP. A partir de eso revisamos cinco decisiones.

| Pregunta | Qué decidimos | Por qué |
| --- | --- | --- |
| ¿Dónde va Grafana? | En su propia VM, `isp-monitoreo`, con todo lo que mira al ISP | El que vigila no puede caerse junto con lo vigilado. Lo probamos apagando `isp-servicios`: el tablero siguió vivo y lo mostró |
| ¿Hace falta una máquina cliente para ver el tablero? | No. El cliente es la notebook, que entra por el navegador | La consigna pide verlo "funcionando en su máquina" y no nombra un cliente. En las prácticas de Servidores el rol de cliente (`cli1`) es una estación de trabajo: acá ese papel lo cumple la notebook. Otra VM con escritorio solo sumaría RAM |
| ¿Quién junta las métricas? | Prometheus pregunta a exportadores | Es el modelo que Prometheus trae de fábrica y el que cita la práctica 7 de Servidores. Cada pieza hace una sola cosa, y la métrica `up` dice sola qué equipo dejó de contestar |
| ¿Sirve el patrón sidecar para el MikroTik? | No. Para el router va un exportador intermediario (`snmp-exporter`) | Un sidecar es un contenedor auxiliar pegado a otro contenedor, que comparte su entorno. El router no es un contenedor: no hay dónde pegarlo. Lo que le corresponde es un intermediario que hable SNMP de un lado y el idioma de Prometheus del otro. Donde sí entraría un sidecar es al lado de FreeRADIUS o de PostgreSQL, para sacar sus métricas internas: no lo sumamos |
| ¿Una VLAN por plan, y otra para los suspendidos? | No. Una sola VLAN de acceso; el plan y el estado de cada abonado los decide el RADIUS | Ver abajo |

**Por qué no una VLAN por plan.** La VLAN separa por dónde llega el abonado: el cable, la zona, el equipo. El plan es un dato de la persona. Con una VLAN por plan, cambiar de plan obligaría a reconfigurar el equipo del abonado y a tener un servidor PPPoE por VLAN en el router. Con RADIUS, cambiar de plan es cambiar un dato en la base, y el router aplica la velocidad nueva en el momento (`isp plan`).

**Qué hacemos con el que no paga.** Hay dos políticas posibles, y las dos se manejan desde el RADIUS:

| Política | Qué recibe el abonado | A favor | En contra |
| --- | --- | --- | --- |
| **Rechazo** (la que tenemos) | El RADIUS contesta que no. No conecta | Simple. El corte es inmediato (`isp suspender` cambia la base y desconecta) y queda registrado | El abonado solo ve que no anda: no distingue un corte por deuda de una falla |
| **Zona restringida** (no implementada) | El RADIUS lo acepta, pero el router lo anota en una lista de suspendidos con una velocidad mínima, y el firewall solo lo deja llegar a una página de aviso | El abonado ve por qué no navega, y el ISP lo sigue viendo conectado | Más piezas: una lista en el firewall, un grupo más en la base y una página de aviso |

La zona restringida es el equivalente, en PPPoE, de "mandar a los suspendidos a otra VLAN": el abonado no cambia de VLAN, cambia de lista. En la base sería un grupo con el atributo `Mikrotik-Address-List`, y en el router una regla de firewall para esa lista. Elegimos el rechazo porque alcanza para lo que pide el proyecto y se explica en una frase. Es la mejora que haríamos primero si esto fuera un ISP real.
