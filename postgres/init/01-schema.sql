-- ==============================================================================
-- 01-schema.sql: Esquema Oficial de FreeRADIUS 3.x para PostgreSQL
-- Fuente: /etc/raddb/mods-config/sql/main/postgresql/schema.sql
-- Cátedra: Administración de Servicios en Linux - UTN FRM
-- Responsable: Parte 1 (Base de Datos)
-- ==============================================================================

-- 1. Verificación de credenciales de usuario (Autenticación)
CREATE TABLE IF NOT EXISTS radcheck (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL DEFAULT '',
    attribute TEXT NOT NULL DEFAULT '',
    op VARCHAR(2) NOT NULL DEFAULT '==',
    value TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS radcheck_username ON radcheck (username, attribute);

-- 2. Atributos devueltos por usuario puntual (Autorización individual)
CREATE TABLE IF NOT EXISTS radreply (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL DEFAULT '',
    attribute TEXT NOT NULL DEFAULT '',
    op VARCHAR(2) NOT NULL DEFAULT '=',
    value TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS radreply_username ON radreply (username, attribute);

-- 3. Verificaciones condicionales por grupo (ej. reglas de Auth-Type Reject)
CREATE TABLE IF NOT EXISTS radgroupcheck (
    id SERIAL PRIMARY KEY,
    groupname TEXT NOT NULL DEFAULT '',
    attribute TEXT NOT NULL DEFAULT '',
    op VARCHAR(2) NOT NULL DEFAULT '==',
    value TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS radgroupcheck_groupname ON radgroupcheck (groupname, attribute);

-- 4. Atributos devueltos por grupo (Planes comerciales: colas, rate-limit)
CREATE TABLE IF NOT EXISTS radgroupreply (
    id SERIAL PRIMARY KEY,
    groupname TEXT NOT NULL DEFAULT '',
    attribute TEXT NOT NULL DEFAULT '',
    op VARCHAR(2) NOT NULL DEFAULT '=',
    value TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS radgroupreply_groupname ON radgroupreply (groupname, attribute);

-- 5. Mapeo de abonados a grupos/planes comerciales
CREATE TABLE IF NOT EXISTS radusergroup (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL DEFAULT '',
    groupname TEXT NOT NULL DEFAULT '',
    priority INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS radusergroup_username ON radusergroup (username);

-- 6. Registro de Accounting (Sesiones activas, cerradas, tiempos y octetos)
CREATE TABLE IF NOT EXISTS radacct (
    radacctid           BIGSERIAL PRIMARY KEY,
    acctsessionid       TEXT NOT NULL,
    acctuniqueid        TEXT NOT NULL UNIQUE,
    username            TEXT,
    groupname           TEXT,
    realm               TEXT,
    nasipaddress        INET NOT NULL,
    nasportid           TEXT,
    nasporttype         TEXT,
    acctstarttime       TIMESTAMP WITH TIME ZONE,
    acctupdatetime      TIMESTAMP WITH TIME ZONE,
    acctstoptime        TIMESTAMP WITH TIME ZONE,
    acctinterval        BIGINT,
    acctsessiontime     BIGINT,
    acctauthentic       TEXT,
    connectinfo_start   TEXT,
    connectinfo_stop    TEXT,
    acctinputoctets     BIGINT,
    acctoutputoctets    BIGINT,
    calledstationid     TEXT,
    callingstationid    TEXT,
    acctterminatecause  TEXT,
    servicetype         TEXT,
    framedprotocol      TEXT,
    framedipaddress     INET,
    framedipv6address   INET,
    framedipv6prefix    INET,
    framedinterfaceid   TEXT,
    delegatedipv6prefix INET,
    class               TEXT
);

-- Índices de alto rendimiento para tracking de sesiones de FreeRADIUS
CREATE INDEX IF NOT EXISTS radacct_username ON radacct (username);
CREATE INDEX IF NOT EXISTS radacct_active_session_idx ON radacct (acctuniqueid) WHERE acctstoptime IS NULL;
CREATE INDEX IF NOT EXISTS radacct_bulk_close ON radacct (nasipaddress, acctstarttime) WHERE acctstoptime IS NULL;
CREATE INDEX IF NOT EXISTS radacct_bulk_timeout ON radacct (acctstoptime NULLS FIRST, acctupdatetime);
CREATE INDEX IF NOT EXISTS radacct_active ON radacct (acctstoptime);

-- 7. Auditoría de intentos de login (Aceptados y Rechazados)
CREATE TABLE IF NOT EXISTS radpostauth (
    id                  BIGSERIAL PRIMARY KEY,
    username            TEXT NOT NULL,
    pass                TEXT,
    reply               TEXT,
    calledstationid     TEXT,
    callingstationid    TEXT,
    authdate            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    class               TEXT
);
CREATE INDEX IF NOT EXISTS radpostauth_authdate ON radpostauth (authdate);

-- 8. Clientes NAS (Routers autorizados a consultar el servidor RADIUS)
CREATE TABLE IF NOT EXISTS nas (
    id          SERIAL PRIMARY KEY,
    nasname     TEXT NOT NULL,
    shortname   TEXT NOT NULL,
    type        TEXT NOT NULL DEFAULT 'other',
    ports       INTEGER,
    secret      TEXT NOT NULL,
    server      TEXT,
    community   TEXT,
    description TEXT
);
CREATE INDEX IF NOT EXISTS nas_nasname ON nas (nasname);
