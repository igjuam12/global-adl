# Proyecto final RADIUS — ISP simulado

Administración de Servicios en Linux · UTN FRM · Presentación: **jueves 26 de noviembre**

Un MikroTik CHR como servidor PPPoE, autenticando abonados contra **FreeRADIUS**, con usuarios y accounting en **PostgreSQL**, y un tablero en **Grafana** con el estado del router y el uso de los abonados.

- **Qué trae la rama `integracion-nacho` y qué tiene que revisar cada uno:** [`cambios-de-esta-rama.md`](cambios-de-esta-rama.md).
- **Plan de trabajo y datos comunes:** [`plan-de-trabajo.md`](plan-de-trabajo.md) (IPs, secreto, abonados, puertos, versiones).
- **Arquitectura y decisiones:** [`arquitectura.md`](arquitectura.md).
- **Topología:** [`topologia.png`](topologia.png). La fuente editable es [`topologia.svg`](topologia.svg).
- **Consigna de la cátedra:** [`Proyecto final — RADIUS.pdf`](Proyecto%20final%20—%20RADIUS.pdf).

## Equipo

| Parte | Responsable | Carpeta | Notas |
| --- | --- | --- | --- |
| 1 · Base de datos | Agus | [`postgres/`](postgres/) | [`notas/agustin.md`](notas/agustin.md) |
| 2 · FreeRADIUS | Nico | [`freeradius/`](freeradius/) | [`notas/nico.md`](notas/nico.md) |
| 3 · Router (MikroTik) | Nacho | [`mikrotik/`](mikrotik/) | [`notas/nacho.md`](notas/nacho.md) |
| 4 · Abonados y pruebas | Rodri | [`abonados/`](abonados/) | [`notas/rodri.md`](notas/rodri.md) |
| 5 · Grafana | Igna | [`grafana/`](grafana/) | [`notas/igna.md`](notas/igna.md) |

Cada carpeta tiene un `README.md` con qué va ahí y cuándo esa parte está "terminada".

## Estructura

```
.
├── README.md                     ← este archivo
├── plan-de-trabajo.md            ← plan del grupo y datos comunes
├── arquitectura.md               ← cómo está armado y por qué
├── referencia/                   ← material de consulta (la guía larga, no se sigue al pie de la letra)
├── topologia.png                 ← el dibujo de la topología
├── topologia.svg                 ← su fuente editable
├── Vagrantfile                   ← crea las dos VMs Debian (isp-servicios e isp-monitoreo) y levanta todo
├── servidor/                     ← scripts de las dos VMs (prepararlas y desplegar) y el comando isp
├── docker-compose.yml            ← los contenedores de isp-servicios: PostgreSQL y FreeRADIUS
├── docker-compose.monitoreo.yml  ← los de isp-monitoreo: Prometheus y sus exportadores, Alloy, Loki y Grafana
├── .env.example                  ← variables de ejemplo (copiar a .env)
├── postgres/init/                ← Parte 1: esquema, datos, historial, vistas y permisos de la base
├── postgres/pg_hba.conf          ← Parte 1: quién puede entrar a la base y desde dónde
├── postgres/extras/              ← Parte 1: datos de prueba inventados (ya no se cargan solos)
├── freeradius/                   ← Parte 2: nuestra imagen de FreeRADIUS (Dockerfile, clients.conf, sql)
├── mikrotik/                     ← Parte 3: configuración de isp-router por etapas y sus /export
├── abonados/                     ← Parte 4: configuración de abonados, tráfico automático y pruebas
├── grafana/                      ← Parte 5: fuentes de datos y tablero
├── alloy/                        ← Parte 5: recolector de logs (syslog del router y de FreeRADIUS)
├── prometheus/                   ← Parte 5: base de métricas
└── notas/                        ← un archivo de decisiones por persona
```

Las herramientas de la Parte 5 van cada una en su propia carpeta en la raíz. Loki no tiene carpeta: usa la configuración que trae su imagen.

## Cómo levantar todo

### Requisitos

- **VirtualBox y Vagrant** en la PC. Lo probamos con VirtualBox 7.2.16 y Vagrant 2.4.9.
- **3,75 GB de RAM** para tener las 5 VMs prendidas: 256 MB cada MikroTik, 1 GB isp-servicios y 2 GB isp-monitoreo.
- La imagen de **CHR 7.20.4** para las tres VMs MikroTik (ver [`abonados/README.md`](abonados/README.md), sección 4).

