# Parte 4 · Abonados y pruebas

**Responsable:** Rodri · **Notas:** [`../notas/rodri.md`](../notas/rodri.md)

Dos clientes (`abonado1` y `abonado2`, MikroTik CHR) que se conectan por PPPoE y generan tráfico, y las pruebas de falla que vamos a mostrar en la presentación.

## Qué va en esta carpeta

- La configuración exportada de cada abonado: `abonado1.rsc` y `abonado2.rsc`.
- Cómo se genera el tráfico (comandos o scripts) y con qué parámetros.
- `pruebas.md`: cada prueba de falla de la sección 10 del plan, con lo que esperábamos, lo que pasó de verdad y la evidencia (comando, log o captura).

## Datos que usa (de `plan-de-trabajo.md`)

| Dato | Valor |
| --- | --- |
| Red de acceso | `ether2` + VLAN 100 |
| Usuarios | `abonado1` / `clave1`, `abonado2` / `clave2`, `moroso` / `clave3` |
| IP | La asigna el router, del pool `100.64.1.10–100.64.1.100` |

## Terminado cuando

- [ ] Los dos abonados se conectan a la vez y reciben una IP 100.64.1.x.
- [ ] Se puede generar tráfico a demanda y se ve el límite de cada plan.
- [ ] Las pruebas de falla están hechas y anotadas en `pruebas.md`.
- [ ] La configuración exportada está en esta carpeta y las notas están al día.
