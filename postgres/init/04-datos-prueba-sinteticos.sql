-- ==============================================================================
-- 04-datos-prueba-sinteticos.sql: Datos de simulación para pruebas de Grafana
-- Cátedra: Administración de Servicios en Linux - UTN FRM
-- Responsable: Parte 1 (Base de Datos)
-- ==============================================================================
-- Este archivo permite que la Parte 1 y la Parte 5 puedan diseñar, probar y validar
-- todos los paneles SQL del tablero de Grafana de forma autónoma, sin necesidad
-- de que las VMs de MikroTik o los abonados estén encendidos.
-- Para limpiar estos datos de prueba cuando se conecte el router real, basta con:
--   docker compose exec postgres psql -U radius -d radius -c "TRUNCATE radacct, radpostauth;"
-- ==============================================================================

-- 1. Sesiones de Accounting simuladas en radacct
INSERT INTO radacct (
    acctsessionid, acctuniqueid, username, groupname, nasipaddress,
    acctstarttime, acctupdatetime, acctstoptime, acctinterval, acctsessiontime,
    acctinputoctets, acctoutputoctets, callingstationid, calledstationid,
    acctterminatecause, framedprotocol, framedipaddress
)
VALUES
    -- Sesión activa 1: abonado1 (conectado hace 25 min, con interim reciente hace 20 seg)
    (
        'sess-sim-001', 'uniq-sim-001', 'abonado1', 'plan-10m', '10.10.50.1'::inet,
        NOW() - INTERVAL '25 minutes', NOW() - INTERVAL '20 seconds', NULL, 60, 1500,
        15728640, 83886080, '08:00:27:AA:BB:01', 'vlan-acceso',
        '', 'PPP', '100.64.1.10'::inet
    ),
    -- Sesión activa 2: abonado2 (conectado hace 12 min, con interim reciente hace 10 seg)
    (
        'sess-sim-002', 'uniq-sim-002', 'abonado2', 'plan-50m', '10.10.50.1'::inet,
        NOW() - INTERVAL '12 minutes', NOW() - INTERVAL '10 seconds', NULL, 60, 720,
        41943040, 262144000, '08:00:27:AA:BB:02', 'vlan-acceso',
        '', 'PPP', '100.64.1.11'::inet
    ),
    -- Sesión cerrada histórica: abonado1 (conectado durante 1 hora y cerrada normalmente)
    (
        'sess-sim-000', 'uniq-sim-000', 'abonado1', 'plan-10m', '10.10.50.1'::inet,
        NOW() - INTERVAL '2 hours', NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', 60, 3600,
        31457280, 157286400, '08:00:27:AA:BB:01', 'vlan-acceso',
        'User-Request', 'PPP', '100.64.1.10'::inet
    ),
    -- Sesión fantasma de prueba: acctstoptime IS NULL pero sin actualización hace 15 minutos (> 3 min)
    -- Sirve para verificar que el panel de "Sesiones Fantasma" de Grafana se pinte en alerta roja (> 0)
    (
        'sess-sim-ghost', 'uniq-sim-ghost', 'abonado2', 'plan-50m', '10.10.50.1'::inet,
        NOW() - INTERVAL '45 minutes', NOW() - INTERVAL '15 minutes', NULL, 60, 1800,
        5242880, 20971520, '08:00:27:99:99:99', 'vlan-acceso',
        '', 'PPP', '100.64.1.99'::inet
    )
ON CONFLICT (acctuniqueid) DO NOTHING;

-- 2. Historial de intentos de autenticación en radpostauth
-- Sirve para alimentar el gráfico de líneas de intentos aceptados vs rechazados
INSERT INTO radpostauth (username, pass, reply, callingstationid, calledstationid, authdate)
VALUES
    ('abonado1', 'clave1', 'Access-Accept', '08:00:27:AA:BB:01', 'vlan-acceso', NOW() - INTERVAL '25 minutes'),
    ('abonado2', 'clave2', 'Access-Accept', '08:00:27:AA:BB:02', 'vlan-acceso', NOW() - INTERVAL '12 minutes'),
    ('moroso',   'clave3', 'Access-Reject', '08:00:27:AA:BB:03', 'vlan-acceso', NOW() - INTERVAL '8 minutes'),
    ('moroso',   'clave3', 'Access-Reject', '08:00:27:AA:BB:03', 'vlan-acceso', NOW() - INTERVAL '7 minutes'),
    ('moroso',   'clave3', 'Access-Reject', '08:00:27:AA:BB:03', 'vlan-acceso', NOW() - INTERVAL '5 minutes'),
    ('abonado1', 'clave1', 'Access-Accept', '08:00:27:AA:BB:01', 'vlan-acceso', NOW() - INTERVAL '2 hours');
