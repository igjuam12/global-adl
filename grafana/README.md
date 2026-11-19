# Parte 5 · Grafana

**Responsable:** Igna (los paneles de accounting los suma Agus) · **Notas:** [`../notas/igna.md`](../notas/igna.md)

Grafana arma el tablero del ISP: estado del router (CPU, memoria, logs) y lo que hacen los abonados (accounting). Esta parte también decide cómo llegan los datos del router hasta Grafana.

## Qué va en esta carpeta

```
grafana/
├── provisioning/
│   ├── datasources/   ← las fuentes de datos (Prometheus, Loki y PostgreSQL)
│   └── dashboards/    ← el archivo que carga los tableros
└── dashboards/        ← el tablero exportado como JSON
```

El `docker-compose.yml` ya monta `./grafana/provisioning` y `./grafana/dashboards` en el contenedor. Así Grafana arranca con todo configurado, sin tocar nada a mano.

Las herramientas que llevan los datos del router hasta Grafana van cada una en su carpeta en la raíz del repo: [`alloy/`](../alloy/) (recolector de SNMP y syslog) y [`prometheus/`](../prometheus/). Loki usa la configuración por defecto de su imagen. Por qué se eligió Alloy: ver [`../notas/igna.md`](../notas/igna.md).

## Datos que usa (de `plan-de-trabajo.md`)

| Dato | Valor |
| --- | --- |
| Grafana | 3000/tcp, se abre en `http://localhost:3000` desde la notebook |
| PostgreSQL | Base `radius`, usuario de solo lectura `grafana_ro` (contraseña en `.env`) |
| Router | `10.10.50.1` (la forma de leerlo la define esta parte) |

## Terminado cuando

- [ ] Grafana levanta desde el repo con las fuentes de datos ya cargadas.
- [ ] El tablero muestra CPU, memoria y logs del router, y el accounting.
- [ ] Hay 3 o 4 paneles extra, cada uno con una frase de por qué le sirve a quien opera el ISP.
- [ ] El tablero está exportado en esta carpeta y las notas están al día.
