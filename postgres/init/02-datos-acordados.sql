-- ==============================================================================
-- 02-datos-acordados.sql: abonados, planes y regla de bloqueo
-- Cátedra: Administración de Servicios en Linux - UTN FRM
-- Responsable: Parte 1 (Base de Datos)
--
-- Los valores salen de plan-de-trabajo.md. Este archivo corre una sola vez,
-- cuando la base se crea vacía.
-- ==============================================================================

-- 1. Credenciales de los abonados (radcheck)
-- Cleartext-Password: PPPoE autentica por desafío (CHAP / MS-CHAPv2). El abonado
-- nunca manda la clave: manda una cuenta hecha con ella, y para repetir esa
-- cuenta el servidor necesita conocer la clave original.
INSERT INTO radcheck (username, attribute, op, value) VALUES
    ('abonado1', 'Cleartext-Password', ':=', 'clave1'),
    ('abonado2', 'Cleartext-Password', ':=', 'clave2'),
    ('moroso',   'Cleartext-Password', ':=', 'clave3');

-- 2. Los planes (radgroupreply)
-- La velocidad vive en el plan y no en el abonado: con 5.000 abonados en dos
-- planes, la velocidad se escribe en dos lugares.
-- Mikrotik-Rate-Limit se escribe subida/bajada del abonado, igual que el
-- rate-limit de un perfil PPP. Son menores a 1 Mbps porque la licencia gratuita
-- de la CHR no pasa de 1 Mbps por interfaz.
INSERT INTO radgroupreply (groupname, attribute, op, value) VALUES
    ('plan-512k', 'Mikrotik-Rate-Limit', ':=', '512k/512k'),
    ('plan-768k', 'Mikrotik-Rate-Limit', ':=', '768k/768k');

-- 3. La regla de bloqueo (radgroupcheck)
-- Quien pertenece al grupo "morosos" es rechazado siempre, tenga bien o mal la clave.
INSERT INTO radgroupcheck (groupname, attribute, op, value) VALUES
    ('morosos', 'Auth-Type', ':=', 'Reject');

-- 4. Qué plan tiene cada abonado (radusergroup)
-- FreeRADIUS recorre los grupos de menor a mayor "priority" y se queda con el
-- primero que aplica. Por eso suspender a alguien es AGREGARLE el grupo
-- "morosos" con prioridad 0: gana ese y el plan queda guardado debajo. Al
-- rehabilitarlo se borra esa fila y vuelve a valer su plan.
INSERT INTO radusergroup (username, groupname, priority) VALUES
    ('abonado1', 'plan-512k', 1),
    ('abonado2', 'plan-768k', 1),
    ('moroso',   'plan-512k', 1),
    ('moroso',   'morosos',   0);

-- Los routers autorizados a consultar (clientes RADIUS) no se cargan acá: van en
-- freeradius/clients.conf, con el secreto tomado de una variable de entorno. La
-- tabla "nas" del esquema queda vacía y FreeRADIUS no la lee (read_clients = no).
