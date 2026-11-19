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

- [ ] El contenedor levanta desde el repo con `docker compose up -d`.
- [ ] `radtest` acepta a `abonado1` y devuelve el atributo `Mikrotik-Rate-Limit` de su plan.
- [ ] `radtest` rechaza a `moroso` y a una contraseña incorrecta.
- [ ] Un intento de login queda registrado en `radpostauth`.
- [ ] Las notas están al día.
