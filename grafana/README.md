# Parte 5 · Grafana

**Responsable:** Igna (los paneles de accounting los suma Agus) · **Notas:** [`../notas/igna.md`](../notas/igna.md)

Grafana arma el tablero del ISP: estado del router (CPU, memoria, logs) y lo que hacen los abonados (accounting). Esta parte también decide cómo llegan los datos del router hasta Grafana.

## Qué va en esta carpeta

```
grafana/
└── provisioning/
    ├── datasources/   ← las fuentes de datos (PostgreSQL y las que se elijan)
    └── dashboards/    ← el tablero exportado como JSON y el archivo que lo carga
```

El `docker-compose.yml` ya monta `./grafana/provisioning` en el contenedor. Así Grafana arranca con todo configurado, sin tocar nada a mano.

Si se suman herramientas para las métricas y los logs del router (por ejemplo Telegraf, Prometheus o Loki), cada una va en su propia carpeta en la raíz del repo.

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
