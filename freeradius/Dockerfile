# ==============================================================================
# Imagen de FreeRADIUS del proyecto
# Parte 2 (FreeRADIUS)
#
# Partimos de la imagen oficial, con la versión fija, y le cambiamos solo
# seis cosas. Todo lo demás queda como viene de fábrica.
# ==============================================================================
FROM freeradius/freeradius-server:3.2.10

# 1. Quién puede consultarnos: el router. Reemplaza al clients.conf de fábrica,
#    que trae un cliente de prueba con un secreto conocido por todos (testing123).
COPY --chown=root:freerad --chmod=640 clients.conf /etc/freeradius/clients.conf

# 2. De dónde leer abonados y planes, y dónde guardar el accounting: PostgreSQL.
#    FreeRADIUS trae los módulos en "mods-available" y solo usa los que tienen
#    un enlace en "mods-enabled". El de SQL viene sin activar.
COPY --chown=root:freerad --chmod=640 sql /etc/freeradius/mods-available/sql
RUN ln -s ../mods-available/sql /etc/freeradius/mods-enabled/sql

# 3. El "servidor de estado": responde si FreeRADIUS está vivo, solo desde
#    adentro del contenedor. Lo usa Docker para el control de salud.
RUN ln -s ../sites-available/status /etc/freeradius/sites-enabled/status

# 4. Anotar en el log cada intento de conexión ("Login OK" / "Login incorrect").
RUN sed -i 's/^\([[:space:]]*\)auth = no/\1auth = yes/' /etc/freeradius/radiusd.conf \
 && grep -q 'auth = yes' /etc/freeradius/radiusd.conf

# 5. No guardar claves en la tabla de intentos. De fábrica, cuando el pedido
#    trae la clave (PAP), FreeRADIUS la copia en radpostauth. Con PPPoE no pasa
#    (usa MS-CHAPv2 y la clave no viaja), pero una prueba a mano la dejaría
#    escrita. El grep hace fallar la construcción si el cambio no se aplicó.
RUN Q=/etc/freeradius/mods-config/sql/main/postgresql/queries.conf \
 && sed -i "s/'%{%{User-Password}:-%{Chap-Password}}'/''/" "$Q" \
 && ! grep -q 'User-Password' "$Q"

# 6. Escribir el log por la salida estándar en lugar de un archivo adentro del
#    contenedor: así se ve con "docker compose logs freeradius".
CMD ["-l", "stdout"]
