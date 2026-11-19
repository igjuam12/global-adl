#!/bin/bash
set -e

# ==============================================================================
# 03-seguridad-grafana.sh: Creación del rol de solo lectura grafana_ro
# Cátedra: Administración de Servicios en Linux - UTN FRM
# Responsable: Parte 1 (Base de Datos)
# ==============================================================================

# Se utiliza la variable de entorno GRAFANA_DB_PASSWORD proveniente de .env
PASS="${GRAFANA_DB_PASSWORD:-LabGrafanaRO-2026}"

echo "=== [PostgreSQL Init] Configurando usuario de solo lectura: grafana_ro ==="

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
-- 1. Crear el rol de login si no existe
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'grafana_ro') THEN
        CREATE ROLE grafana_ro WITH LOGIN PASSWORD '$PASS';
    ELSE
        ALTER ROLE grafana_ro WITH PASSWORD '$PASS';
    END IF;
END
\$\$;

-- 2. Conceder acceso a la base de datos y esquema público
GRANT CONNECT ON DATABASE radius TO grafana_ro;
GRANT USAGE ON SCHEMA public TO grafana_ro;

-- 3. Principio de Mínimo Privilegio:
-- Conceder SOLO lectura (SELECT) en tablas de métricas, histórico, planes y auditoría
GRANT SELECT ON radacct, radpostauth, radusergroup, radgroupreply, radgroupcheck, nas TO grafana_ro;

-- 4. Seguridad estricta (Mínimo privilegio):
-- Revocar explícitamente cualquier permiso sobre radcheck (donde residen las contraseñas de los usuarios)
REVOKE ALL ON radcheck FROM grafana_ro;

EOSQL

echo "=== [PostgreSQL Init] Usuario grafana_ro configurado con éxito. ==="
