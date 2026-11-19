# Bitácora de Decisiones y Avance — Parte 1: Base de Datos (PostgreSQL)
**Responsable:** Agustín  
**Rol:** Parte 1 — Base de Datos  
**Materia:** Administración de Servicios en Linux — UTN FRM  
**Fecha:** 19 de Noviembre de 2026  

---

## 1. Qué investigué: qué es mi pieza y qué papel cumple

Mi pieza es el **servidor de base de datos PostgreSQL 17** desplegado en Docker (`isp-postgres`).

En una arquitectura de ISP, la base de datos es el **núcleo de persistencia del sistema AAA**:
* FreeRADIUS no almacena los datos en archivos de texto locales; utiliza el módulo `rlm_sql` para consultar a PostgreSQL ante cada solicitud que llega desde el router de borde (MikroTik).
* Desacopla la lógica de red de la persistencia: los routers pueden reiniciarse, agregarse o reemplazarse, pero las cuentas de abonados, sus contratos de velocidad y los registros históricos de consumo permanecen centralizados e intactos en la base de datos.

### Tablas oficiales que administro y su propósito:
1. `nas`: Lista de routers autorizados a consultar al servidor RADIUS, su IP y su secreto compartido (`IspUtnRadius2026`).
2. `radcheck`: Credenciales de acceso de los abonados (usuario y contraseña) para la etapa de **Autenticación**.
3. `radusergroup`: Vincula a cada abonado con su plan comercial (ej. `plan-10m`, `plan-50m`, `morosos`) para la etapa de **Autorización**.
4. `radgroupreply`: Atributos de red que se devuelven al router cuando un usuario de determinado grupo se autentica (aquí reside el atributo propietario `Mikrotik-Rate-Limit`).
5. `radgroupcheck`: Reglas condicionales por grupo (aquí configuramos el rechazo de morosos con `Auth-Type := Reject`).
6. `radacct`: Registro de **Accounting**. Almacena una fila por cada sesión PPPoE (hora de inicio, último interim, hora de fin, causa de desconexión, IP asignada, MAC del cliente y octetos transmitidos/recibidos).
7. `radpostauth`: Tabla de auditoría que registra cada intento de login (`Access-Accept` o `Access-Reject`) con marca temporal precisa.

---

## 2. Alternativas: qué opciones había y por qué descarté cada una

### A. Motor de Base de Datos: SQLite / MySQL vs PostgreSQL 17
* **Descartada (SQLite):** Aunque es simple y no requiere servicio de red, bloquea el archivo entero ante escrituras concurrentes. Con múltiples sesiones enviando paquetes de accounting (`interim-update`) cada minuto, genera contención y cuellos de botella. Además, no soporta usuarios concurrentes ni granularidad de permisos (no permite crear un usuario de solo lectura para Grafana).
* **Descartada (MySQL/MariaDB):** Era viable, pero PostgreSQL ofrece soporte nativo para tipos de datos de red (`INET` para almacenar direcciones IP de abonados y NAS sin parseos raros) y es el motor con mejor integración documentada en el módulo `rlm_sql` de FreeRADIUS 3.
* **Elegida (PostgreSQL 17):** Excelente rendimiento transaccional, soporte nativo de tipos de red (`INET`), índices parciales robustos y versión fijada para reproducibilidad.

### B. Almacenamiento de Contraseñas: Hash (bcrypt/MD5) vs Texto Plano (`Cleartext-Password`)
* **Descartada (Hash en base):** En entornos web tradicionales se exige hashear contraseñas. Sin embargo, en enlaces PPPoE la autenticación habitual utiliza protocolos basados en desafío-respuesta como CHAP o MS-CHAPv2. En estos protocolos, la contraseña **nunca viaja por la red**; el cliente devuelve un hash calculado a partir de un número aleatorio que le envía el servidor. Para que FreeRADIUS pueda verificar si la respuesta es correcta, el servidor necesita conocer la clave original para replicar el cálculo.
* **Elegida (`Cleartext-Password`):** Es el atributo requerido por FreeRADIUS para autenticar CHAP/MS-CHAPv2. La seguridad en un ISP se garantiza protegiendo la base de datos (red privada y permisos estrictos), no hasheando un valor que el protocolo de acceso no puede verificar.

