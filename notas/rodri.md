# Notas — Parte 4: Abonados y pruebas

**Responsable:** Rodri

Escribir **mientras** se trabaja, no al final. Es lo que preguntan en la presentación.

> Borrador con lo que hice hasta el jue 19-nov. Las partes entre [corchetes] las completo yo.

## 1. Qué investigué

Qué es mi pieza y qué papel cumple en el proyecto.

- Los abonados son los **clientes del ISP**. Cada uno es un MikroTik CHR que se conecta al router por **PPPoE**: se loguea con usuario y contraseña y recién ahí recibe una IP del pool.
- Lo hacen sobre la **VLAN 100**, una etiqueta que separa el tráfico de los abonados dentro del mismo cable. Tiene que ser el mismo número en el router y en los abonados.
- Son el **punto de partida del recorrido**: abonado → router → RADIUS → base → Grafana. Generan las conexiones y el tráfico que después aparecen en el accounting y en el tablero.
- **El abonado nunca habla con el RADIUS.** El cliente RADIUS es el router. Por eso la configuración de los abonados no cambia cuando el router pasa de usuarios locales a RADIUS.
- Para avanzar sin esperar a nadie, armé un **router de prueba** con usuarios locales (`/ppp secret`), que reemplaza al RADIUS, usando la configuración base del plan de trabajo.

## 2. Alternativas

Qué opciones había y por qué descarté cada una.

**Hacia dónde mandar el tráfico de prueba:**

| Opción | Por qué la descarté |
| --- | --- |
| De un abonado al otro | El tráfico atraviesa el router, pero las dos colas se mezclan (el de 768k queda frenado por el de 512k) y la IP del destino cambia en cada conexión |
| Hacia un servidor en isp-servicios | Rompe la regla de que los abonados no ven la red de servicios; habría que tocar rutas y firewall de otras partes |
| Darle internet real al router | Cambia la topología acordada |

**Qué hacer con el límite de 1 Mbps de la licencia:**

| Opción | Por qué la descarté |
| --- | --- |
| Bajar los planes a 256k/512k | Implicaba cambiar otra vez un dato común; el grupo prefirió explicarlo |
| Generar tráfico en distintos momentos | Más complicado y menos realista: en un ISP todos usan a la vez |
| Licencia de prueba de 60 días | Necesita cuenta en mikrotik.com e internet en cada CHR |

## 3. Qué elegí y por qué

- Abonados como **CHR clonados** de una base, con **MACs nuevas**, porque PPPoE distingue a cada abonado por su MAC.
- **bandwidth-test contra el router**: es simple, no necesita nada más y muestra el plan de cada abonado.
- **Planes 512k/768k (opción B, decisión del grupo):** por separado cada abonado llega a su plan; juntos se reparten ~1 Mbps, y lo explicamos con las mediciones.
- [Completar: por qué me pareció bien la opción B]

## 4. Qué hice

Los archivos que dejé en el repo y qué hace cada uno.

| Archivo | Qué hace |
| --- | --- |
| `abonados/README.md` | Receta paso a paso: armar los abonados, qué necesitan del router y cómo integrarlos con el router real y el RADIUS. Cada comando explicado |
| `abonados/abonado1.rsc`, `abonado2.rsc` | Configuración comentada de cada abonado, para importar en un CHR nuevo con `/import` |
| `abonados/laboratorio/isp-router-prueba.rsc` | El router de prueba que usé, con usuarios locales. No es el router oficial (ese es de nacho) |
| `abonados/export/` | Los `/export` reales de mis VMs, como respaldo |
| `abonados/pruebas.md` | Mediciones de velocidad y tabla de pruebas de falla |

## 5. Qué falló y cómo lo diagnostiqué

| Síntoma | Cómo lo diagnostiqué (comando o log) | Causa | Solución |
| --- | --- | --- | --- |
| Las placas aparecían como `ether2`-`ether4` en vez de `ether1`-`ether3` | `/interface ethernet print`, comparando las MAC con las de VirtualBox | La `chr-base` ya se había arrancado. RouterOS asocia cada nombre a una MAC; al clonar con MACs nuevas, les dio el siguiente nombre libre | Renombrar eligiendo cada placa por su MAC: `/interface ethernet set [find mac-address=...] name=ether1`. Además borré un cliente DHCP que apuntaba a la placa vieja (`*2` en el `/export`) |
| `expected end of command` y después `already have interface with such name` | Leyendo los dos errores y `/interface pppoe-client print detail` | Pegué el comando del cliente PPPoE en dos partes. La primera mitad era válida y creó `wan-pppoe` sin contraseña y apagada | Completarla con `set` en lugar de repetir el `add` |
| Los dos abonados juntos no llegan a su plan: 351k + 606k ≈ 957k, cuando los planes suman 1280k | bandwidth-test en los dos a la vez. Por separado daban 497k y 746k. CPU máxima 16 % | Límite de 1 Mbps por interfaz de la licencia gratuita del CHR. No era la CPU | Opción B: se mantienen los planes y se explica en la presentación |

## 6. Cómo usé la IA

Qué le pregunté, qué respondió mal y cómo me di cuenta.

- [Completar: qué le pregunté. Ej.: que me guíe paso a paso para crear las VMs y configurar PPPoE, explicando cada comando.]
- [Completar: qué respondió mal o qué tuve que corregir. Ej.: arrancó con los planes de 10M/50M del plan de trabajo; con el límite de la licencia que averigüé, no se iba a ver la diferencia.]
- [Completar: cómo me di cuenta. Ej.: midiendo con bandwidth-test y comparando con lo esperado.]
- La IA anticipó que la licencia podía limitar las pruebas simultáneas; lo comprobamos con mediciones antes de creerlo.
