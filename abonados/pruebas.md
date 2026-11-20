# Parte 4 · Pruebas

Para cada prueba se anota **antes** qué esperamos y **después** qué pasó de verdad. Si no coincide, mejor: es material para contar en la presentación ("cómo diagnosticamos lo que falló").

---

## 1. Pruebas de tráfico (bajada: jue 19-nov · subida: vie 20-nov · laboratorio de la parte 4)

Herramienta: `/tool bandwidth-test` desde cada abonado contra el router (100.64.1.1), TCP, 30 segundos.

Planes (los de la base): abonado1 `plan-10m` = 256k subida / 512k bajada · abonado2 `plan-50m` = 512k subida / 768k bajada.

| Prueba | Esperado | Medido | ¿Coincide? | Comentario |
|---|---|---|---|---|
| abonado1 bajada | ~512k | 497 kbps | ✅ | 97 % del plan. La diferencia son los encabezados (PPPoE, IP, TCP) |
| abonado1 subida | ~256k | 240,7 kbps | ✅ | 94 %. Medido dos veces, mismo resultado. (El 19-nov, con el perfil viejo de 512k, había dado 487k) |
| abonado2 bajada | ~768k | 746 kbps | ✅ | 97 % |
| abonado2 subida | ~512k | 486 kbps | ✅ | 95 %. Medido dos veces: 485,9 y 486,7 kbps. (El 19-nov, con el perfil viejo de 768k, había dado 734k) |
| Los dos juntos, bajada | 512k + 768k | 351 + 606 ≈ **957 kbps** | ❌ | Límite de 1 Mbps por interfaz de la licencia gratuita del CHR. CPU máxima 16 %: no era la CPU |
| Los dos juntos, subida | 256k + 512k = 768k, entra en 1 Mbps | 240,7 + 486,7 ≈ **727 kbps** | ✅ | Cada uno llegó a su plan. CPU máxima 15 % |

**Observaciones:**
- La cola del plan también frena el tráfico que va al propio router (no era seguro: lo comprobamos).
- En la prueba simultánea, abonado1 arrancó unos segundos después. Su promedio de los últimos 10 s fue 294 kbps, pero al final subió a 564 kbps: cuando terminó la prueba de abonado2, abonado1 quedó con el "caño" libre.
- **Decisión del grupo (opción B):** mantener los planes y explicar el límite en la presentación.
- Las bajadas se midieron el 19-nov con perfiles de 512k/512k y 768k/768k. El 20-nov se alinearon los perfiles con la base (cambió solo la subida), así que las bajadas siguen valiendo. Al reconectar, `/queue simple print` mostró `max-limit=256k/512k` (abonado1) y `max-limit=512k/768k` (abonado2).
- **Por qué al subir juntos sí llegan y al bajar no:** el límite de la licencia es sobre lo que **manda** cada interfaz. Al bajar, la que manda es la `ether2` del router, una sola para los dos abonados: 512k + 768k no entran en ~1 Mbps. Al subir, cada abonado manda por su propia `ether2` (cada uno tiene su límite) y el router solo recibe: 768k en total, sin problema.

---

## 2. Pruebas de falla que se pueden hacer sin RADIUS

| Prueba | Cómo se provoca | Qué esperamos | Dónde mirar | Qué pasó |
|---|---|---|---|---|
| Contraseña incorrecta | En abonado1: `/interface pppoe-client set wan-pppoe password=mal` | El router rechaza la conexión; el abonado no recibe IP | `/log print` en el router y en el abonado; `/interface pppoe-client monitor wan-pppoe` | |
| VLAN distinta | En abonado1: `/interface vlan set vlan-acceso vlan-id=200` | El abonado no encuentra el servidor ("searching…") y **ningún log menciona la VLAN** | `monitor` en el abonado; `/interface vlan print` en las dos puntas | |
| Cambio de plan (local) | En el router: `/ppp secret set abonado1 profile=plan-50m` y reconectar abonado1 | La cola pasa a 512k/768k sin tocar el abonado | `/queue simple print`; bandwidth-test | |
| Router cargado | bandwidth-test en los dos abonados a la vez | La CPU del router sube | `/system resource print` en el router; después, el tablero de Grafana | |

Después de cada prueba, **volver todo a como estaba** y verificar que los dos abonados reconectan.

---

## 3. Pruebas de falla con el sistema completo (al integrar en la PC)

Antes de empezar: la base trae sesiones e intentos de login **inventados** (`04-datos-prueba-sinteticos.sql`) para probar Grafana. Hay que distinguirlos de los reales, o acordar con agus cuándo borrarlos.

| Prueba | Cómo se provoca | Qué esperamos | Dónde mirar | Qué pasó |
|---|---|---|---|---|
| Se cae el RADIUS | Apagar el contenedor de FreeRADIUS | Los abonados ya conectados siguen navegando (el router ya los autorizó). Uno que se reconecta no puede entrar. El accounting deja de actualizarse | `/log print` en el router; `radacct` en la base | |
| Se cae la base | Apagar el contenedor de PostgreSQL, con FreeRADIUS prendido | FreeRADIUS no puede verificar a nadie. Comparar con la prueba anterior. Ojo (notas de nico): si FreeRADIUS **arranca** sin la base, no carga a ningún router, porque los lee de la tabla `nas` | Log de FreeRADIUS (`freeradius -X`); log del router | |
| Secreto distinto | Cambiar el secreto en un solo lado | El RADIUS ignora los pedidos y el router dice que no responde | `freeradius -X` (¿llega el pedido?); log del router | |
| Contraseña incorrecta | Cambiar la clave en un abonado | Rechazo, registrado como intento fallido | Tabla `radpostauth`; log del router | |
| Moroso | Conectar con `moroso`/`clave3` | Rechazo | Log del router; `radpostauth` | |
| Cambio de plan | Mover a abonado1 al grupo `plan-50m` en la base (`UPDATE radusergroup SET groupname = 'plan-50m' WHERE username = 'abonado1';`) y reconectar | La cola pasa de 256k/512k a 512k/768k sin tocar el router | `/queue simple print`; bandwidth-test | |
| Corte en el momento | Bloquear a un abonado conectado y mandar un Disconnect | Se desconecta al instante y no puede volver a entrar | `/ppp active print`; log del router | |
| Los dos abonados con tráfico | bandwidth-test o script en los dos a la vez | Se reparten ~1 Mbps (límite de licencia). La CPU sube en el tablero | Grafana; `radacct` | |
