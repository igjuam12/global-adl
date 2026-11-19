# Parte 3 · Router (MikroTik)

**Responsable:** Nacho · **Notas:** [`../notas/nacho.md`](../notas/nacho.md)

El router `isp-router` es el servidor PPPoE de los abonados y el cliente RADIUS: no decide solo, le pregunta a FreeRADIUS. También expone sus datos (CPU, memoria, logs) para que lleguen a Grafana.

## Qué va en esta carpeta

- La configuración de `isp-router`, exportada con `/export file=isp-router` y guardada como `isp-router.rsc`.
- Si se usan, scripts `.rsc` aparte para cada paso (por ejemplo, la parte de RADIUS), con comentarios.

Antes de exportar, conviene no dejar contraseñas reales. Para el laboratorio usamos los valores de `plan-de-trabajo.md`.

## Datos que usa (de `plan-de-trabajo.md`)

| Dato | Valor |
| --- | --- |
| RouterOS | 7.20.4 |
| Red de servicios | `ether3` → `10.10.50.1/24` |
| Red de acceso | `ether2` + VLAN 100, pool `100.64.1.10–100.64.1.100`, router `100.64.1.1` |
| Servidor RADIUS | `10.10.50.10`, secreto `IspUtnRadius2026` |
| Cortes desde el RADIUS | 3799/udp |

**Ojo:** confirmar los nombres de las interfaces con `/interface ethernet print` antes de configurar (en las prácticas los clones quedaron con la numeración corrida).

## Terminado cuando

- [ ] Los dos abonados se conectan por PPPoE con usuarios locales y aparecen en `/ppp active print`.
- [ ] Con los usuarios locales borrados, los abonados entran gracias al RADIUS y `moroso` es rechazado.
- [ ] El accounting llega cada minuto (`interim-update`).
- [ ] CPU, memoria y logs se pueden leer desde isp-servicios (junto con la Parte 5).
- [ ] La configuración exportada está en esta carpeta y las notas están al día.
