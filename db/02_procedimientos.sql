-- =====================================================================
-- Sistema de permisos - Registro de Inasistencias o Permisos
-- Script 2 (Entrega 5): procedimientos almacenados.
-- El aplicativo NO ejecuta SQL directo sobre las tablas: toda lectura y
-- escritura se hace con CALL a estos procedimientos.
--   * sp_empleado_*      CRUD de empleados (baja lógica)
--   * sp_solicitud_*     CRUD de solicitudes (anulación lógica) y resolución
--   * sp_compensacion_*  detalle de compensación de horas
--   * sp_firma_*         firmas de la compensación
--   * sp_rep_01..10      reportes (todos usan JOIN)
-- =====================================================================
USE permisos_hora;

DROP PROCEDURE IF EXISTS sp_empleado_listar;
DROP PROCEDURE IF EXISTS sp_empleado_obtener;
DROP PROCEDURE IF EXISTS sp_empleado_insertar;
DROP PROCEDURE IF EXISTS sp_empleado_actualizar;
DROP PROCEDURE IF EXISTS sp_empleado_baja;
DROP PROCEDURE IF EXISTS sp_empleado_reactivar;
DROP PROCEDURE IF EXISTS sp_areas_listar;
DROP PROCEDURE IF EXISTS sp_solicitud_listar;
DROP PROCEDURE IF EXISTS sp_solicitud_obtener;
DROP PROCEDURE IF EXISTS sp_solicitud_insertar;
DROP PROCEDURE IF EXISTS sp_solicitud_actualizar;
DROP PROCEDURE IF EXISTS sp_solicitud_resolver;
DROP PROCEDURE IF EXISTS sp_solicitud_anular;
DROP PROCEDURE IF EXISTS sp_compensacion_listar;
DROP PROCEDURE IF EXISTS sp_compensacion_insertar;
DROP PROCEDURE IF EXISTS sp_compensacion_eliminar;
DROP PROCEDURE IF EXISTS sp_firma_registrar;
DROP PROCEDURE IF EXISTS sp_firma_quitar;
DROP PROCEDURE IF EXISTS sp_bitacora_listar;
DROP PROCEDURE IF EXISTS sp_panel_resumen;
DROP PROCEDURE IF EXISTS sp_rep_01_permisos_por_empleado;
DROP PROCEDURE IF EXISTS sp_rep_02_tope_semanal;
DROP PROCEDURE IF EXISTS sp_rep_03_tope_mensual;
DROP PROCEDURE IF EXISTS sp_rep_04_pendientes_por_area;
DROP PROCEDURE IF EXISTS sp_rep_05_compensaciones_firmas;
DROP PROCEDURE IF EXISTS sp_rep_06_saldo_por_compensar;
DROP PROCEDURE IF EXISTS sp_rep_07_historial;
DROP PROCEDURE IF EXISTS sp_rep_08_resumen_mensual_area;
DROP PROCEDURE IF EXISTS sp_rep_09_enrutamiento;
DROP PROCEDURE IF EXISTS sp_rep_10_ranking_minutos;

DELIMITER $$

-- =====================================================================
-- EMPLEADOS
-- =====================================================================

-- Lista empleados; p_buscar filtra por DNI, nombres, apellidos o área.
CREATE PROCEDURE sp_empleado_listar(IN p_buscar VARCHAR(60), IN p_solo_activos TINYINT)
BEGIN
  SELECT e.dni, e.nombres, e.apellidos, e.cargo, e.area, e.activo,
         DATE_FORMAT(e.fecha_baja, '%Y-%m-%d %H:%i') AS fecha_baja,
         (SELECT COUNT(*) FROM solicitud_permiso s
           WHERE s.dni = e.dni AND s.activo = 1) AS solicitudes
    FROM empleado e
   WHERE (p_solo_activos = 0 OR e.activo = 1)
     AND (p_buscar IS NULL OR p_buscar = ''
          OR e.dni LIKE CONCAT(p_buscar, '%')
          OR CONCAT(e.nombres, ' ', e.apellidos) LIKE CONCAT('%', p_buscar, '%')
          OR e.area LIKE CONCAT('%', p_buscar, '%'))
   ORDER BY e.activo DESC, e.apellidos, e.nombres;
