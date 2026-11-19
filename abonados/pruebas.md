# Parte 4 · Pruebas

Para cada prueba se anota **antes** qué esperamos y **después** qué pasó de verdad. Si no coincide, mejor: es material para contar en la presentación ("cómo diagnosticamos lo que falló").

---

## 1. Pruebas de tráfico (hechas el jue 19-nov, laboratorio de la parte 4)

Herramienta: `/tool bandwidth-test` desde cada abonado contra el router (100.64.1.1), TCP, 30 segundos. Planes: abonado1 512k/512k, abonado2 768k/768k.

| Prueba | Esperado | Medido | ¿Coincide? | Comentario |
|---|---|---|---|---|
| abonado1 bajada | ~512k | 497 kbps | ✅ | 97 % del plan. La diferencia son los encabezados (PPPoE, IP, TCP) |
| abonado1 subida | ~512k | 487 kbps | ✅ | 95 % |
| abonado2 bajada | ~768k | 746 kbps | ✅ | 97 % |
| abonado2 subida | ~768k | 734 kbps | ✅ | 96 % |
| Los dos juntos, bajada  | 512k + 768k | 351 + 606 ≈ **957 kbps** | ❌ | Límite de 1 Mbps por interfaz de la licencia gratuita del CHR. CPU máxima 16 %: no era la CPU |

**Observaciones:**
- La cola del plan también frena el tráfico que va al propio router (no era seguro: lo comprobamos).
- En la prueba simultánea, abonado1 arrancó unos segundos después. Su promedio de los últimos 10 s fue 294 kbps, pero al final subió a 564 kbps: cuando terminó la prueba de abonado2, abonado1 quedó con el "caño" libre.
- **Decisión del grupo (opción B):** mantener 512k/768k y explicar el límite en la presentación.

---

## 2. Pruebas de falla que se pueden hacer sin RADIUS

| Prueba | Cómo se provoca | Qué esperamos | Dónde mirar | Qué pasó |
|---|---|---|---|---|
| Contraseña incorrecta | En abonado1: `/interface pppoe-client set wan-pppoe password=mal` | El router rechaza la conexión; el abonado no recibe IP | `/log print` en el router y en el abonado; `/interface pppoe-client monitor wan-pppoe` | |
| VLAN distinta | En abonado1: `/interface vlan set vlan-acceso vlan-id=200` | El abonado no encuentra el servidor ("searching…") y **ningún log menciona la VLAN** | `monitor` en el abonado; `/interface vlan print` en las dos puntas | |
| Cambio de plan (local) | En el router: `/ppp secret set abonado1 profile=plan-768k` y reconectar abonado1 | La cola pasa a 768k sin tocar el abonado | `/queue simple print`; bandwidth-test | |
| Router cargado | bandwidth-test en los dos abonados a la vez | La CPU del router sube | `/system resource print` en el router; después, el tablero de Grafana | |

Después de cada prueba, **volver todo a como estaba** y verificar que los dos abonados reconectan.

---

## 3. Pruebas de falla con el sistema completo (día de la integración)

| Prueba | Cómo se provoca | Qué esperamos | Dónde mirar | Qué pasó |
|---|---|---|---|---|
| Se cae el RADIUS | Apagar el contenedor de FreeRADIUS | Los abonados ya conectados siguen navegando (el router ya los autorizó). Uno que se reconecta no puede entrar. El accounting deja de actualizarse | `/log print` en el router; `radacct` en la base | |
| Se cae la base | Apagar el contenedor de PostgreSQL, con FreeRADIUS prendido | FreeRADIUS no puede verificar a nadie. Comparar con la prueba anterior | Log de FreeRADIUS (`freeradius -X`); log del router | |
| Secreto distinto | Cambiar el secreto en un solo lado | El RADIUS ignora los pedidos y el router dice que no responde | `freeradius -X` (¿llega el pedido?); log del router | |
| Contraseña incorrecta | Cambiar la clave en un abonado | Rechazo, registrado como intento fallido | Tabla `radpostauth`; log del router | |
| Moroso | Conectar con `moroso`/`clave3` | Rechazo | Log del router; `radpostauth` | |
| Cambio de plan | Pasar a abonado1 a 768k en la base y reconectar | La velocidad cambia sin tocar el router | `/queue simple print`; bandwidth-test | |
| Corte en el momento | Bloquear a un abonado conectado y mandar un Disconnect | Se desconecta al instante y no puede volver a entrar | `/ppp active print`; log del router | |
| Los dos abonados con tráfico | bandwidth-test o script en los dos a la vez | Se reparten ~1 Mbps (límite de licencia). La CPU sube en el tablero | Grafana; `radacct` | |
