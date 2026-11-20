#!/bin/bash
# ==============================================================================
# 04-roles-y-permisos.sh: los usuarios de la base y qué puede hacer cada uno
# Cátedra: Administración de Servicios en Linux - UTN FRM
# Responsable: Parte 1 (Base de Datos)
#
# Corre último, cuando las tablas y las vistas ya existen. Es un .sh y no un
# .sql porque necesita leer las contraseñas de las variables de entorno.
# ==============================================================================
set -euo pipefail

# Si falta alguna contraseña se corta acá, con un mensaje claro
: "${RADIUS_DB_PASSWORD:?falta RADIUS_DB_PASSWORD en .env}"
: "${GRAFANA_DB_PASSWORD:?falta GRAFANA_DB_PASSWORD en .env}"

# Mínimo privilegio, con tres usuarios:
#   postgres    administra: crea tablas y es quien usamos nosotros para operar
#   radius      lo usa FreeRADIUS: lee abonados y planes, escribe accounting
#   grafana_ro  lo usa Grafana: solo lee las vistas del tablero
#
# :'variable' hace que psql ponga las comillas: una clave con caracteres raros
# no rompe la consulta.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v clave_radius="$RADIUS_DB_PASSWORD" -v clave_grafana="$GRAFANA_DB_PASSWORD" <<'EOSQL'

CREATE ROLE radius     LOGIN PASSWORD :'clave_radius';
CREATE ROLE grafana_ro LOGIN PASSWORD :'clave_grafana';

-- Nadie más que estos dos roles (y el administrador) entra a la base
REVOKE ALL ON DATABASE radius FROM PUBLIC;
GRANT CONNECT ON DATABASE radius TO radius, grafana_ro;
GRANT USAGE ON SCHEMA public TO radius, grafana_ro;

-- FreeRADIUS: los mismos permisos que da su instalación oficial (setup.sql).
-- Lee quién es cada abonado y qué plan tiene...
GRANT SELECT ON radcheck, radreply, radusergroup, radgroupcheck, radgroupreply TO radius;
-- ...y escribe las conexiones y los intentos de login. No puede borrar nada.
GRANT SELECT, INSERT, UPDATE ON radacct, radpostauth TO radius;
GRANT USAGE, SELECT ON SEQUENCE radacct_radacctid_seq, radpostauth_id_seq TO radius;

-- Grafana: solo las vistas. No ve radcheck (las claves) ni ninguna tabla.
GRANT SELECT ON v_abonados, v_sesiones, v_trafico, v_logins TO grafana_ro;

EOSQL

echo "Roles creados: radius (FreeRADIUS) y grafana_ro (Grafana, solo vistas)."