END$$

CREATE PROCEDURE sp_empleado_obtener(IN p_dni CHAR(8))
BEGIN
  SELECT dni, nombres, apellidos, cargo, area, activo FROM empleado WHERE dni = p_dni;
END$$

CREATE PROCEDURE sp_empleado_insertar(IN p_dni CHAR(8), IN p_nombres VARCHAR(50),
  IN p_apellidos VARCHAR(50), IN p_cargo VARCHAR(30), IN p_area VARCHAR(30))
BEGIN
  IF EXISTS (SELECT 1 FROM empleado WHERE dni = p_dni) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un empleado con ese DNI';
  END IF;
  IF TRIM(p_nombres) NOT REGEXP '^[[:alpha:]]+([ .''-]+[[:alpha:]]+)*[.]?$'
     OR TRIM(p_apellidos) NOT REGEXP '^[[:alpha:]]+([ .''-]+[[:alpha:]]+)*[.]?$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Los nombres y apellidos solo admiten letras, espacios, guion o apóstrofo';
  END IF;
  IF TRIM(p_cargo) = '' OR TRIM(p_area) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cargo y el área son obligatorios';
  END IF;
  INSERT INTO empleado (dni, nombres, apellidos, cargo, area)
  VALUES (p_dni, TRIM(p_nombres), TRIM(p_apellidos), TRIM(p_cargo), TRIM(p_area));
  CALL sp_empleado_obtener(p_dni);
END$$

CREATE PROCEDURE sp_empleado_actualizar(IN p_dni CHAR(8), IN p_nombres VARCHAR(50),
  IN p_apellidos VARCHAR(50), IN p_cargo VARCHAR(30), IN p_area VARCHAR(30))
BEGIN
  IF NOT EXISTS (SELECT 1 FROM empleado WHERE dni = p_dni) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Empleado no encontrado';
  END IF;
  IF TRIM(p_nombres) NOT REGEXP '^[[:alpha:]]+([ .''-]+[[:alpha:]]+)*[.]?$'
     OR TRIM(p_apellidos) NOT REGEXP '^[[:alpha:]]+([ .''-]+[[:alpha:]]+)*[.]?$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Los nombres y apellidos solo admiten letras, espacios, guion o apóstrofo';
  END IF;
  IF TRIM(p_cargo) = '' OR TRIM(p_area) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cargo y el área son obligatorios';
  END IF;
  UPDATE empleado
     SET nombres = TRIM(p_nombres), apellidos = TRIM(p_apellidos),
         cargo = TRIM(p_cargo), area = TRIM(p_area)
   WHERE dni = p_dni;
  CALL sp_empleado_obtener(p_dni);
END$$