### 1. Los dos servidores

```bash
git clone https://github.com/igjuam12/global-adl.git
cd global-adl
cp .env.example .env      # y ajustar las contraseñas si hace falta
vagrant up
```

`vagrant up` crea y levanta las dos VMs Debian que define el [`Vagrantfile`](Vagrantfile):

| VM | IP | RAM | Qué corre | Su archivo de Compose |
| --- | --- | --- | --- | --- |
| `isp-servicios` | 10.10.50.10 | 1 GB | Lo que hace funcionar al ISP: PostgreSQL y FreeRADIUS. También le da la hora al router | [`docker-compose.yml`](docker-compose.yml) |
| `isp-monitoreo` | 10.10.50.20 | 2 GB | Lo que lo mira: Prometheus con sus exportadores, Alloy, Loki y Grafana | [`docker-compose.monitoreo.yml`](docker-compose.monitoreo.yml) |

**Por qué dos y no una:** para separar el monitoreo de lo monitoreado. Si se cae isp-servicios (la base y el RADIUS), el tablero sigue vivo en la otra VM y lo muestra. Con todo en una sola VM se caían juntos el RADIUS y el tablero.

En cada VM, `vagrant up` hace los mismos cuatro pasos:

| Paso | Qué hace | Dónde está |
| --- | --- | --- |
| Crea la VM | Debian 12 (box `debian/bookworm64` 12.20250126.1) con 2 CPUs. Adaptador 1 en NAT y adaptador 2 en la red interna `isp-servicios`, con su IP fija. En isp-monitoreo, además, reenvía el puerto 3000 (Grafana) a la notebook | `Vagrantfile` |
| La prepara | Zona horaria, servicio de hora (chrony) y Docker | [`servidor/preparar-servidor.sh`](servidor/preparar-servidor.sh) |
| Sube lo que le toca | A isp-servicios: `docker-compose.yml`, `postgres/`, `freeradius/` y `servidor/`. A isp-monitoreo: `docker-compose.monitoreo.yml`, `alloy/`, `prometheus/`, `grafana/` y `servidor/`. A cada una, el `.env` solo con las claves que usa | `Vagrantfile` |
| Despliega | Lo deja en `/opt/isp-lab` y corre `docker compose up -d --build`. Si cambió la configuración de Alloy, Prometheus, Grafana o la autenticación SNMP, reinicia ese servicio; si cambió `postgres/pg_hba.conf`, le avisa a PostgreSQL para que lo relea. En isp-servicios deja además el atajo `isp` | [`servidor/desplegar.sh`](servidor/desplegar.sh) |

Al terminar, cada VM muestra sus contenedores: tres en isp-servicios (PostgreSQL, FreeRADIUS y node-exporter, que mide al servidor) y seis en isp-monitoreo (Prometheus, snmp-exporter, node-exporter, Alloy, Loki y Grafana).

- En isp-monitoreo, `docker-compose.monitoreo.yml` queda guardado con el nombre `docker-compose.yml`. Por eso adentro de cualquiera de las dos VMs se usa `docker compose` sin aclarar el archivo.
- Si no existe `.env`, se sube `.env.example` con ese nombre (los valores de laboratorio).
- **Cuánto tarda** (medido el 19-nov, con la box ya descargada): borrar las dos VMs y crearlas de cero (`vagrant destroy -f` y `vagrant up`), unos 6 minutos; reiniciar las dos (`vagrant reload`), 81 segundos. Los contenedores vuelven a arrancar solos.
- **Las contraseñas se fijan en el primer arranque.** Los usuarios de la base y el `admin` de Grafana se crean una sola vez, con lo que diga el `.env` en ese momento. Cambiar el `.env` después no los cambia: hay que recrear las VMs (`vagrant destroy` y `vagrant up`) o cambiarlas a mano adentro.
- **Si en VirtualBox ya hay una VM llamada `isp-servicios` o `isp-monitoreo`** armada a mano, `vagrant up` falla por el nombre repetido. Hay que renombrarla o borrarla antes, y no prender dos máquinas con la misma IP.

**Grafana** queda en <http://localhost:3000>, usuario `admin` y la clave `GRAFANA_ADMIN_PASSWORD` del `.env`. El tablero está en la carpeta **ISP**.