### C. Bloqueo de Abonados Morosos: En el Router vs en la Base por Grupo
* **Descartada (Bloqueo en el Router):** Como vimos en la Práctica 6 de Redes, deshabilitar un secreto en el router exige tocar el equipo a mano, no escala si hay múltiples concentradores y no corta la sesión activa existente.
* **Elegida (Bloqueo por Grupo en PostgreSQL):** Crear un grupo `morosos` con la regla `Auth-Type := Reject` en `radgroupcheck`. Asignar o desasignar a un cliente de ese grupo es una sola sentencia `UPDATE radusergroup`. Al reconectar, FreeRADIUS rechaza la conexión en el acto sin tocar la configuración de ningún router.

### D. Conexión de Grafana a la Base: Usuario `radius` vs Rol `grafana_ro`
* **Descartada (Usar usuario `radius` en Grafana):** Violaba el principio de mínimo privilegio visto en Servidores. Darle permisos de escritura a una herramienta de visualización expone la base a corrupciones o inyecciones accidentales desde un panel. Además, le daría acceso a la tabla `radcheck` donde están las contraseñas.
* **Elegida (`grafana_ro`):** Rol con permisos de solo lectura (`SELECT`) restringido exclusivamente a las tablas de reportería (`radacct`, `radpostauth`, `radusergroup`, `radgroupreply`, `nas`), con revocación explícita sobre `radcheck`.

---

## 3. Qué hice: Análisis exhaustivo de cada archivo generado

Para cumplir con el principio de Infraestructura como Código (IaC de la P07 de Servidores: *"que no dependa de que alguien se acuerde"*), todos los artefactos de la base de datos se organizaron de forma declarativa y modular.

La imagen oficial de PostgreSQL ejecuta automáticamente los archivos montados en `/docker-entrypoint-initdb.d/` **únicamente la primera vez** que se inicializa el volumen, procesándolos en estricto orden alfanumérico (`01-`, `02-`, `03-`, `04-`).

A continuación se detalla la anatomía, propósito y sentencias de cada archivo:

```
postgres/init/
├── 01-schema.sql                 ← Estructura de tablas e índices oficiales
├── 02-datos-acordados.sql        ← Contratos, planes, NAS y regla de bloqueo
├── 03-seguridad-grafana.sh       ← Rol grafana_ro (Mínimo Privilegio)
└── 04-datos-prueba-sinteticos.sql ← Sesiones simuladas para pruebas en Grafana
```

---

### Archivo 1: `postgres/init/01-schema.sql` (Estructura oficial de FreeRADIUS 3.x)
* **Propósito:** Define el esquema relacional que el módulo `rlm_sql` de FreeRADIUS espera encontrar. Si los nombres de columnas o tipos difieren, las consultas precompiladas de FreeRADIUS fallan.
* **Componentes clave explicados sentencia por sentencia:**
  1. **`radcheck` (Autenticación de usuario):**
     - Columnas: `username` (nombre del abonado), `attribute` (ej. `Cleartext-Password`), `op` (operador de comparación `==` o `:=`), `value` (la contraseña esperada).
     - Índice: `radcheck_username` acelera la búsqueda durante la fase de `Access-Request`.
  2. **`radusergroup` (Mapeo Usuario $\rightarrow$ Grupo):**
     - Asocia `username` con `groupname` mediante un valor de `priority`. Permite que un usuario herede los atributos de su plan comercial.
  3. **`radgroupreply` (Atributos de respuesta del plan):**
     - Almacena los atributos que FreeRADIUS inyecta en el paquete `Access-Accept` para todos los usuarios pertenecientes a un grupo (ej. `Mikrotik-Rate-Limit`).
  4. **`radgroupcheck` (Validaciones condicionales de grupo):**
     - Permite aplicar chequeos a nivel de grupo, como la regla de bloqueo `Auth-Type := Reject`.
  5. **`radacct` (La tabla central de Accounting y Auditoría de ISP):**
     - `radacctid bigserial PRIMARY KEY`: Clave de 64 bits para soportar millones de registros de sesiones sin agotar el espacio numérico de un entero convencional.
     - `acctsessionid text` y `acctuniqueid text NOT NULL UNIQUE`: Identificadores únicos generados por FreeRADIUS para evitar colisiones entre sesiones concurrentes de distintos routers.
     - `nasipaddress inet` y `framedipaddress inet`: Tipo nativo `INET` de PostgreSQL que valida automáticamente el formato de direcciones IP y permite búsquedas de subredes.
     - `acctinputoctets` y `acctoutputoctets`: Enteros de 64 bits (`BIGINT`) para registrar bytes transmitidos y recibidos sin desbordamiento (un entero estándar de 32 bits colapsa al superar los 4 GB de descarga).
     - **Índices parciales de alto rendimiento:**
       - `radacct_active_session_idx`: Indexa únicamente filas donde `acctstoptime IS NULL`. Esto hace que los paquetes de `Interim-Update` cada 60 segundos actualicen la fila en microsegundos, sin escanear el histórico cerrado.
       - `radacct_bulk_close`: Permite cerrar en lote todas las sesiones abiertas de un NAS si el router se reinicia.
  6. **`radpostauth` (Auditoría de accesos):**
     - Guarda cada intento de login (`Access-Accept` o `Access-Reject`), la IP/MAC solicitante (`callingstationid`) y la fecha (`authdate` con zona horaria).
  7. **`nas` (Directorio de Routers autorizados):**
     - Guarda la IP del router, el tipo (`mikrotik`) y el secreto compartido para validar que solo routers autorizados puedan enviar peticiones AAA.

