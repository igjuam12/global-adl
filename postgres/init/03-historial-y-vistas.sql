-- ==============================================================================
-- 03-historial-y-vistas.sql: historial del accounting y vistas para el tablero
-- Cátedra: Administración de Servicios en Linux - UTN FRM
-- Responsable: Parte 1 (Base de Datos)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Historial del accounting
-- ------------------------------------------------------------------------------
-- El problema: "radacct" guarda UNA fila por conexión y la va pisando con cada
-- aviso del router. Sirve para saber cuánto lleva consumido un abonado, pero no
-- cuánto consumía hace diez minutos: es la última foto, no la película.
--
-- La solución: cada vez que FreeRADIUS inserta o actualiza una fila de radacct,
-- un disparador (trigger) copia los contadores a esta tabla junto con la hora.
-- Con dos copias seguidas se calcula la velocidad: bytes de diferencia sobre
-- segundos de diferencia.
CREATE TABLE radacct_historial (
    id            BIGSERIAL PRIMARY KEY,
    momento       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    acctuniqueid  TEXT NOT NULL,              -- a qué conexión pertenece
    username      TEXT,
    bytes_subida  BIGINT NOT NULL DEFAULT 0,  -- lo que el router recibió del abonado
    bytes_bajada  BIGINT NOT NULL DEFAULT 0,  -- lo que el router le mandó al abonado
    segundos      BIGINT NOT NULL DEFAULT 0   -- duración de la conexión hasta ese momento
);
CREATE INDEX radacct_historial_momento ON radacct_historial (momento);
CREATE INDEX radacct_historial_sesion  ON radacct_historial (acctuniqueid, momento);

-- SECURITY DEFINER: la función corre con los permisos de su dueño. Así el rol
-- con el que entra FreeRADIUS no necesita ningún permiso sobre esta tabla.
CREATE FUNCTION guardar_historial_accounting() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO radacct_historial (acctuniqueid, username, bytes_subida, bytes_bajada, segundos)
    VALUES (NEW.acctuniqueid, NEW.username,
            COALESCE(NEW.acctinputoctets, 0),
            COALESCE(NEW.acctoutputoctets, 0),
            COALESCE(NEW.acctsessiontime, 0));
    RETURN NEW;
END
$$;

CREATE TRIGGER radacct_guardar_historial
    AFTER INSERT OR UPDATE ON radacct
    FOR EACH ROW EXECUTE FUNCTION guardar_historial_accounting();

-- ------------------------------------------------------------------------------
-- 2. Vistas para el tablero
-- ------------------------------------------------------------------------------
-- Grafana no lee las tablas del RADIUS: lee estas vistas. Son el "contrato"
-- entre la base y el tablero, y por acá no sale ninguna contraseña.

-- Cada abonado con su plan, su velocidad y si está suspendido
CREATE VIEW v_abonados AS
SELECT c.username AS abonado,
       p.groupname AS plan,
       r.value     AS velocidad,
       EXISTS (SELECT 1 FROM radusergroup m
               WHERE m.username = c.username AND m.groupname = 'morosos') AS suspendido
FROM radcheck c
LEFT JOIN LATERAL (
    SELECT g.groupname FROM radusergroup g
    WHERE g.username = c.username AND g.groupname <> 'morosos'
    ORDER BY g.priority LIMIT 1
) p ON true
LEFT JOIN radgroupreply r
       ON r.groupname = p.groupname AND r.attribute = 'Mikrotik-Rate-Limit'
WHERE c.attribute = 'Cleartext-Password';

-- Cada conexión, con un estado calculado.
-- "sin noticias": sigue abierta pero hace más de 3 minutos que el router no
-- informa nada. El router avisa cada minuto, así que faltaron tres avisos
-- seguidos: se apagó el router o se cortó la red de servicios.
--
-- Los tres horarios (inicio, ultima_noticia, fin) salen del historial, o sea
-- del reloj de la base: cuándo llegó el primer aviso y cuándo el último. No
-- usamos la hora que dice el router porque no es confiable: lo vimos 46
-- minutos adelantado, y recién reiniciado manda avisos antes de haber
-- sincronizado su reloj. Con el reloj del servidor el tablero siempre cierra.
CREATE VIEW v_sesiones AS
SELECT a.acctuniqueid       AS sesion,
       a.username           AS abonado,
       a.framedipaddress    AS ip,
       a.callingstationid   AS mac,
       u.primer_aviso       AS inicio,
       u.ultimo_aviso       AS ultima_noticia,
       CASE WHEN a.acctstoptime IS NOT NULL THEN u.ultimo_aviso END AS fin,
       a.acctsessiontime    AS segundos,
       a.acctinputoctets    AS bytes_subida,
       a.acctoutputoctets   AS bytes_bajada,
       a.acctterminatecause AS causa_fin,
       CASE
           WHEN a.acctstoptime IS NOT NULL THEN 'cerrada'
           WHEN u.ultimo_aviso < now() - interval '3 minutes' THEN 'sin noticias'
           ELSE 'activa'
       END AS estado
FROM radacct a
LEFT JOIN LATERAL (
    SELECT min(h.momento) AS primer_aviso, max(h.momento) AS ultimo_aviso
    FROM radacct_historial h
    WHERE h.acctuniqueid = a.acctuniqueid
) u ON true;

-- Tráfico de cada abonado a lo largo del tiempo. Cada fila es el tramo entre
-- dos avisos seguidos de la misma conexión: cuántos bytes pasaron y a qué
-- velocidad promedio, en bits por segundo.
-- lag() trae el valor de la copia anterior de la misma conexión.
CREATE VIEW v_trafico AS
SELECT momento, abonado,
       dif_subida AS bytes_subida,
       dif_bajada AS bytes_bajada,
       round(dif_subida * 8 / segundos_entre) AS bps_subida,
       round(dif_bajada * 8 / segundos_entre) AS bps_bajada
FROM (
    SELECT h.momento,
           h.username AS abonado,
           h.bytes_subida - lag(h.bytes_subida) OVER w AS dif_subida,
           h.bytes_bajada - lag(h.bytes_bajada) OVER w AS dif_bajada,
           extract(epoch FROM h.momento - lag(h.momento) OVER w) AS segundos_entre
    FROM radacct_historial h
    WINDOW w AS (PARTITION BY h.acctuniqueid ORDER BY h.momento)
) t
WHERE segundos_entre >= 10 AND dif_subida >= 0 AND dif_bajada >= 0;

-- Intentos de conexión, aceptados y rechazados. Sin la columna "pass".
-- (El motivo de cada rechazo y la MAC desde la que se intentó no están en la
-- base: quedan en el log de FreeRADIUS, que también llega a Grafana.)
CREATE VIEW v_logins AS
SELECT authdate AS momento,
       username AS abonado,
       reply    AS respuesta
FROM radpostauth;