-- Baja lógica: el disparador trg_empleado_validar_baja impide la baja
-- si hay solicitudes pendientes y registra la fecha.
CREATE PROCEDURE sp_empleado_baja(IN p_dni CHAR(8))
BEGIN
  IF NOT EXISTS (SELECT 1 FROM empleado WHERE dni = p_dni AND activo = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Empleado no encontrado o ya dado de baja';
  END IF;
  UPDATE empleado SET activo = 0 WHERE dni = p_dni;
  CALL sp_empleado_obtener(p_dni);
END$$

CREATE PROCEDURE sp_empleado_reactivar(IN p_dni CHAR(8))
BEGIN
  IF NOT EXISTS (SELECT 1 FROM empleado WHERE dni = p_dni AND activo = 0) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Empleado no encontrado o ya está activo';
  END IF;
  UPDATE empleado SET activo = 1 WHERE dni = p_dni;
  CALL sp_empleado_obtener(p_dni);
END$$

CREATE PROCEDURE sp_areas_listar()
BEGIN
  SELECT DISTINCT area FROM empleado ORDER BY area;
END$$

-- =====================================================================
-- SOLICITUDES DE PERMISO
-- =====================================================================

-- Bandeja de solicitudes con el empleado (JOIN) y el destino de la
-- aprobación: más de 20 minutos de anticipación -> Líder de área;
-- 20 minutos o menos -> RRHH (regla del proceso TO-BE).
CREATE PROCEDURE sp_solicitud_listar(IN p_buscar VARCHAR(60), IN p_estado VARCHAR(10),
  IN p_desde DATE, IN p_hasta DATE, IN p_incluir_anuladas TINYINT)
BEGIN
  SELECT s.id_permiso,
         DATE_FORMAT(s.fecha_solicitud, '%Y-%m-%d') AS fecha_solicitud,
         TIME_FORMAT(s.hora_registro, '%H:%i')      AS hora_registro,
         TIME_FORMAT(s.hora_de_inicio, '%H:%i')     AS hora_de_inicio,
         s.duracion, s.subtipo, s.dias, s.estado,
         TIME_FORMAT(s.tiempo_laborar, '%H:%i')     AS tiempo_laborar,
         s.dni, CONCAT(e.nombres, ' ', e.apellidos) AS empleado, e.area,
         IF(TIMESTAMPDIFF(MINUTE, s.hora_registro, s.hora_de_inicio) > 20,
            'Líder de área', 'RRHH')                AS destino,
         h.tipo_de_permiso, h.motivo, s.activo
    FROM solicitud_permiso s
    JOIN empleado e               ON e.dni = s.dni
    LEFT JOIN historial_permiso h ON h.id_permiso = s.id_permiso
   WHERE (p_incluir_anuladas = 1 OR s.activo = 1)
     AND (p_estado IS NULL OR p_estado = '' OR s.estado = p_estado)
     AND (p_desde IS NULL OR s.fecha_solicitud >= p_desde)
     AND (p_hasta IS NULL OR s.fecha_solicitud <= p_hasta)
     AND (p_buscar IS NULL OR p_buscar = ''
          OR s.dni LIKE CONCAT(p_buscar, '%')
          OR CAST(s.id_permiso AS CHAR) = p_buscar
          OR CONCAT(e.nombres, ' ', e.apellidos) LIKE CONCAT('%', p_buscar, '%')
          OR e.area LIKE CONCAT('%', p_buscar, '%'))
   ORDER BY s.fecha_solicitud DESC, s.id_permiso DESC;
END$$

CREATE PROCEDURE sp_solicitud_obtener(IN p_id INT UNSIGNED)
BEGIN
  SELECT s.id_permiso, DATE_FORMAT(s.fecha_solicitud, '%Y-%m-%d') AS fecha_solicitud,
         TIME_FORMAT(s.hora_registro, '%H:%i') AS hora_registro,
         TIME_FORMAT(s.hora_de_inicio, '%H:%i') AS hora_de_inicio,
         s.duracion, s.subtipo, s.dias, s.estado,
         TIME_FORMAT(s.tiempo_laborar, '%H:%i') AS tiempo_laborar,
         s.dni, CONCAT(e.nombres, ' ', e.apellidos) AS empleado, s.activo
    FROM solicitud_permiso s JOIN empleado e ON e.dni = s.dni
   WHERE s.id_permiso = p_id;
END$$

-- Registro de una solicitud. Los topes los valida trg_solicitud_topes.
CREATE PROCEDURE sp_solicitud_insertar(IN p_fecha DATE, IN p_hora_registro TIME,
  IN p_hora_inicio TIME, IN p_duracion SMALLINT, IN p_subtipo VARCHAR(10),
  IN p_dias TINYINT, IN p_tiempo_laborar TIME, IN p_dni CHAR(8))
BEGIN
  INSERT INTO solicitud_permiso (fecha_solicitud, hora_registro, hora_de_inicio, duracion,
                                 subtipo, dias, tiempo_laborar, dni)
  VALUES (p_fecha, p_hora_registro, p_hora_inicio, p_duracion, p_subtipo,
          COALESCE(p_dias, 1), p_tiempo_laborar, p_dni);
  CALL sp_solicitud_obtener(LAST_INSERT_ID());
END$$

-- Modificación: trg_solicitud_validar_cambio solo la permite en estado Pendiente.
CREATE PROCEDURE sp_solicitud_actualizar(IN p_id INT UNSIGNED, IN p_fecha DATE,
  IN p_hora_registro TIME, IN p_hora_inicio TIME, IN p_duracion SMALLINT,
  IN p_subtipo VARCHAR(10), IN p_dias TINYINT, IN p_tiempo_laborar TIME)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM solicitud_permiso WHERE id_permiso = p_id AND activo = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solicitud no encontrada o anulada';
  END IF;
  UPDATE solicitud_permiso
     SET fecha_solicitud = p_fecha, hora_registro = p_hora_registro, hora_de_inicio = p_hora_inicio,
         duracion = p_duracion, subtipo = p_subtipo, dias = COALESCE(p_dias, 1),
         tiempo_laborar = p_tiempo_laborar
   WHERE id_permiso = p_id;
  CALL sp_solicitud_obtener(p_id);
END$$

-- Aprobación o rechazo: cambia el estado y registra el historial en una
-- sola transacción (el historial es entidad débil de la solicitud).
CREATE PROCEDURE sp_solicitud_resolver(IN p_id INT UNSIGNED, IN p_estado VARCHAR(10),
  IN p_tipo VARCHAR(25), IN p_motivo VARCHAR(150))
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  IF p_estado NOT IN ('Aprobado', 'Rechazado') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El estado debe ser Aprobado o Rechazado';
  END IF;
  IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Debe indicar el motivo del permiso';
  END IF;
  START TRANSACTION;
  IF NOT EXISTS (SELECT 1 FROM solicitud_permiso
                  WHERE id_permiso = p_id AND estado = 'Pendiente' AND activo = 1 FOR UPDATE) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden resolver solicitudes pendientes y activas';
  END IF;
  UPDATE solicitud_permiso SET estado = p_estado WHERE id_permiso = p_id;
  INSERT INTO historial_permiso (id_permiso, tipo_de_permiso, motivo, fecha)
  VALUES (p_id, p_tipo, TRIM(p_motivo), CURDATE());
  COMMIT;
  CALL sp_solicitud_obtener(p_id);
END$$

-- Anulación lógica (borrado lógico de la solicitud).
CREATE PROCEDURE sp_solicitud_anular(IN p_id INT UNSIGNED)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM solicitud_permiso WHERE id_permiso = p_id AND activo = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solicitud no encontrada o ya anulada';
  END IF;
  IF EXISTS (SELECT 1 FROM compensacion WHERE id_permiso = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La solicitud ya tiene compensaciones registradas y no puede anularse';
  END IF;
  UPDATE solicitud_permiso SET activo = 0 WHERE id_permiso = p_id;
  CALL sp_solicitud_obtener(p_id);
END$$

-- =====================================================================
-- COMPENSACIÓN Y FIRMAS
-- =====================================================================
CREATE PROCEDURE sp_compensacion_listar(IN p_id_permiso INT UNSIGNED)
BEGIN
  SELECT c.id_compensacion, c.id_permiso,
         DATE_FORMAT(c.fecha_compensacion, '%Y-%m-%d') AS fecha_compensacion,
         TIME_FORMAT(c.hora_inicio, '%H:%i') AS hora_inicio,
         TIME_FORMAT(c.hora_fin, '%H:%i')    AS hora_fin,
         TIME_FORMAT(TIMEDIFF(c.hora_fin, c.hora_inicio), '%H:%i') AS hrs_min,
         SUM(f.firmante = 'Colaborador')   AS firma_colaborador,
         SUM(f.firmante = 'Administrador') AS firma_administrador
    FROM compensacion c
    LEFT JOIN firma_compensacion f ON f.id_compensacion = c.id_compensacion
   WHERE c.id_permiso = p_id_permiso
   GROUP BY c.id_compensacion, c.id_permiso, c.fecha_compensacion, c.hora_inicio, c.hora_fin
   ORDER BY c.fecha_compensacion, c.hora_inicio;
END$$

-- Las reglas (aprobada, máximo 7, no exceder el tiempo) las valida trg_compensacion_max7.
CREATE PROCEDURE sp_compensacion_insertar(IN p_fecha DATE, IN p_hora_inicio TIME,
  IN p_hora_fin TIME, IN p_id_permiso INT UNSIGNED)
BEGIN
  INSERT INTO compensacion (fecha_compensacion, hora_inicio, hora_fin, id_permiso)
  VALUES (p_fecha, p_hora_inicio, p_hora_fin, p_id_permiso);
  CALL sp_compensacion_listar(p_id_permiso);
END$$

-- Eliminación de un bloque de detalle (no firmado por el administrador;
-- lo controla trg_compensacion_no_borrar_firmada). Las firmas se borran en cascada.
CREATE PROCEDURE sp_compensacion_eliminar(IN p_id_compensacion INT UNSIGNED)
BEGIN
  DECLARE v_permiso INT UNSIGNED;
  SELECT id_permiso INTO v_permiso FROM compensacion WHERE id_compensacion = p_id_compensacion;
  IF v_permiso IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Compensación no encontrada';
  END IF;
  DELETE FROM compensacion WHERE id_compensacion = p_id_compensacion;
  CALL sp_compensacion_listar(v_permiso);
END$$

CREATE PROCEDURE sp_firma_registrar(IN p_id_compensacion INT UNSIGNED, IN p_firmante VARCHAR(15))
BEGIN
  IF p_firmante = 'Administrador' AND NOT EXISTS (
       SELECT 1 FROM firma_compensacion
        WHERE id_compensacion = p_id_compensacion AND firmante = 'Colaborador') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Primero debe firmar el colaborador';
  END IF;
  INSERT INTO firma_compensacion (id_compensacion, firmante) VALUES (p_id_compensacion, p_firmante);
  SELECT id_compensacion, firmante FROM firma_compensacion WHERE id_compensacion = p_id_compensacion;
END$$

CREATE PROCEDURE sp_firma_quitar(IN p_id_compensacion INT UNSIGNED, IN p_firmante VARCHAR(15))
BEGIN
  IF p_firmante = 'Colaborador' AND EXISTS (
       SELECT 1 FROM firma_compensacion
        WHERE id_compensacion = p_id_compensacion AND firmante = 'Administrador') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede quitar la firma del colaborador si ya firmó el administrador';
  END IF;
  -- Sin esta regla se podría quitar la firma y luego borrar un bloque ya firmado.
  IF p_firmante = 'Administrador' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La firma del administrador es definitiva y no se puede quitar';
  END IF;
  DELETE FROM firma_compensacion WHERE id_compensacion = p_id_compensacion AND firmante = p_firmante;
  SELECT id_compensacion, firmante FROM firma_compensacion WHERE id_compensacion = p_id_compensacion;
END$$

-- =====================================================================
-- BITÁCORA Y PANEL
-- =====================================================================
CREATE PROCEDURE sp_bitacora_listar(IN p_limite INT)
BEGIN
  SELECT id_bitacora, DATE_FORMAT(fecha_hora, '%Y-%m-%d %H:%i:%s') AS fecha_hora,
         tabla, operacion, id_registro, detalle, usuario_bd
    FROM bitacora ORDER BY id_bitacora DESC LIMIT p_limite;
END$$

CREATE PROCEDURE sp_panel_resumen()
BEGIN
  SELECT (SELECT COUNT(*) FROM empleado WHERE activo = 1)                       AS empleados_activos,
         (SELECT COUNT(*) FROM solicitud_permiso WHERE activo = 1)              AS solicitudes,
         (SELECT COUNT(*) FROM solicitud_permiso WHERE activo = 1 AND estado = 'Pendiente') AS pendientes,
         (SELECT COUNT(*) FROM solicitud_permiso WHERE activo = 1 AND estado = 'Aprobado')  AS aprobadas,
         (SELECT COUNT(*) FROM solicitud_permiso WHERE activo = 1 AND estado = 'Rechazado') AS rechazadas,
         (SELECT COUNT(*) FROM compensacion c
            LEFT JOIN firma_compensacion f
                   ON f.id_compensacion = c.id_compensacion AND f.firmante = 'Administrador'
           WHERE f.id_compensacion IS NULL)                                     AS compensaciones_sin_firma;
END$$

-- =====================================================================
-- REPORTES (10). Todos combinan tablas con JOIN o LEFT JOIN.
-- =====================================================================

-- R1. Permisos por empleado en un período (JOIN, GROUP BY, SUM condicional).
CREATE PROCEDURE sp_rep_01_permisos_por_empleado(IN p_desde DATE, IN p_hasta DATE)
BEGIN
  SELECT e.dni,
         CONCAT(e.nombres, ' ', e.apellidos)                             AS empleado,
         e.area,
         COUNT(*)                                                        AS total,
         SUM(s.subtipo = 'Urgente')                                      AS urgentes,
         SUM(s.subtipo = 'Personal')                                     AS personales,
         SUM(s.estado = 'Aprobado')                                      AS aprobadas,
         SUM(CASE WHEN s.estado = 'Aprobado' THEN s.duracion ELSE 0 END) AS min_aprobados
    FROM empleado e
    JOIN solicitud_permiso s ON s.dni = e.dni
   WHERE s.activo = 1 AND s.fecha_solicitud BETWEEN p_desde AND p_hasta
   GROUP BY e.dni, e.nombres, e.apellidos, e.area
   ORDER BY total DESC, empleado;
END$$

-- R2. Tope semanal de tolerancia (LEFT JOIN, COUNT, IF).
CREATE PROCEDURE sp_rep_02_tope_semanal(IN p_fecha DATE)
BEGIN
  DECLARE v_lunes DATE DEFAULT p_fecha - INTERVAL WEEKDAY(p_fecha) DAY;
  SELECT e.dni,
         CONCAT(e.nombres, ' ', e.apellidos)            AS empleado,
         DATE_FORMAT(v_lunes, '%d/%m')                  AS desde,
         DATE_FORMAT(v_lunes + INTERVAL 6 DAY, '%d/%m') AS hasta,
         COUNT(s.id_permiso)                            AS usadas,
         GREATEST(1 - COUNT(s.id_permiso), 0)           AS disponibles,
         IF(COUNT(s.id_permiso) >= 1, 'Tope alcanzado', 'Puede solicitar') AS validacion
    FROM empleado e
    LEFT JOIN solicitud_permiso s
           ON s.dni = e.dni AND s.subtipo = 'Urgente' AND s.estado <> 'Rechazado' AND s.activo = 1
          AND s.fecha_solicitud BETWEEN v_lunes AND v_lunes + INTERVAL 6 DAY
   WHERE e.activo = 1
   GROUP BY e.dni, e.nombres, e.apellidos
   ORDER BY usadas DESC, empleado;
END$$

-- R3. Tope mensual de permisos personales (LEFT JOIN, COUNT, LAST_DAY).
CREATE PROCEDURE sp_rep_03_tope_mensual(IN p_fecha DATE)
BEGIN
  SELECT e.dni,
         CONCAT(e.nombres, ' ', e.apellidos) AS empleado,
         DATE_FORMAT(p_fecha, '%m/%Y')       AS mes,
         COUNT(s.id_permiso)                 AS usados,
         GREATEST(2 - COUNT(s.id_permiso), 0) AS disponibles,
         IF(COUNT(s.id_permiso) >= 2, 'Tope alcanzado', 'Puede solicitar') AS validacion
    FROM empleado e
    LEFT JOIN solicitud_permiso s
           ON s.dni = e.dni AND s.subtipo = 'Personal' AND s.estado <> 'Rechazado' AND s.activo = 1
          AND s.fecha_solicitud BETWEEN DATE_FORMAT(p_fecha, '%Y-%m-01') AND LAST_DAY(p_fecha)
   WHERE e.activo = 1
   GROUP BY e.dni, e.nombres, e.apellidos
   ORDER BY usados DESC, empleado;
END$$

-- R4. Bandeja de pendientes por área (JOIN, GROUP_CONCAT, MIN).
CREATE PROCEDURE sp_rep_04_pendientes_por_area()
BEGIN
  SELECT e.area,
         COUNT(*)                                         AS pendientes,
         SUM(s.subtipo = 'Urgente')                       AS urgentes,
         DATE_FORMAT(MIN(s.fecha_solicitud), '%Y-%m-%d')  AS mas_antigua,
         GROUP_CONCAT(s.id_permiso ORDER BY s.id_permiso SEPARATOR ', ') AS solicitudes
    FROM solicitud_permiso s
    JOIN empleado e ON e.dni = s.dni
   WHERE s.estado = 'Pendiente' AND s.activo = 1
   GROUP BY e.area
   ORDER BY pendientes DESC, mas_antigua;
END$$

-- R5. Compensaciones de un período con sus firmas (JOIN de 3 tablas + LEFT JOIN).
CREATE PROCEDURE sp_rep_05_compensaciones_firmas(IN p_desde DATE, IN p_hasta DATE)
BEGIN
  SELECT c.id_compensacion                                   AS id_comp,
         c.id_permiso,
         CONCAT(e.nombres, ' ', e.apellidos)                 AS empleado,
         DATE_FORMAT(c.fecha_compensacion, '%d/%m/%Y')       AS fecha,
         CONCAT(TIME_FORMAT(c.hora_inicio, '%H:%i'), '-', TIME_FORMAT(c.hora_fin, '%H:%i')) AS horario,
         TIME_FORMAT(TIMEDIFF(c.hora_fin, c.hora_inicio), '%H:%i') AS hrs_min,
         GROUP_CONCAT(f.firmante ORDER BY f.firmante DESC SEPARATOR ', ') AS firmas,
         IF(COUNT(f.firmante) = 2, 'Completo', 'Falta firma') AS estado_formato
    FROM compensacion c
    JOIN solicitud_permiso s ON s.id_permiso = c.id_permiso
    JOIN empleado e          ON e.dni = s.dni
    LEFT JOIN firma_compensacion f ON f.id_compensacion = c.id_compensacion
   WHERE c.fecha_compensacion BETWEEN p_desde AND p_hasta
   GROUP BY c.id_compensacion, c.id_permiso, e.nombres, e.apellidos,
            c.fecha_compensacion, c.hora_inicio, c.hora_fin
   ORDER BY c.fecha_compensacion, c.id_compensacion;
END$$

-- R6. Saldo de horas por compensar (JOIN + LEFT JOIN, SUM de tiempos).
CREATE PROCEDURE sp_rep_06_saldo_por_compensar()
BEGIN
  SELECT s.id_permiso,
         CONCAT(e.nombres, ' ', e.apellidos)    AS empleado,
         TIME_FORMAT(s.tiempo_laborar, '%H:%i') AS a_compensar,
         TIME_FORMAT(SEC_TO_TIME(COALESCE(SUM(TIME_TO_SEC(TIMEDIFF(c.hora_fin, c.hora_inicio))), 0)), '%H:%i') AS compensado,
         TIME_FORMAT(SEC_TO_TIME(TIME_TO_SEC(s.tiempo_laborar)
               - COALESCE(SUM(TIME_TO_SEC(TIMEDIFF(c.hora_fin, c.hora_inicio))), 0)), '%H:%i') AS saldo,
         COUNT(c.id_compensacion)               AS bloques
    FROM solicitud_permiso s
    JOIN empleado e ON e.dni = s.dni
    LEFT JOIN compensacion c ON c.id_permiso = s.id_permiso
   WHERE s.estado = 'Aprobado' AND s.activo = 1 AND s.tiempo_laborar IS NOT NULL
   GROUP BY s.id_permiso, e.nombres, e.apellidos, s.tiempo_laborar
   HAVING saldo <> '00:00'
   ORDER BY s.id_permiso;
END$$

-- R7. Historial de permisos con el empleado (JOIN de 3 tablas).
CREATE PROCEDURE sp_rep_07_historial(IN p_desde DATE, IN p_hasta DATE)
BEGIN
  SELECT h.id_permiso,
         DATE_FORMAT(h.fecha, '%d/%m/%Y')    AS fecha,
         CONCAT(e.nombres, ' ', e.apellidos) AS empleado,
         e.area,
         h.tipo_de_permiso,
         s.estado,
         s.dias,
         h.motivo
    FROM historial_permiso h
    JOIN solicitud_permiso s ON s.id_permiso = h.id_permiso
    JOIN empleado e          ON e.dni = s.dni
   WHERE h.fecha BETWEEN p_desde AND p_hasta AND s.activo = 1
   ORDER BY h.fecha, h.id_permiso;
END$$

-- R8. Resumen mensual por área: volumen, tasa de aprobación y minutos (JOIN).
CREATE PROCEDURE sp_rep_08_resumen_mensual_area(IN p_anio SMALLINT)
BEGIN
  SELECT DATE_FORMAT(s.fecha_solicitud, '%Y-%m')               AS mes,
         e.area,
         COUNT(*)                                              AS solicitudes,
         SUM(s.estado = 'Aprobado')                            AS aprobadas,
         SUM(s.estado = 'Rechazado')                           AS rechazadas,
         SUM(s.estado = 'Pendiente')                           AS pendientes,
         ROUND(100 * SUM(s.estado = 'Aprobado')
               / NULLIF(SUM(s.estado <> 'Pendiente'), 0), 1)   AS pct_aprobacion,
         SUM(CASE WHEN s.estado = 'Aprobado' THEN s.duracion ELSE 0 END) AS min_aprobados
    FROM solicitud_permiso s
    JOIN empleado e ON e.dni = s.dni
   WHERE s.activo = 1 AND YEAR(s.fecha_solicitud) = p_anio
   GROUP BY mes, e.area
   ORDER BY mes, solicitudes DESC, e.area;
END$$

-- R9. Enrutamiento de la aprobación por área y subtipo: cuántas
--     solicitudes van al líder (> 20 min de anticipación) y cuántas a RRHH,
--     con la anticipación promedio (JOIN, CASE, AVG).
CREATE PROCEDURE sp_rep_09_enrutamiento(IN p_desde DATE, IN p_hasta DATE)
BEGIN
  SELECT e.area,
         s.subtipo,
         COUNT(*) AS solicitudes,
         SUM(TIMESTAMPDIFF(MINUTE, s.hora_registro, s.hora_de_inicio) > 20)  AS al_lider,
         SUM(TIMESTAMPDIFF(MINUTE, s.hora_registro, s.hora_de_inicio) <= 20) AS a_rrhh,
         ROUND(AVG(TIMESTAMPDIFF(MINUTE, s.hora_registro, s.hora_de_inicio)), 1) AS anticipacion_prom_min,
         IF(s.subtipo = 'Urgente', 10, 30) AS sla_lider_min
    FROM solicitud_permiso s
    JOIN empleado e ON e.dni = s.dni
   WHERE s.activo = 1 AND s.fecha_solicitud BETWEEN p_desde AND p_hasta
   GROUP BY e.area, s.subtipo
   ORDER BY e.area, s.subtipo;
END$$

-- R10. Ranking de empleados por minutos de permiso aprobados y su avance
--      de compensación (JOIN + LEFT JOIN a una subconsulta agregada).
CREATE PROCEDURE sp_rep_10_ranking_minutos(IN p_desde DATE, IN p_hasta DATE, IN p_top INT)
BEGIN
  SELECT CONCAT(e.nombres, ' ', e.apellidos) AS empleado,
         e.area,
         COUNT(*)                            AS permisos_aprobados,
         SUM(s.duracion)                     AS min_permiso,
         ROUND(SUM(TIME_TO_SEC(COALESCE(s.tiempo_laborar, '00:00'))) / 60) AS min_a_compensar,
         ROUND(COALESCE(SUM(comp.seg), 0) / 60)                           AS min_compensados,
         ROUND(100 * COALESCE(SUM(comp.seg), 0)
               / NULLIF(SUM(TIME_TO_SEC(COALESCE(s.tiempo_laborar, '00:00'))), 0), 1) AS pct_compensado
    FROM solicitud_permiso s
    JOIN empleado e ON e.dni = s.dni
    LEFT JOIN (SELECT id_permiso, SUM(TIME_TO_SEC(TIMEDIFF(hora_fin, hora_inicio))) AS seg
                 FROM compensacion GROUP BY id_permiso) comp
           ON comp.id_permiso = s.id_permiso
   WHERE s.estado = 'Aprobado' AND s.activo = 1
     AND s.fecha_solicitud BETWEEN p_desde AND p_hasta
   GROUP BY e.dni, e.nombres, e.apellidos, e.area
   ORDER BY min_permiso DESC, empleado
   LIMIT p_top;
END$$

DELIMITER ;