---

### Archivo 2: `postgres/init/02-datos-acordados.sql` (Aprovisionamiento de Contratos y Planes)
* **Propósito:** Carga los datos maestros acordados por el equipo en el [plan-de-trabajo.md](file:///C:/Users/agust/Downloads/UNIVERSIDAD/5to%20año/Admin%20de%20servicios%20en%20Linux/Proyecto/plan-de-trabajo.md), garantizando la integración con el MikroTik.
* **Componentes clave explicados sentencia por sentencia:**
  1. **Alta del NAS (`INSERT INTO nas`):**
     - Se registra `10.10.50.1` (`isp-router`) con el secreto compartido `IspUtnRadius2026`.
     - *Decisión de robustez:* Se agregó también la subred `10.10.50.0/24` y `127.0.0.1` para que las pruebas locales de la Parte 2 con `radtest` funcionen inmediatamente.
  2. **Alta de credenciales (`INSERT INTO radcheck`):**
     - Se dan de alta los tres abonados del contrato: `abonado1` (`clave1`), `abonado2` (`clave2`) y `moroso` (`clave3`), con operador `:=` y atributo `Cleartext-Password`.
  3. **Asignación a planes (`INSERT INTO radusergroup`):**
     - `abonado1` se asigna a `plan-10m`.
     - `abonado2` se asigna a `plan-50m`.
     - `moroso` se asigna a `morosos`.
  4. **Atributos de velocidad (`INSERT INTO radgroupreply`):**
     - Se inyecta el atributo `Mikrotik-Rate-Limit` con operador `:=`.
     - *Valores aplicados:* `256k/512k` para `plan-10m` y `512k/768k` para `plan-50m`.
     - *Alias de compatibilidad:* Se crearon también las entradas para `plan-basico` y `plan-plus` con idénticos parámetros, blindando el sistema en caso de que algún compañero pruebe con los nombres de la guía preliminar.
  5. **Mecanismo de corte a morosos (`INSERT INTO radgroupcheck`):**
     - Se define `('morosos', 'Auth-Type', ':=', 'Reject')`.
     - Esta regla intercepta el login del usuario moroso antes de evaluar la contraseña y devuelve un `Access-Reject`.

---

### Archivo 3: `postgres/init/03-seguridad-grafana.sh` (Hardening y Mínimo Privilegio)
* **Propósito:** Configura el acceso seguro que utilizará Grafana para consultar la base de datos sin comprometer la seguridad del ISP.
* **Componentes clave explicados sentencia por sentencia:**
  1. **Manejo de variables de entorno:**
     - Toma la contraseña desde `${GRAFANA_DB_PASSWORD:-LabGrafanaRO-2026}`, desacoplando las claves del código fuente.
  2. **Idempotencia mediante bloque PL/pgSQL:**
     - Ejecuta `DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafana_ro') ... END $$;`. Esto evita errores si el script se vuelve a correr manualmente sobre una base ya creada.
  3. **Concesión granular de lectura (`GRANT SELECT`):**
     - Permite `SELECT` sobre `radacct` (para métricas de tráfico y sesiones), `radpostauth` (para gráficos de login), `radusergroup` y `radgroupreply` (para nombres de planes) y `nas` (para identificar el equipo).
  4. **Revocación explícita (`REVOKE ALL ON radcheck FROM grafana_ro`):**
     - Implementa una barrera estricta de seguridad: aun si Grafana sufriera una vulnerabilidad o inyección SQL desde un panel web, es imposible que extraiga las contraseñas de los clientes.

---

### Archivo 4: `postgres/init/04-datos-prueba-sinteticos.sql` (Desacople y Pruebas Autónomas)
* **Propósito:** Permite que la Parte 1 y la Parte 5 puedan diseñar, probar y validar todos los paneles de Grafana de forma independiente, antes de que el router MikroTik y las VMs cliente estén encendidas.
* **Componentes clave explicados sentencia por sentencia:**
  1. **Marcas temporales relativas (`NOW() - INTERVAL '...'`):**
     - En lugar de usar fechas fijas (que quedarían obsoletas al día siguiente), las fechas se calculan respecto a la hora actual (`NOW()`). Así, el tablero de Grafana siempre muestra datos vivos y recientes, sin importar el día o la hora en que se levante la prueba.
  2. **Modelado de los 4 estados de sesión en `radacct`:**
     - **Sesión activa 1 (`abonado1`):** Conectado hace 25 min, con `acctupdatetime` hace 20 segundos y 80 MB consumidos. Simula un caso normal navegando.
     - **Sesión activa 2 (`abonado2`):** Conectado hace 12 min, con `acctupdatetime` hace 10 segundos y 250 MB consumidos. Simula un plan de mayor consumo.
     - **Sesión cerrada histórica (`abonado1`):** Sesión con `acctstoptime` fijado hace 1 hora y causa `User-Request`. Permite verificar que los gráficos de consumo acumulado y Top Talkers agreguen sesiones pasadas.
     - **Sesión fantasma (`sess-sim-ghost`):** Sesión con `acctstoptime IS NULL`, pero con `acctupdatetime` congelado hace 15 minutos (> 3 minutos). Sirve para comprobar que el panel de alerta de Grafana se active en rojo.
  3. **Eventos de autenticación en `radpostauth`:**
     - Inserta eventos exitosos (`Access-Accept`) y 3 rechazos consecutivos de `moroso` (`Access-Reject`) en los últimos minutos, alimentando el gráfico de series temporales de fallos de acceso.
  4. **Comando de purga para el día de la integración:**
     - Se documenta el comando `TRUNCATE radacct, radpostauth;` para vaciar los datos sintéticos con una sola orden cuando se conecte el MikroTik real.

---

### Archivo 5: `docker-compose.yml`, `.env` y `.env.example` (Despliegue e IaC)
* **Propósito:** Orquestar el despliegue del contenedor de base de datos bajo los principios de la Práctica 7 de Servidores (*Infraestructura como Código*).
* **Componentes clave explicados:**
  1. **Fijación de versión mayor (`image: postgres:17`):**
     - Evita problemas de incompatibilidad de datos binarios si Docker descarga una versión superior al recrear contenedores.
  2. **Persistencia de datos (`pgdata:/var/lib/postgresql/data`):**
     - El volumen con nombre `pgdata` garantiza que los datos y el histórico de sesiones no se pierdan al ejecutar `docker compose down`. Solo se borran si se usa explícitamente la bandera `-v`.
  3. **Chequeo de salud (`healthcheck`):**
     - Monitorea la disponibilidad del servicio con `pg_isready -U radius -d radius` cada 5 segundos. Esto permitirá que cuando la Parte 2 agregue FreeRADIUS, use `condition: service_healthy` para no arrancar hasta que la base esté lista.
  4. **Aislamiento de puertos:**
     - No se exponen puertos hacia el host Windows (`ports:` no publicado). La base solo escucha en la red interna de Docker, minimizando la superficie de ataque.
  5. **Desacople de secretos (`.env` vs `.env.example`):**
     - `.env` contiene las contraseñas reales de laboratorio con permisos restringidos (`chmod 600`), mientras que `.env.example` se versiona en Git sin exponer secretos.

---

## 4. Cambios aplicados con criterio técnico respecto al plan original

1. **Tasas de velocidad sub-1Mbps (`256k/512k` y `512k/768k`):**  
   * *El dilema:* En `plan-de-trabajo.md` se mencionaban `10M/10M` y `50M/50M`.
   * *El cambio:* Mantenemos el nombre comercial de los planes (`plan-10m` y `plan-50m`), pero inyectamos `256k/512k` y `512k/768k`.
   * *Justificación técnica:* La licencia gratuita de MikroTik CHR limita por software el ancho de banda a **1 Mbps por interfaz** (comprobado en la Práctica 8 de Redes y en la documentación oficial de MikroTik). Si configuráramos 10M y 50M, la saturación la provocaría el kernel de la máquina virtual y nunca las colas dinámicas de RADIUS. Con tasas sub-1Mbps, el encolamiento se produce en la Simple Queue y Grafana puede graficar escalones y saturaciones reales.
2. **Alias de compatibilidad de planes:**  
   Se incluyeron `plan-basico` y `plan-plus` junto a `plan-10m` y `plan-50m` para que el trabajo de los compañeros no se vea afectado si utilizan nomenclaturas alternativas.
3. **Bloqueo a nivel de grupo:**  
   En lugar de alterar registros individuales o secretos del router, el usuario `moroso` se bloquea mediante el grupo `morosos` con `Auth-Type := Reject`. Esto permite reactivar el servicio con una sola consulta SQL (`UPDATE radusergroup`) sin tocar la infraestructura de red.

---

## 5. Limitaciones del sistema de Base de Datos y Accounting

Comprender las limitaciones del sistema es fundamental para la defensa ante la cátedra:

1. **Sesiones Fantasma (Ghost Sessions):**  
   Si el concentrador MikroTik sufre un corte de energía o se cae el enlace hacia el RADIUS de forma imprevista, el paquete `Accounting-Stop` nunca llega a PostgreSQL. Como consecuencia, la sesión permanece con `acctstoptime IS NULL` indefinidamente en `radacct`.  
   *Mitigación:* Se implementó en Grafana la consulta que compara `now() - acctupdatetime > interval '3 minutes'` para detectar y alertar en rojo sesiones sin reporte.
2. **Granularidad del Accounting vs Telemetría en Tiempo Real:**  
   El accounting interino se envía cada 60 segundos (`interim-update=1m`). Esto significa que en la base de datos el consumo tiene hasta un minuto de desfase. No reemplaza a las métricas instantáneas (SNMP o API que recolecta Prometheus cada 15s).
3. **Pérdida de paquetes de Accounting (UDP):**  
   El protocolo RADIUS utiliza UDP (puerto 1813). Si hay congestión severa en la red de servicios, un paquete interino puede descartarse. Por esta razón, el umbral de sesión fantasma se fija en 3 minutos (tolerando la pérdida de hasta 2 paquetes consecutivos sin dar falsos positivos).
4. **Naturaleza acumulativa de los contadores:**  
   Los campos `acctinputoctets` y `acctoutputoctets` son enteros acumulados que solo crecen durante la sesión. No representan velocidad instantánea (bps) directamente; requieren que Grafana o la consulta SQL calcule la derivada temporal ($\Delta \text{octetos} / \Delta t$).
5. **Riesgo de almacenamiento en texto plano:**  
   Dado que CHAP/MS-CHAPv2 exige `Cleartext-Password`, el archivo `radcheck` contiene contraseñas legibles. Toda la seguridad del ISP descansa en no exponer la base hacia redes públicas y limitar estrictamente el acceso a administradores.

---

## 6. Qué falló y cómo lo diagnostiqué

1. **Permisos en script de inicialización (`03-seguridad-grafana.sh`):**  
   * *Síntoma:* PostgreSQL no ejecutaba el script al inicializar el volumen.  
   * *Diagnóstico:* Revisé `docker compose logs postgres` y noté falta de permisos de ejecución en el script montado en `/docker-entrypoint-initdb.d/`.  
   * *Solución:* Agregué `chmod +x` y validé que el rol no fallara si ya existía mediante `DO $$ BEGIN ... END $$;`.
2. **Validación de la alerta de Sesiones Fantasma:**  
   * *Problema:* Necesitaba asegurarme de que la consulta SQL en Grafana detectara la sesión congelada sin marcar como caídas a las sesiones normales activas.  
   * *Diagnóstico:* En `04-datos-prueba-sinteticos.sql` creé intencionalmente la sesión `sess-sim-ghost` con `acctupdatetime` atrasado 15 minutos.  
   * *Solución:* Comprobé con `psql` que la consulta devolvía exactamente 1 fila (la fantasma) y descartaba las sesiones con actualización en los últimos 20 segundos.

---

## 7. Cómo usé la IA

* **Qué le pregunté:** Le pedí que estructurara el esquema SQL de FreeRADIUS, que diseñara los planes según `plan-de-trabajo.md` y que armara las consultas para el tablero de Grafana.
* **Qué propuso inicialmente y qué respondió mal:** La IA inicialmente tomó de forma literal los planes comerciales de 10M y 50M y generó los `INSERT` con `10M/10M` y `50M/50M`.
* **Cómo me di cuenta:** Recordé lo aprendido en la Práctica 8 de Redes (Mangle y QoS) sobre el límite de 1 Mbps de la licencia gratuita de MikroTik CHR. Al revisar la documentación oficial de MikroTik y confrontar a la IA con este dato, confirmamos que con 10M/50M el tablero no iba a poder mostrar saturación de colas en el laboratorio. Corregí los scripts para usar las tasas de laboratorio `256k/512k` y `512k/768k`, documentando la justificación técnica en esta bitácora.