| Comando | Para qué |
| --- | --- |
| `vagrant provision` | Después de un `git pull`: vuelve a subir el proyecto a las dos VMs y aplica los cambios. Los datos no se pierden, viven en volúmenes de Docker |
| `vagrant ssh isp-servicios` | Entrar a una VM. Hay que decir a cuál: `isp-servicios` o `isp-monitoreo` |
| `vagrant halt` / `vagrant up` | Apagarlas / prenderlas. Los contenedores arrancan solos |
| `vagrant reload` | Reiniciarlas |
| `vagrant destroy` | Borrarlas enteras, **con los datos** |

Con el nombre de una VM al final, estos comandos actúan solo sobre esa. Por ejemplo, `vagrant provision isp-monitoreo`.

### 2. Las VMs MikroTik

Con los dos servidores arriba, se arman el router y los abonados. Cada uno tiene su receta:

- **Router:** [`mikrotik/README.md`](mikrotik/README.md). Tres archivos, uno por etapa, que se importan en orden.
- **Abonados:** [`abonados/README.md`](abonados/README.md).

### 3. Operar el ISP

En isp-servicios hay un comando que junta las tareas de todos los días. Cambia el dato en la base y le avisa al router, para que el cambio valga en el momento:

```bash
vagrant ssh isp-servicios
sudo isp estado
```

| Comando | Qué hace |
| --- | --- |
| `isp estado` | Contenedores de isp-servicios, abonados y conexiones abiertas |
| `isp suspender <abonado>` | Lo marca como moroso y lo desconecta en el momento |
| `isp rehabilitar <abonado>` | Le saca la marca; vuelve a entrar solo |
| `isp plan <abonado> <plan>` | Le cambia el plan y aplica la velocidad sin desconectarlo |
| `isp probar <abonado> <clave>` | Le pregunta al RADIUS sin pasar por el router |

Todos van con `sudo` adelante, por ejemplo `sudo isp suspender abonado2`. `isp` es un atajo a `/opt/isp-lab/servidor/isp` que deja el despliegue. La lista completa sale con `sudo isp`, sin argumentos. Cómo funciona por dentro: [`freeradius/README.md`](freeradius/README.md).

El comando va en isp-servicios porque opera sobre la base y el RADIUS. La carpeta `servidor/` también se copia a isp-monitoreo, pero ahí `isp` no sirve.

### Sin Vagrant

Armar los dos servidores a mano, clonando una VM Debian para cada uno, **no está probado** con este diseño. Lo que haría falta está en [`plan-de-trabajo.md`](plan-de-trabajo.md), sección 6.

## Reglas del repo

1. **Todo lo que se configura queda en un archivo del repo.** Si algo se hizo a mano y no está acá, no se puede rearmar en la máquina de la presentación.
2. **Cada uno trabaja en su carpeta y en su archivo de notas.** Los dos archivos de Compose son compartidos: cada uno toca solo el bloque de su parte.
3. **`git pull` antes de empezar y antes de hacer `push`**, para no pisar el trabajo de otro.
4. **Commits chicos y con prefijo de la parte**, por ejemplo: `feat(freeradius): conexión con PostgreSQL` o `fix(mikrotik): nombre de la interfaz de acceso`. Prefijos: `database`, `freeradius`, `mikrotik`, `abonados`, `grafana`, `docs`.
5. **Nunca se sube el `.env`** (está en `.gitignore`). Las contraseñas de ejemplo van en `.env.example`.
6. **Las notas se escriben mientras se trabaja**, con la plantilla de [`notas/`](notas/): qué investigué, alternativas, qué elegí, qué falló y cómo usé la IA.
7. **Si cambia un dato común** (IP, secreto, usuario, puerto), se avisa al grupo y se actualiza `plan-de-trabajo.md` en el mismo commit.

## Saltos de línea (importante en Windows)

El archivo [`.gitattributes`](.gitattributes) fuerza saltos de línea de Linux (LF) en el repo. Los scripts `.sh` y los archivos de configuración con saltos de Windows (CRLF) fallan dentro de los contenedores con errores raros (por ejemplo `bad interpreter` o `$'\r': command not found`). Si alguien ya tenía el repo clonado, lo más simple es subir sus cambios y volver a clonarlo.
