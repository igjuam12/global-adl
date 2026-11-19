# Proyecto final RADIUS — ISP simulado

Administración de Servicios en Linux · UTN FRM · Presentación: **jueves 26 de noviembre**

Un MikroTik CHR como servidor PPPoE, autenticando abonados contra **FreeRADIUS**, con usuarios y accounting en **PostgreSQL**, y un tablero en **Grafana** con el estado del router y el uso de los abonados.

- **Plan de trabajo y datos comunes:** [`plan-de-trabajo.md`](plan-de-trabajo.md) (IPs, secreto, abonados, puertos, versiones).
- **Topología:** [`topologia.png`](topologia.png).
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
├── README.md                 ← este archivo
├── plan-de-trabajo.md        ← plan del grupo y datos comunes
├── referencia/               ← material de consulta (la guía larga, no se sigue al pie de la letra)
├── topologia.png
├── docker-compose.yml        ← todos los contenedores de isp-servicios
├── .env.example              ← variables de ejemplo (copiar a .env)
├── postgres/init/            ← Parte 1: esquema, datos y permisos de la base
├── freeradius/               ← Parte 2: configuración de FreeRADIUS
├── mikrotik/                 ← Parte 3: configuración exportada de isp-router
├── abonados/                 ← Parte 4: configuración de abonados y pruebas
├── grafana/                  ← Parte 5: fuentes de datos y tablero
└── notas/                    ← un archivo de decisiones por persona
```

Si la Parte 5 suma herramientas (por ejemplo Telegraf, Prometheus o Loki), cada una va en su propia carpeta en la raíz, como ya prevé el `docker-compose.yml`.

## Cómo levantar los servicios (en la VM isp-servicios)

```bash
git clone https://github.com/igjuam12/global-adl.git
cd global-adl
cp .env.example .env      # y ajustar las contraseñas si hace falta
chmod 600 .env
docker compose up -d
docker compose ps
```

Por ahora solo está activo PostgreSQL. Cada parte descomenta su bloque del `docker-compose.yml` cuando lo integra.

## Reglas del repo

1. **Todo lo que se configura queda en un archivo del repo.** Si algo se hizo a mano y no está acá, no se puede rearmar en la máquina de la presentación.
2. **Cada uno trabaja en su carpeta y en su archivo de notas.** El `docker-compose.yml` es compartido: cada uno toca solo el bloque de su parte.
3. **`git pull` antes de empezar y antes de hacer `push`**, para no pisar el trabajo de otro.
4. **Commits chicos y con prefijo de la parte**, por ejemplo: `feat(freeradius): conexión con PostgreSQL` o `fix(mikrotik): nombre de la interfaz de acceso`. Prefijos: `database`, `freeradius`, `mikrotik`, `abonados`, `grafana`, `docs`.
5. **Nunca se sube el `.env`** (está en `.gitignore`). Las contraseñas de ejemplo van en `.env.example`.
6. **Las notas se escriben mientras se trabaja**, con la plantilla de [`notas/`](notas/): qué investigué, alternativas, qué elegí, qué falló y cómo usé la IA.
7. **Si cambia un dato común** (IP, secreto, usuario, puerto), se avisa al grupo y se actualiza `plan-de-trabajo.md` en el mismo commit.

## Saltos de línea (importante en Windows)

El archivo [`.gitattributes`](.gitattributes) fuerza saltos de línea de Linux (LF) en el repo. Los scripts `.sh` y los archivos de configuración con saltos de Windows (CRLF) fallan dentro de los contenedores con errores raros (por ejemplo `bad interpreter` o `$'\r': command not found`). Si alguien ya tenía el repo clonado, lo más simple es subir sus cambios y volver a clonarlo.
