# =====================================================================
# trafico.rsc - Tráfico automático, para que el tablero tenga movimiento
# Proyecto final RADIUS - Parte 4: abonados y pruebas
# RouterOS 7.20.4
#
# Sirve igual para abonado1 y para abonado2. Se carga después del archivo
# del abonado (abonado1.rsc o abonado2.rsc):   /import file-name=trafico.rsc
#
# Para frenarlo:   /system scheduler disable trafico
# Para seguirlo:   /system scheduler enable trafico
# =====================================================================

# Un "script" es una lista de comandos con nombre. Este baja datos del router
# durante 30 segundos y después le sube durante 20, con el usuario de pruebas
# (btest) que creó la parte 3. La velocidad la frena la cola del plan.
/system script add name=generar-trafico comment="30 s de bajada y 20 s de subida contra el router" source="/tool bandwidth-test address=100.64.1.1 user=btest password=BtestIsp2026 protocol=tcp direction=receive duration=30s; /tool bandwidth-test address=100.64.1.1 user=btest password=BtestIsp2026 protocol=tcp direction=transmit duration=20s"

# El "scheduler" es el cron de RouterOS: corre el script cada cierto tiempo.
/system scheduler add name=trafico interval=2m on-event=generar-trafico comment="genera trafico cada 2 minutos"

# abonado2 lo hace cada 3 minutos en vez de 2. Así a veces los dos bajan a la
# vez (y se reparten el tope de 1 Mbps de la licencia) y a veces uno solo.
:if ([/system identity get name] = "abonado2") do={ /system scheduler set trafico interval=3m comment="genera trafico cada 3 minutos" }
