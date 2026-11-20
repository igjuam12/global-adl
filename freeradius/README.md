# Parte 2 · FreeRADIUS

**Responsable:** Nico · **Notas:** [`../notas/nico.md`](../notas/nico.md)

FreeRADIUS recibe las preguntas del router ("¿dejo entrar a este abonado?"), busca al usuario y su plan en PostgreSQL, responde aceptando o rechazando, y guarda el accounting que manda el router.

## Qué va en esta carpeta

Los archivos de configuración de FreeRADIUS que se montan en el contenedor (ver el bloque `freeradius` del `docker-compose.yml`). Solo los que cambiamos respecto de la imagen oficial, cada uno con comentarios que expliquen qué hace y por qué.

## Datos que usa (de `plan-de-trabajo.md`)

| Dato | Valor |
| --- | --- |
| Router (cliente RADIUS) | `10.10.50.1` |
| Secreto compartido | `IspUtnRadius2026` |
| Puertos | 1812/udp (autenticación), 1813/udp (accounting) |
| Base | `radius` en el contenedor `postgres`, usuario `radius` (contraseña en `.env`) |
| Abonados | `abonado1`, `abonado2` y `moroso` (rechazado), ya cargados por la Parte 1 |

## Terminado cuando

- [x] El contenedor levanta desde el repo con `docker compose up -d`.
- [x] `radtest` acepta a `abonado1` y devuelve el atributo `Mikrotik-Rate-Limit` de su plan.
- [x] `radtest` rechaza a `moroso` y a una contraseña incorrecta.
- [x] Un intento de login queda registrado en `radpostauth`.
- [x] Las notas están al día.

## Archivos de esta carpeta

| Archivo | Se monta en | Qué hace |
| --- | --- | --- |
| `sql` | `/etc/raddb/mods-enabled/sql` | Módulo `sql`: conecta FreeRADIUS con PostgreSQL y carga los routers de la tabla `nas`. Es el original de la imagen 3.2.10 con 8 cambios marcados: `grep -n CAMBIO sql`. |

## Cómo probarlo (en isp-servicios)

```bash
docker compose up -d
docker compose logs -f freeradius     # modo debug (-X): detalle de cada pedido. Ctrl+C para salir

# Las pruebas usan el cliente localhost de la imagen (secreto testing123)
docker exec isp-freeradius radtest abonado1 clave1 127.0.0.1 0 testing123     # Accept + Mikrotik-Rate-Limit = "256k/512k"
docker exec isp-freeradius radtest moroso clave3 127.0.0.1 0 testing123       # Reject (grupo morosos)
docker exec isp-freeradius radtest abonado1 otraclave 127.0.0.1 0 testing123  # Reject (clave incorrecta)

# Cada intento queda registrado (authdate en UTC)
docker exec isp-postgres psql -U radius -d radius -c "SELECT id, username, reply, authdate FROM radpostauth ORDER BY id;"
```

## Lo que necesita cada parte

- **Router (Nacho):** el RADIUS escucha en `10.10.50.10`, 1812/udp (autenticación) y 1813/udp (accounting), con el secreto `IspUtnRadius2026`. El router ya está dado de alta en la tabla `nas` como `10.10.50.1`. El Access-Accept trae `Mikrotik-Rate-Limit` (la cola del plan), `Framed-Protocol = PPP` y `Service-Type = Framed-User`.
- **Base (Agus) y Grafana (Igna):** FreeRADIUS lee `radcheck`, `radusergroup`, `radgroupcheck`, `radgroupreply` y `nas`, y escribe `radpostauth` (cada intento, aceptado o rechazado) y `radacct` (accounting, cuando esté el router). Las fechas se guardan bien, pero `psql` las muestra en UTC.
