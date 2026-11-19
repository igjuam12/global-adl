-- ==============================================================================
-- 02-datos-acordados.sql: Clientes NAS, Abonados, Grupos y Planes Comerciales
-- Cátedra: Administración de Servicios en Linux - UTN FRM
-- Responsable: Parte 1 (Base de Datos)
-- ==============================================================================

-- 1. Declarar el router MikroTik (isp-router) como cliente NAS autorizado
-- Secreto acordado en plan-de-trabajo.md: IspUtnRadius2026
-- IP del router en la red de servicios acordada: 10.10.50.1
INSERT INTO nas (nasname, shortname, type, secret, description)
VALUES 
    ('10.10.50.1',    'isp-router',        'mikrotik', 'IspUtnRadius2026', 'Router de borde ISP (IP acordada)'),
    ('10.10.50.0/24', 'isp-servicios-net', 'mikrotik', 'IspUtnRadius2026', 'Subred de servicios acordada'),
    ('127.0.0.1',     'localhost-test',    'other',    'IspUtnRadius2026', 'Pruebas locales con radtest'),
    ('192.168.56.10', 'chr-hostonly',      'mikrotik', 'IspUtnRadius2026', 'Compatibilidad red solo-anfitrion'),
    ('192.168.56.0/24','hostonly-net',     'mikrotik', 'IspUtnRadius2026', 'Compatibilidad subred solo-anfitrion')
ON CONFLICT DO NOTHING;

-- 2. Credenciales de los abonados (radcheck)
-- Se usa Cleartext-Password para permitir la autenticación por desafío CHAP/MS-CHAPv2 de PPPoE
-- Se configuran las claves acordadas en plan-de-trabajo.md (y las de la guia de investigacion por compatibilidad)
INSERT INTO radcheck (username, attribute, op, value)
VALUES 
    ('abonado1', 'Cleartext-Password', ':=', 'clave1'),
    ('abonado2', 'Cleartext-Password', ':=', 'clave2'),
    ('moroso',   'Cleartext-Password', ':=', 'clave3')
ON CONFLICT DO NOTHING;

-- 3. Asignación de abonados a grupos/planes comerciales (radusergroup)
INSERT INTO radusergroup (username, groupname, priority)
VALUES 
    ('abonado1', 'plan-10m', 1),
    ('abonado2', 'plan-50m', 1),
    ('moroso',   'morosos',  1)
ON CONFLICT DO NOTHING;

-- 4. Definición de Atributos de los Planes Comerciales (radgroupreply)
-- NOTA TÉCNICA (Decisión documentada en notas/agustin.md):
-- Aunque comercialmente los planes se denominan 'plan-10m' y 'plan-50m', la licencia gratuita
-- de MikroTik CHR limita el throughput a un máximo de 1 Mbps por interfaz (verificado en la
-- Práctica 8 de Redes y en la documentación oficial de MikroTik).
-- Si inyectáramos 10M y 50M, la saturación la provocaría el kernel de la CHR y nunca las colas dinámicas.
-- Por ello, inyectamos velocidades controladas sub-1Mbps:
--   plan-10m -> 256 kbps subida / 512 kbps bajada
--   plan-50m -> 512 kbps subida / 768 kbps bajada
-- Se definen también los alias 'plan-basico' y 'plan-plus' para total compatibilidad.
INSERT INTO radgroupreply (groupname, attribute, op, value)
VALUES 
    -- Plan 10M (Tasa de laboratorio: 256k/512k)
    ('plan-10m',    'Mikrotik-Rate-Limit', ':=', '256k/512k'),
    ('plan-10m',    'Framed-Protocol',     '=',  'PPP'),
    ('plan-10m',    'Service-Type',        '=',  'Framed-User'),

    -- Plan 50M (Tasa de laboratorio: 512k/768k)
    ('plan-50m',    'Mikrotik-Rate-Limit', ':=', '512k/768k'),
    ('plan-50m',    'Framed-Protocol',     '=',  'PPP'),
    ('plan-50m',    'Service-Type',        '=',  'Framed-User'),

    -- Alias de compatibilidad con guia-proyecto-radius.md
    ('plan-basico', 'Mikrotik-Rate-Limit', ':=', '256k/512k'),
    ('plan-basico', 'Framed-Protocol',     '=',  'PPP'),
    ('plan-basico', 'Service-Type',        '=',  'Framed-User'),
    ('plan-plus',   'Mikrotik-Rate-Limit', ':=', '512k/768k'),
    ('plan-plus',   'Framed-Protocol',     '=',  'PPP'),
    ('plan-plus',   'Service-Type',        '=',  'Framed-User')
ON CONFLICT DO NOTHING;

-- 5. Regla de Bloqueo para el Grupo 'morosos' (radgroupcheck)
-- NOTA TÉCNICA (Decisión de diseño):
-- El bloqueo se implementa a nivel de grupo asignando Auth-Type := Reject.
-- De esta forma, FreeRADIUS rechaza al abonado de inmediato sin validar credenciales.
-- Cuando el abonado regulariza su deuda, se ejecuta:
--   UPDATE radusergroup SET groupname = 'plan-10m' WHERE username = 'moroso';
-- y el cliente queda habilitado automáticamente sin reiniciar servicios ni tocar el router.
INSERT INTO radgroupcheck (groupname, attribute, op, value)
VALUES 
    ('morosos', 'Auth-Type', ':=', 'Reject'),
    ('bloqueado', 'Auth-Type', ':=', 'Reject')
ON CONFLICT DO NOTHING;
