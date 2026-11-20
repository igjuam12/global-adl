-- ==============================================================================
-- datos-prueba-sinteticos.sql: datos inventados para probar el tablero sin router
-- Cátedra: Administración de Servicios en Linux - UTN FRM
-- Responsable: Parte 1 (Base de Datos)
-- ==============================================================================
-- Sirve para diseñar y probar los paneles de accounting cuando las VMs de
-- MikroTik están apagadas. NO se carga solo: está fuera de init/ a propósito,
-- para que el tablero nunca muestre conexiones que no existen.
--
-- Cargarlo (en isp-servicios, parado en /opt/isp-lab):
--   sudo docker compose exec -T postgres psql -U postgres -d radius < postgres/extras/datos-prueba-sinteticos.sql
--
-- Borrar solo lo inventado, sin tocar los datos reales:
--   DELETE FROM radacct           WHERE acctuniqueid LIKE 'uniq-sim-%';
--   DELETE FROM radacct_historial WHERE acctuniqueid LIKE 'uniq-sim-%';
--   DELETE FROM radpostauth       WHERE class = 'sim';
-- ==============================================================================

-- 1. Conexiones simuladas en radacct
INSERT INTO radacct (
    acctsessionid, acctuniqueid, username, groupname, nasipaddress,
    acctstarttime, acctupdatetime, acctstoptime, acctinterval, acctsessiontime,
    acctinputoctets, acctoutputoctets, callingstationid, calledstationid,
    acctterminatecause, framedprotocol, framedipaddress
)
VALUES
    -- Conexión abierta de abonado1 (empezó hace 25 minutos)
    (
        'sess-sim-001', 'uniq-sim-001', 'abonado1', 'plan-512k', '10.10.50.1'::inet,
        NOW() - INTERVAL '25 minutes', NOW() - INTERVAL '20 seconds', NULL, 60, 1500,
        15728640, 83886080, '08:00:27:AA:BB:01', 'isp',
        '', 'PPP', '100.64.1.10'::inet
    ),
    -- Conexión abierta de abonado2 (empezó hace 12 minutos)
    (
        'sess-sim-002', 'uniq-sim-002', 'abonado2', 'plan-768k', '10.10.50.1'::inet,
        NOW() - INTERVAL '12 minutes', NOW() - INTERVAL '10 seconds', NULL, 60, 720,
        41943040, 262144000, '08:00:27:AA:BB:02', 'isp',
        '', 'PPP', '100.64.1.11'::inet
    ),
    -- Conexión cerrada de abonado1 (duró una hora y la cerró el abonado)
    (
        'sess-sim-000', 'uniq-sim-000', 'abonado1', 'plan-512k', '10.10.50.1'::inet,
        NOW() - INTERVAL '2 hours', NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', 60, 3600,
        31457280, 157286400, '08:00:27:AA:BB:01', 'isp',
        'User-Request', 'PPP', '100.64.1.10'::inet
    );

-- Ojo: en el tablero estas conexiones abiertas pasan a "sin noticias" a los 3
-- minutos de cargadas, porque nadie manda avisos por ellas. Sirve justamente
-- para ver ese panel en rojo.

-- 2. Intentos de conexión simulados en radpostauth
-- La columna "pass" queda vacía, igual que con los abonados reales (MS-CHAPv2).
-- class = 'sim' marca estas filas para poder borrarlas después.
INSERT INTO radpostauth (username, pass, reply, authdate, class)
VALUES
    ('abonado1', '', 'Access-Accept', NOW() - INTERVAL '25 minutes', 'sim'),
    ('abonado2', '', 'Access-Accept', NOW() - INTERVAL '12 minutes', 'sim'),
    ('moroso',   '', 'Access-Reject', NOW() - INTERVAL '8 minutes',  'sim'),
    ('moroso',   '', 'Access-Reject', NOW() - INTERVAL '7 minutes',  'sim'),
    ('moroso',   '', 'Access-Reject', NOW() - INTERVAL '5 minutes',  'sim'),
    ('abonado1', '', 'Access-Accept', NOW() - INTERVAL '2 hours',    'sim');
