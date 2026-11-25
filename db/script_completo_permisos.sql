-- =====================================================================
-- Sistema de permisos - Script COMPLETO de la base de datos (Entrega 5)
-- Incluye, en orden: 1) creación de la BD, tablas, índices y disparadores;
-- 2) procedimientos almacenados; 3) datos de prueba; 4) usuario del aplicativo.
-- Ejecutar con:  mysql -u root -p < script_completo_permisos.sql
-- =====================================================================

-- >>>>>>>>>>>>>>>>>>>> 01_esquema.sql >>>>>>>>>>>>>>>>>>>>
-- =====================================================================
-- Sistema de permisos - Registro de Inasistencias o Permisos (permisos por hora)
-- Script 1 (Entrega 5): base de datos, tablas, restricciones, índices
-- y disparadores.
-- Motor: MySQL 8.0 (InnoDB), juego de caracteres utf8mb4.
--
-- Cambios respecto de la Entrega 4:
--   * empleado y solicitud_permiso incorporan borrado lógico
--     (columnas activo y fecha_baja). El aplicativo nunca borra
--     físicamente estos registros: los da de baja.
--   * Nueva tabla bitacora para auditar las operaciones del aplicativo.
--   * Nuevos disparadores: bloqueo del borrado físico, validación de
--     transiciones de estado, reglas de compensación y auditoría.
-- =====================================================================

DROP DATABASE IF EXISTS permisos_hora;

CREATE DATABASE permisos_hora
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE permisos_hora;

-- ---------------------------------------------------------------------
-- Tabla EMPLEADO: colaboradores que solicitan permisos.
-- ---------------------------------------------------------------------
CREATE TABLE empleado (
  dni        CHAR(8)     NOT NULL,
  nombres    VARCHAR(50) NOT NULL,
  apellidos  VARCHAR(50) NOT NULL,
  cargo      VARCHAR(30) NOT NULL,
  area       VARCHAR(30) NOT NULL,
  activo     TINYINT(1)  NOT NULL DEFAULT 1,   -- Entrega 5: borrado lógico
  fecha_baja DATETIME    NULL,                 -- Entrega 5: momento de la baja
  CONSTRAINT pk_empleado PRIMARY KEY (dni),
  -- El DNI peruano tiene exactamente 8 dígitos numéricos.
  CONSTRAINT ck_empleado_dni CHECK (dni REGEXP '^[0-9]{8}$'),
  CONSTRAINT ck_empleado_activo CHECK (activo IN (0, 1))
) ENGINE = InnoDB;

-- Índice para agrupar y filtrar solicitudes por área (consulta de pendientes).
CREATE INDEX idx_empleado_area ON empleado (area);
-- Índice para la búsqueda por apellidos desde el aplicativo.
CREATE INDEX idx_empleado_apellidos ON empleado (apellidos, nombres);

-- ---------------------------------------------------------------------
-- Tabla SOLICITUD_PERMISO: cada solicitud de permiso por hora.
-- ---------------------------------------------------------------------
CREATE TABLE solicitud_permiso (
  id_permiso      INT UNSIGNED      NOT NULL AUTO_INCREMENT,
  fecha_solicitud DATE              NOT NULL,
  hora_registro   TIME              NOT NULL,
  hora_de_inicio  TIME              NOT NULL,
  duracion        SMALLINT UNSIGNED NOT NULL,
  subtipo         ENUM('Urgente','Personal') NOT NULL,
  dias            TINYINT UNSIGNED  NOT NULL DEFAULT 1,
  estado          ENUM('Pendiente','Aprobado','Rechazado') NOT NULL DEFAULT 'Pendiente',
  tiempo_laborar  TIME              NULL,
  dni             CHAR(8)           NOT NULL,
  activo          TINYINT(1)        NOT NULL DEFAULT 1,   -- Entrega 5: anulación lógica
  fecha_baja      DATETIME          NULL,
  CONSTRAINT pk_solicitud PRIMARY KEY (id_permiso),
  CONSTRAINT fk_solicitud_empleado FOREIGN KEY (dni)
    REFERENCES empleado (dni)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  -- Un permiso por hora no puede superar los 60 minutos.
  CONSTRAINT ck_solicitud_duracion CHECK (duracion BETWEEN 1 AND 60),
  CONSTRAINT ck_solicitud_dias CHECK (dias >= 1),
  CONSTRAINT ck_solicitud_activo CHECK (activo IN (0, 1)),
  -- Un empleado no puede registrar dos solicitudes con el mismo inicio.
  CONSTRAINT uq_solicitud_empleado_inicio UNIQUE (dni, fecha_solicitud, hora_de_inicio)
) ENGINE = InnoDB AUTO_INCREMENT = 1001;

-- Índice compuesto para validar los topes semanales y mensuales:
-- igualdad por dni y subtipo + rango por fecha_solicitud.
CREATE INDEX idx_solicitud_tope ON solicitud_permiso (dni, subtipo, fecha_solicitud);
-- Índice para la bandeja de solicitudes pendientes ordenadas por fecha.
CREATE INDEX idx_solicitud_estado_fecha ON solicitud_permiso (estado, fecha_solicitud);

-- ---------------------------------------------------------------------
-- Tabla COMPENSACION: cada fila del detalle de compensación de horas.
-- ---------------------------------------------------------------------
CREATE TABLE compensacion (
  id_compensacion    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  fecha_compensacion DATE         NOT NULL,
  hora_inicio        TIME         NOT NULL,
  hora_fin           TIME         NOT NULL,
  id_permiso         INT UNSIGNED NOT NULL,
  CONSTRAINT pk_compensacion PRIMARY KEY (id_compensacion),
  CONSTRAINT fk_compensacion_solicitud FOREIGN KEY (id_permiso)
    REFERENCES solicitud_permiso (id_permiso)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_compensacion_horario CHECK (hora_fin > hora_inicio),
  -- Evita registrar dos veces el mismo bloque de compensación.
  CONSTRAINT uq_compensacion_bloque UNIQUE (id_permiso, fecha_compensacion, hora_inicio)
) ENGINE = InnoDB AUTO_INCREMENT = 5001;

-- Índice para filtrar compensaciones por rango de fechas.
CREATE INDEX idx_compensacion_fecha ON compensacion (fecha_compensacion);

-- ---------------------------------------------------------------------
-- Tabla HISTORIAL_PERMISO: entidad débil de SOLICITUD_PERMISO (1:1).
-- ---------------------------------------------------------------------
CREATE TABLE historial_permiso (
  id_permiso      INT UNSIGNED NOT NULL,
  tipo_de_permiso ENUM('Tardanza','Tardanza justificada','Salida anticipada','Personal') NOT NULL,
  motivo          VARCHAR(150) NOT NULL,
  fecha           DATE         NOT NULL,
  CONSTRAINT pk_historial PRIMARY KEY (id_permiso),
  -- Dependencia de existencia: si se elimina la solicitud, se elimina su historial.
  CONSTRAINT fk_historial_solicitud FOREIGN KEY (id_permiso)
    REFERENCES solicitud_permiso (id_permiso)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

-- Índice para reportes del historial por fecha.
CREATE INDEX idx_historial_fecha ON historial_permiso (fecha);

-- ---------------------------------------------------------------------
-- Tabla FIRMA_COMPENSACION: atributo multivaluado {firmas}.
-- ---------------------------------------------------------------------
CREATE TABLE firma_compensacion (
  id_compensacion INT UNSIGNED NOT NULL,
  firmante        ENUM('Colaborador','Administrador') NOT NULL,
  CONSTRAINT pk_firma PRIMARY KEY (id_compensacion, firmante),
  CONSTRAINT fk_firma_compensacion FOREIGN KEY (id_compensacion)
    REFERENCES compensacion (id_compensacion)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- Tabla BITACORA (Entrega 5): auditoría de las operaciones.
-- La llenan únicamente los disparadores.
-- ---------------------------------------------------------------------
CREATE TABLE bitacora (
  id_bitacora INT UNSIGNED NOT NULL AUTO_INCREMENT,
  fecha_hora  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  tabla       VARCHAR(30)  NOT NULL,
  operacion   ENUM('INSERT','UPDATE','BAJA','REACTIVACION','DELETE') NOT NULL,
  id_registro VARCHAR(20)  NOT NULL,
  detalle     VARCHAR(255) NULL,
  usuario_bd  VARCHAR(80)  NOT NULL,
  CONSTRAINT pk_bitacora PRIMARY KEY (id_bitacora)
) ENGINE = InnoDB;

CREATE INDEX idx_bitacora_fecha ON bitacora (fecha_hora);
CREATE INDEX idx_bitacora_tabla ON bitacora (tabla, id_registro);

-- ---------------------------------------------------------------------
-- Disparadores
-- ---------------------------------------------------------------------
DELIMITER $$

-- (1) Topes de uso: 1 solicitud de tolerancia (Urgente) por semana
--     y 2 permisos personales por mes; no cuentan las rechazadas
--     ni las anuladas (activo = 0).
CREATE TRIGGER trg_solicitud_topes
BEFORE INSERT ON solicitud_permiso
FOR EACH ROW
BEGIN
  DECLARE v_usadas INT;
  DECLARE v_activo TINYINT;

  -- El bloqueo de la fila del empleado evita que dos registros simultáneos pasen el mismo tope.
  SELECT activo INTO v_activo FROM empleado WHERE dni = NEW.dni FOR UPDATE;
  IF v_activo = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El empleado está dado de baja y no puede registrar solicitudes';
  END IF;

  IF NEW.hora_registro > NEW.hora_de_inicio THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'La solicitud debe registrarse antes de la hora de inicio del permiso';
  END IF;
  IF TIME_TO_SEC(NEW.hora_de_inicio) + NEW.duracion * 60 > 86400 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El permiso debe terminar el mismo día';
  END IF;
  IF TIME_TO_SEC(NEW.tiempo_laborar) <= 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El tiempo a compensar debe ser mayor que cero';
  END IF;
  IF NEW.estado <> 'Rechazado' AND EXISTS (
       SELECT 1 FROM solicitud_permiso
        WHERE dni = NEW.dni AND fecha_solicitud = NEW.fecha_solicitud
          AND activo = 1 AND estado <> 'Rechazado'
          AND TIME_TO_SEC(hora_de_inicio) < TIME_TO_SEC(NEW.hora_de_inicio) + NEW.duracion * 60
          AND TIME_TO_SEC(NEW.hora_de_inicio) < TIME_TO_SEC(hora_de_inicio) + duracion * 60) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El empleado ya tiene otro permiso que se cruza con ese horario';
  END IF;

  IF NEW.subtipo = 'Urgente' THEN
    SELECT COUNT(*) INTO v_usadas
      FROM solicitud_permiso
     WHERE dni = NEW.dni
       AND subtipo = 'Urgente'
       AND estado <> 'Rechazado'
       AND activo = 1
       -- Semana de lunes a domingo que contiene la fecha solicitada.
       AND fecha_solicitud BETWEEN NEW.fecha_solicitud - INTERVAL WEEKDAY(NEW.fecha_solicitud) DAY
                               AND NEW.fecha_solicitud - INTERVAL WEEKDAY(NEW.fecha_solicitud) DAY + INTERVAL 6 DAY;
    IF v_usadas >= 1 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tope excedido: solo 1 solicitud de tolerancia (Urgente) por semana';
    END IF;
  ELSE
    SELECT COUNT(*) INTO v_usadas
      FROM solicitud_permiso
     WHERE dni = NEW.dni
       AND subtipo = 'Personal'
       AND estado <> 'Rechazado'
       AND activo = 1
       AND fecha_solicitud BETWEEN DATE_FORMAT(NEW.fecha_solicitud, '%Y-%m-01')
                               AND LAST_DAY(NEW.fecha_solicitud);
    IF v_usadas >= 2 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tope excedido: solo 2 permisos personales por mes';
    END IF;
  END IF;
END$$

-- (2) Solo se modifican solicitudes pendientes; un estado resuelto
--     no cambia y una solicitud anulada no se modifica ni se reactiva.
--     Al editar se vuelven a validar el horario y los topes de (1).
CREATE TRIGGER trg_solicitud_validar_cambio
BEFORE UPDATE ON solicitud_permiso
FOR EACH ROW
BEGIN
  DECLARE v_usadas INT;
  DECLARE v_activo TINYINT;
  DECLARE v_cambia TINYINT DEFAULT NOT (
        NEW.fecha_solicitud <=> OLD.fecha_solicitud AND NEW.hora_registro <=> OLD.hora_registro
    AND NEW.hora_de_inicio <=> OLD.hora_de_inicio AND NEW.duracion <=> OLD.duracion
    AND NEW.subtipo <=> OLD.subtipo AND NEW.dias <=> OLD.dias
    AND NEW.tiempo_laborar <=> OLD.tiempo_laborar AND NEW.dni <=> OLD.dni);

  IF OLD.activo = 0 AND NEW.activo = 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Una solicitud anulada no puede reactivarse; registre una nueva';
  END IF;
  IF OLD.estado <> 'Pendiente' AND NEW.estado = 'Pendiente' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Una solicitud resuelta no puede volver a Pendiente';
  END IF;
  IF OLD.estado <> 'Pendiente' AND NEW.estado <> OLD.estado THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Una solicitud resuelta no puede cambiar de decisión';
  END IF;
  IF OLD.activo = 0 AND (v_cambia OR NEW.estado <> OLD.estado) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Una solicitud anulada no se puede modificar';
  END IF;
  IF OLD.estado <> 'Pendiente' AND v_cambia THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Solo se pueden modificar los datos de solicitudes pendientes';
  END IF;
  IF v_cambia THEN
    SELECT activo INTO v_activo FROM empleado WHERE dni = NEW.dni FOR UPDATE;
    IF NEW.hora_registro > NEW.hora_de_inicio THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La solicitud debe registrarse antes de la hora de inicio del permiso';
    END IF;
    IF TIME_TO_SEC(NEW.hora_de_inicio) + NEW.duracion * 60 > 86400 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El permiso debe terminar el mismo día';
    END IF;
    IF TIME_TO_SEC(NEW.tiempo_laborar) <= 0 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El tiempo a compensar debe ser mayor que cero';
    END IF;
    IF NEW.estado <> 'Rechazado' AND EXISTS (
         SELECT 1 FROM solicitud_permiso
          WHERE dni = NEW.dni AND fecha_solicitud = NEW.fecha_solicitud
            AND id_permiso <> NEW.id_permiso
            AND activo = 1 AND estado <> 'Rechazado'
            AND TIME_TO_SEC(hora_de_inicio) < TIME_TO_SEC(NEW.hora_de_inicio) + NEW.duracion * 60
            AND TIME_TO_SEC(NEW.hora_de_inicio) < TIME_TO_SEC(hora_de_inicio) + duracion * 60) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El empleado ya tiene otro permiso que se cruza con ese horario';
    END IF;
    IF NEW.subtipo = 'Urgente' THEN
      SELECT COUNT(*) INTO v_usadas
        FROM solicitud_permiso
       WHERE dni = NEW.dni
         AND id_permiso <> NEW.id_permiso
         AND subtipo = 'Urgente'
         AND estado <> 'Rechazado'
         AND activo = 1
         -- Semana de lunes a domingo que contiene la fecha solicitada.
         AND fecha_solicitud BETWEEN NEW.fecha_solicitud - INTERVAL WEEKDAY(NEW.fecha_solicitud) DAY
                                 AND NEW.fecha_solicitud - INTERVAL WEEKDAY(NEW.fecha_solicitud) DAY + INTERVAL 6 DAY;
      IF v_usadas >= 1 THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = 'Tope excedido: solo 1 solicitud de tolerancia (Urgente) por semana';
      END IF;
    ELSE
      SELECT COUNT(*) INTO v_usadas
        FROM solicitud_permiso
       WHERE dni = NEW.dni
         AND id_permiso <> NEW.id_permiso
         AND subtipo = 'Personal'
         AND estado <> 'Rechazado'
         AND activo = 1
         AND fecha_solicitud BETWEEN DATE_FORMAT(NEW.fecha_solicitud, '%Y-%m-01')
                                 AND LAST_DAY(NEW.fecha_solicitud);
      IF v_usadas >= 2 THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = 'Tope excedido: solo 2 permisos personales por mes';
      END IF;
    END IF;
  END IF;
  IF NEW.activo = 0 AND OLD.activo = 1 THEN
    IF EXISTS (SELECT 1 FROM compensacion WHERE id_permiso = OLD.id_permiso) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La solicitud ya tiene compensaciones registradas y no puede anularse';
    END IF;
    SET NEW.fecha_baja = NOW();
  END IF;
END$$

-- (3) El borrado físico de solicitudes y empleados está prohibido:
--     el aplicativo usa baja lógica.
CREATE TRIGGER trg_solicitud_no_borrar
BEFORE DELETE ON solicitud_permiso
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'No se permite eliminar solicitudes: use la anulación lógica';
END$$

CREATE TRIGGER trg_empleado_no_borrar
BEFORE DELETE ON empleado
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'No se permite eliminar empleados: use la baja lógica';
END$$

-- (4) Un empleado con solicitudes pendientes no puede darse de baja.
CREATE TRIGGER trg_empleado_validar_baja
BEFORE UPDATE ON empleado
FOR EACH ROW
BEGIN
  IF OLD.activo = 1 AND NEW.activo = 0 THEN
    IF EXISTS (SELECT 1 FROM solicitud_permiso
                WHERE dni = OLD.dni AND estado = 'Pendiente' AND activo = 1) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El empleado tiene solicitudes pendientes; resuélvalas antes de darlo de baja';
    END IF;
    SET NEW.fecha_baja = NOW();
  ELSEIF OLD.activo = 0 AND NEW.activo = 1 THEN
    SET NEW.fecha_baja = NULL;
  END IF;
END$$

-- (5) Reglas de la compensación: solo para solicitudes aprobadas y
--     activas, máximo 7 filas por permiso (regla del formato físico),
--     sin superar el tiempo a laborar, desde la fecha del permiso (se
--     compensa un permiso ya utilizado) y sin cruzarse entre sí.
CREATE TRIGGER trg_compensacion_max7
BEFORE INSERT ON compensacion
FOR EACH ROW
BEGIN
  DECLARE v_estado VARCHAR(10);
  DECLARE v_activo TINYINT;
  DECLARE v_tiempo TIME;
  DECLARE v_compensado INT;
  DECLARE v_fecha DATE;

  -- El bloqueo de la solicitud evita que dos bloques simultáneos superen el total.
  SELECT estado, activo, tiempo_laborar, fecha_solicitud INTO v_estado, v_activo, v_tiempo, v_fecha
    FROM solicitud_permiso WHERE id_permiso = NEW.id_permiso FOR UPDATE;

  IF v_estado <> 'Aprobado' OR v_activo = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Solo se registran compensaciones de solicitudes aprobadas y activas';
  END IF;
  IF v_tiempo IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'La solicitud no tiene tiempo a laborar: no requiere compensación';
  END IF;
  IF NEW.fecha_compensacion < v_fecha THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'La compensación no puede ser anterior a la fecha del permiso';
  END IF;
  IF EXISTS (SELECT 1 FROM compensacion
              WHERE id_permiso = NEW.id_permiso AND fecha_compensacion = NEW.fecha_compensacion
                AND hora_inicio < NEW.hora_fin AND NEW.hora_inicio < hora_fin) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El bloque se cruza con otro bloque de la misma solicitud';
  END IF;
  IF (SELECT COUNT(*) FROM compensacion WHERE id_permiso = NEW.id_permiso) >= 7 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El formato admite como máximo 7 compensaciones por permiso';
  END IF;
  SELECT COALESCE(SUM(TIME_TO_SEC(TIMEDIFF(hora_fin, hora_inicio))), 0) INTO v_compensado
    FROM compensacion WHERE id_permiso = NEW.id_permiso;
  IF v_compensado + TIME_TO_SEC(TIMEDIFF(NEW.hora_fin, NEW.hora_inicio)) > TIME_TO_SEC(v_tiempo) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El bloque supera el tiempo pendiente por compensar';
  END IF;
END$$

-- (6) Una compensación con la firma del administrador ya no se elimina.
CREATE TRIGGER trg_compensacion_no_borrar_firmada
BEFORE DELETE ON compensacion
FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM firma_compensacion
              WHERE id_compensacion = OLD.id_compensacion AND firmante = 'Administrador') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'La compensación ya fue firmada por el administrador y no puede eliminarse';
  END IF;
END$$

-- (7) Auditoría en la bitácora.
CREATE TRIGGER trg_empleado_auditoria_ins
AFTER INSERT ON empleado
FOR EACH ROW
  INSERT INTO bitacora (tabla, operacion, id_registro, detalle, usuario_bd)
  VALUES ('empleado', 'INSERT', NEW.dni,
          CONCAT('Alta de ', NEW.nombres, ' ', NEW.apellidos, ' (', NEW.area, ')'), USER())$$

CREATE TRIGGER trg_empleado_auditoria_upd
AFTER UPDATE ON empleado
FOR EACH ROW
  INSERT INTO bitacora (tabla, operacion, id_registro, detalle, usuario_bd)
  VALUES ('empleado',
          CASE WHEN OLD.activo = 1 AND NEW.activo = 0 THEN 'BAJA'
               WHEN OLD.activo = 0 AND NEW.activo = 1 THEN 'REACTIVACION'
               ELSE 'UPDATE' END,
          NEW.dni,
          CONCAT(NEW.nombres, ' ', NEW.apellidos, ' - ', NEW.cargo, ' / ', NEW.area), USER())$$

CREATE TRIGGER trg_solicitud_auditoria_ins
AFTER INSERT ON solicitud_permiso
FOR EACH ROW
  INSERT INTO bitacora (tabla, operacion, id_registro, detalle, usuario_bd)
  VALUES ('solicitud_permiso', 'INSERT', NEW.id_permiso,
          CONCAT(NEW.subtipo, ' de ', NEW.duracion, ' min el ', DATE_FORMAT(NEW.fecha_solicitud, '%d/%m/%Y'),
                 ' - DNI ', NEW.dni), USER())$$

CREATE TRIGGER trg_solicitud_auditoria_upd
AFTER UPDATE ON solicitud_permiso
FOR EACH ROW
  INSERT INTO bitacora (tabla, operacion, id_registro, detalle, usuario_bd)
  VALUES ('solicitud_permiso',
          IF(OLD.activo = 1 AND NEW.activo = 0, 'BAJA', 'UPDATE'),
          NEW.id_permiso,
          IF(OLD.estado <> NEW.estado,
             CONCAT('Estado: ', OLD.estado, ' -> ', NEW.estado),
             IF(OLD.activo = 1 AND NEW.activo = 0, 'Solicitud anulada', 'Datos de la solicitud modificados')),
          USER())$$

CREATE TRIGGER trg_compensacion_auditoria_ins
AFTER INSERT ON compensacion
FOR EACH ROW
  INSERT INTO bitacora (tabla, operacion, id_registro, detalle, usuario_bd)
  VALUES ('compensacion', 'INSERT', NEW.id_compensacion,
          CONCAT('Permiso ', NEW.id_permiso, ': ', DATE_FORMAT(NEW.fecha_compensacion, '%d/%m/%Y'), ' ',
                 TIME_FORMAT(NEW.hora_inicio, '%H:%i'), '-', TIME_FORMAT(NEW.hora_fin, '%H:%i')), USER())$$

CREATE TRIGGER trg_compensacion_auditoria_del
AFTER DELETE ON compensacion
FOR EACH ROW
  INSERT INTO bitacora (tabla, operacion, id_registro, detalle, usuario_bd)
  VALUES ('compensacion', 'DELETE', OLD.id_compensacion,
          CONCAT('Bloque eliminado del permiso ', OLD.id_permiso), USER())$$

DELIMITER ;

-- >>>>>>>>>>>>>>>>>>>> 02_procedimientos.sql >>>>>>>>>>>>>>>>>>>>
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

-- >>>>>>>>>>>>>>>>>>>> 03_datos.sql >>>>>>>>>>>>>>>>>>>>
-- =====================================================================
-- Script 3 (Entrega 5): datos de prueba ampliados.
-- Parte A: datos de la Entrega 4 (sin cambios).
-- Parte B: 30 empleados, 247 solicitudes, 239 registros de historial,
--          230 bloques de compensación y 457 firmas generados con
--          generar_datos.py (semilla fija), respetando los topes y la
--          regla de compensación (los disparadores validan cada fila).
-- Parte C: bajas lógicas de ejemplo.
-- =====================================================================
USE permisos_hora;

-- Parte A ------------------------------------------------------------
-- Datos de prueba de la Entrega 4 (Tablas 9 a 18 del informe).
-- 10 empleados (los tres primeros son los de la Tabla 9).
INSERT INTO empleado (dni, nombres, apellidos, cargo, area) VALUES
('72123249', 'Milagros', 'Cáceres',            'Docente',                  'Enfermería Técnica'),
('60782954', 'Deyanira', 'Casaperalta',        'Líder de Administración',  'Administración'),
('72221744', 'Jose',     'Molina',             'Asistente administrativo', 'Administración'),
('74839201', 'Julián',   'Rivas Rodríguez',    'Docente',                  'Contabilidad'),
('45612378', 'Rosa',     'Quispe Mamani',      'Docente',                  'Producción Agropecuaria'),
('70451236', 'Carlos',   'Huamán Torres',      'Coordinador académico',    'Administración de Empresas'),
('41258963', 'Lucía',    'Flores Ccama',       'Secretaria académica',     'Secretaría Académica'),
('73698521', 'Miguel',   'Apaza Condori',      'Técnico de soporte',       'Sistemas'),
('46987123', 'Karina',   'Zúñiga Paredes',     'Docente',                  'Administración Bancaria'),
('71324598', 'Renzo',    'Valdivia Ríos',      'Asistente de RR.HH.',      'Recursos Humanos');
-- 17 solicitudes (1001 a 1003 son las de la Tabla 16).
-- 13 resueltas (11 aprobadas, 2 rechazadas) y 4 pendientes.
INSERT INTO solicitud_permiso
  (id_permiso, fecha_solicitud, hora_registro, hora_de_inicio, duracion, subtipo, dias, estado,
tiempo_laborar, dni) VALUES
(1001, '2026-08-17', '07:40', '08:00', 45, 'Urgente',  1, 'Aprobado',  '00:45', '72123249'),
(1002, '2026-08-10', '07:10', '08:00', 60, 'Personal', 2, 'Aprobado',  NULL,    '60782954'),
(1003, '2026-08-07', '07:55', '08:00', 30, 'Urgente',  1, 'Aprobado',  '01:00', '72221744'),
(1004, '2026-08-05', '07:30', '08:00', 60, 'Personal', 1, 'Aprobado',  '01:00', '74839201'),
(1005, '2026-08-12', '07:50', '08:00', 20, 'Urgente',  1, 'Aprobado',  '00:20', '45612378'),
(1006, '2026-08-14', '10:00', '12:00', 60, 'Personal', 1, 'Rechazado', NULL,    '70451236'),
(1007, '2026-08-19', '07:45', '08:00', 40, 'Urgente',  1, 'Aprobado',  '00:40', '41258963'),
(1008, '2026-08-20', '08:00', '11:00', 60, 'Personal', 1, 'Aprobado',  '01:00', '73698521'),
(1009, '2026-08-24', '07:52', '08:00', 15, 'Urgente',  1, 'Aprobado',  NULL,    '72123249'),
(1010, '2026-08-25', '09:00', '15:00', 60, 'Personal', 1, 'Aprobado',  '01:00', '72123249'),
(1011, '2026-08-26', '07:20', '08:00', 30, 'Urgente',  1, 'Rechazado', NULL,    '46987123'),
(1012, '2026-08-27', '13:00', '16:00', 45, 'Personal', 1, 'Aprobado',  '00:45', '71324598'),
(1013, '2026-09-01', '07:48', '08:00', 25, 'Urgente',  1, 'Pendiente', NULL,    '74839201'),
(1014, '2026-09-01', '08:10', '10:30', 60, 'Personal', 1, 'Pendiente', NULL,    '45612378'),
(1015, '2026-09-02', '07:15', '08:00', 50, 'Urgente',  1, 'Pendiente', NULL,    '73698521'),
(1016, '2026-09-02', '08:30', '14:00', 30, 'Personal', 1, 'Pendiente', NULL,    '72221744'),
(1017, '2026-08-28', '08:00', '10:00', 30, 'Personal', 1, 'Aprobado',  NULL,    '72123249');
-- 11 bloques de compensación (5001 a 5003 son los de la Tabla 17).
INSERT INTO compensacion (id_compensacion, fecha_compensacion, hora_inicio, hora_fin, id_permiso)
VALUES
(5001, '2026-08-12', '17:00', '17:30', 1003),
(5002, '2026-08-13', '17:00', '17:30', 1003),
(5003, '2026-08-18', '17:00', '17:45', 1001),
(5004, '2026-08-06', '17:00', '18:00', 1004),
(5005, '2026-08-13', '17:00', '17:20', 1005),
(5006, '2026-08-20', '17:00', '17:40', 1007),
(5007, '2026-08-21', '17:00', '17:30', 1008),
(5008, '2026-08-22', '09:00', '09:30', 1008),
(5009, '2026-08-26', '17:00', '17:30', 1010),
(5010, '2026-08-27', '17:00', '17:30', 1010),
(5011, '2026-08-28', '17:00', '17:45', 1012);
-- 13 registros de historial: uno por cada solicitud resuelta
-- (1001 a 1003 son los de la Tabla 18).
INSERT INTO historial_permiso (id_permiso, tipo_de_permiso, motivo, fecha) VALUES
(1001, 'Tardanza justificada', 'Malestar estomacal',         '2026-08-17'),
(1002, 'Tardanza',             'Falta de transporte',        '2026-08-11'),
(1003, 'Tardanza',             'Tráfico',                    '2026-08-07'),
(1004, 'Personal',             'Trámite en RENIEC',          '2026-08-05'),
(1005, 'Tardanza justificada', 'Corte de agua en domicilio', '2026-08-12'),
(1006, 'Salida anticipada',    'Reunión en colegio del hijo','2026-08-14'),
(1007, 'Tardanza justificada', 'Cita médica',                '2026-08-19'),
(1008, 'Personal',             'Trámite bancario',           '2026-08-20'),
(1009, 'Tardanza',             'Paro de transportistas',     '2026-08-24'),
(1010, 'Salida anticipada',    'Cita odontológica',          '2026-08-25'),
(1011, 'Tardanza',             'Tráfico',                    '2026-08-26'),
(1012, 'Salida anticipada',    'Trámite notarial',           '2026-08-27'),
(1017, 'Personal',             'Gestión municipal',          '2026-08-28');
-- 21 firmas: las compensaciones 5001 a 5010 tienen ambas firmas;
-- la 5011 aún espera la firma del administrador.
INSERT INTO firma_compensacion (id_compensacion, firmante) VALUES
(5001, 'Colaborador'), (5001, 'Administrador'),
(5002, 'Colaborador'), (5002, 'Administrador'),
(5003, 'Colaborador'), (5003, 'Administrador'),
(5004, 'Colaborador'), (5004, 'Administrador'),
(5005, 'Colaborador'), (5005, 'Administrador'),
(5006, 'Colaborador'), (5006, 'Administrador'),
(5007, 'Colaborador'), (5007, 'Administrador'),
(5008, 'Colaborador'), (5008, 'Administrador'),
(5009, 'Colaborador'), (5009, 'Administrador'),
(5010, 'Colaborador'), (5010, 'Administrador'),
(5011, 'Colaborador');

-- Parte B ------------------------------------------------------------
INSERT INTO empleado (dni, nombres, apellidos, cargo, area) VALUES
('47994000', 'Ana', 'Mamani Quispe', 'Docente', 'Enfermería Técnica'),
('73723261', 'Luis', 'Condori Huanca', 'Técnico de campo', 'Producción Agropecuaria'),
('46887842', 'María', 'Ramos Tapia', 'Docente', 'Contabilidad'),
('77350043', 'Jorge', 'Ccahuana Puma', 'Docente', 'Administración de Empresas'),
('78424442', 'Patricia', 'Salas Medina', 'Coordinador de carrera', 'Administración Bancaria'),
('79360747', 'Ricardo', 'Choque Lima', 'Cajera', 'Administración'),
('56101703', 'Elena', 'Pari Cutipa', 'Asistente académico', 'Secretaría Académica'),
('45417273', 'Fernando', 'Vargas Núñez', 'Técnico de soporte', 'Sistemas'),
('59276364', 'Sofía', 'Delgado Zevallos', 'Analista de RR.HH.', 'Recursos Humanos'),
('70175825', 'Diego', 'Huanca Arapa', 'Psicóloga', 'Bienestar Estudiantil'),
('72902585', 'Gabriela', 'Chávez Benavides', 'Bibliotecario', 'Biblioteca'),
('54107938', 'Óscar', 'Llerena Paz', 'Vigilante', 'Mantenimiento'),
('56878758', 'Valeria', 'Bustamante Rey', 'Docente', 'Enfermería Técnica'),
('63933440', 'Héctor', 'Ticona Mendoza', 'Docente', 'Producción Agropecuaria'),
('74466276', 'Carmen', 'Coaguila Rojas', 'Docente', 'Contabilidad'),
('62843493', 'Raúl', 'Pinto Linares', 'Docente', 'Administración de Empresas'),
('77409872', 'Daniela', 'Gutiérrez Vera', 'Coordinador de carrera', 'Administración Bancaria'),
('59300639', 'Edwin', 'Ochoa Salinas', 'Cajera', 'Administración'),
('49454857', 'Paola', 'Cornejo Málaga', 'Asistente académico', 'Secretaría Académica'),
('41660226', 'Víctor', 'Arce Valdivia', 'Desarrollador', 'Sistemas'),
('64396906', 'Silvia', 'Yucra Ccori', 'Analista de RR.HH.', 'Recursos Humanos'),
('68334536', 'Alberto', 'Torres Lazo', 'Psicóloga', 'Bienestar Estudiantil'),
('66761224', 'Natalia', 'Begazo Díaz', 'Bibliotecario', 'Biblioteca'),
('47814689', 'Wilber', 'Quispe Apaza', 'Vigilante', 'Mantenimiento'),
('73981160', 'Roxana', 'Mendoza Rivera', 'Coordinador de carrera', 'Enfermería Técnica'),
('72952513', 'Iván', 'Flores Zegarra', 'Docente', 'Producción Agropecuaria'),
('75208847', 'Yesenia', 'Paredes Chirinos', 'Asistente contable', 'Contabilidad'),
('68183451', 'Marco', 'Rojas Cuba', 'Docente', 'Administración de Empresas'),
('74423452', 'Fiorella', 'Herrera Talavera', 'Docente', 'Administración Bancaria'),
('78622241', 'Néstor', 'Molina Bedoya', 'Asistente administrativo', 'Administración');

INSERT INTO solicitud_permiso (id_permiso, fecha_solicitud, hora_registro, hora_de_inicio, duracion, subtipo, dias, estado, tiempo_laborar, dni) VALUES
(1018, '2026-07-01', '07:30', '09:00', 60, 'Personal', 1, 'Aprobado', NULL, '74839201'),
(1019, '2026-07-01', '07:05', '07:30', 30, 'Urgente', 1, 'Aprobado', '00:30', '47814689'),
(1020, '2026-07-02', '14:45', '15:00', 60, 'Personal', 2, 'Aprobado', '01:00', '71324598'),
(1021, '2026-07-03', '07:20', '07:30', 25, 'Urgente', 1, 'Rechazado', NULL, '72902585'),
(1022, '2026-07-03', '13:52', '14:00', 20, 'Urgente', 1, 'Aprobado', NULL, '41660226'),
(1023, '2026-07-03', '07:48', '08:00', 30, 'Urgente', 1, 'Aprobado', '00:30', '41258963'),
(1024, '2026-07-06', '07:20', '08:00', 30, 'Urgente', 1, 'Aprobado', '00:30', '73981160'),
(1025, '2026-07-06', '07:48', '08:00', 30, 'Urgente', 1, 'Aprobado', NULL, '78424442'),
(1026, '2026-07-07', '07:10', '07:30', 25, 'Urgente', 1, 'Rechazado', NULL, '60782954'),
(1027, '2026-07-07', '08:30', '10:00', 45, 'Personal', 1, 'Aprobado', '00:45', '66761224'),
(1028, '2026-07-07', '07:48', '08:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '64396906'),
(1029, '2026-07-08', '07:00', '07:30', 25, 'Urgente', 1, 'Rechazado', NULL, '77409872'),
(1030, '2026-07-08', '13:52', '14:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '70451236'),
(1031, '2026-07-08', '07:40', '08:00', 10, 'Urgente', 1, 'Aprobado', '00:10', '74466276'),
(1032, '2026-07-09', '15:30', '16:00', 45, 'Personal', 1, 'Aprobado', '00:45', '75208847'),
(1033, '2026-07-09', '08:00', '09:00', 60, 'Personal', 2, 'Aprobado', '01:00', '59276364'),
(1034, '2026-07-10', '07:22', '07:30', 10, 'Urgente', 2, 'Aprobado', '00:10', '41258963'),
(1035, '2026-07-13', '07:40', '08:00', 40, 'Urgente', 1, 'Rechazado', NULL, '72902585'),
(1036, '2026-07-13', '08:00', '11:00', 30, 'Personal', 1, 'Aprobado', NULL, '74423452'),
(1037, '2026-07-13', '08:45', '09:00', 60, 'Personal', 1, 'Aprobado', '01:00', '77350043'),
(1038, '2026-07-13', '15:30', '16:00', 60, 'Personal', 1, 'Aprobado', '01:00', '41660226'),
(1039, '2026-07-14', '13:50', '14:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '73723261'),
(1040, '2026-07-14', '12:00', '15:00', 30, 'Personal', 1, 'Rechazado', NULL, '73981160'),
(1041, '2026-07-15', '07:20', '08:00', 40, 'Urgente', 2, 'Rechazado', NULL, '74839201'),
(1042, '2026-07-15', '10:45', '11:00', 60, 'Personal', 1, 'Aprobado', '01:00', '72123249'),
(1043, '2026-07-15', '07:20', '08:00', 20, 'Urgente', 1, 'Aprobado', NULL, '79360747'),
(1044, '2026-07-16', '07:25', '07:30', 30, 'Urgente', 1, 'Rechazado', NULL, '46987123'),
(1045, '2026-07-16', '13:20', '14:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '41258963'),
(1046, '2026-07-16', '13:55', '14:00', 15, 'Urgente', 2, 'Aprobado', '00:15', '60782954'),
(1047, '2026-07-17', '07:20', '08:00', 10, 'Urgente', 1, 'Aprobado', NULL, '72902585'),
(1048, '2026-07-17', '07:48', '08:00', 30, 'Urgente', 1, 'Aprobado', NULL, '73981160'),
(1049, '2026-07-20', '08:45', '09:00', 45, 'Personal', 1, 'Aprobado', NULL, '73698521'),
(1050, '2026-07-20', '08:45', '09:00', 60, 'Personal', 1, 'Aprobado', NULL, '56878758'),
(1051, '2026-07-20', '09:30', '11:00', 60, 'Personal', 1, 'Aprobado', '01:00', '64396906'),
(1052, '2026-07-21', '07:45', '08:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '75208847'),
(1053, '2026-07-21', '13:35', '14:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '46987123'),
(1054, '2026-07-21', '14:30', '16:00', 45, 'Personal', 2, 'Aprobado', '00:45', '59300639'),
(1055, '2026-07-21', '13:30', '14:00', 45, 'Urgente', 1, 'Rechazado', NULL, '45417273'),
(1056, '2026-07-22', '07:30', '08:00', 45, 'Urgente', 1, 'Aprobado', '00:45', '45417273'),
(1057, '2026-07-23', '13:20', '14:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '77350043'),
(1058, '2026-07-23', '07:00', '07:30', 30, 'Urgente', 1, 'Aprobado', NULL, '74423452'),
(1059, '2026-07-23', '07:00', '07:30', 20, 'Urgente', 1, 'Aprobado', '00:20', '47994000'),
(1060, '2026-07-23', '07:30', '09:00', 60, 'Personal', 2, 'Aprobado', NULL, '70175825'),
(1061, '2026-07-24', '09:45', '10:00', 60, 'Personal', 1, 'Aprobado', NULL, '63933440'),
(1062, '2026-07-24', '13:20', '14:00', 30, 'Urgente', 1, 'Aprobado', '00:30', '73723261'),
(1063, '2026-07-24', '13:20', '14:00', 30, 'Urgente', 1, 'Aprobado', '00:30', '45612378'),
(1064, '2026-07-27', '09:00', '10:00', 45, 'Personal', 1, 'Rechazado', NULL, '45417273'),
(1065, '2026-07-28', '10:00', '12:00', 60, 'Personal', 1, 'Rechazado', NULL, '74839201'),
(1066, '2026-07-28', '13:40', '14:00', 15, 'Urgente', 1, 'Aprobado', '00:15', '73723261'),
(1067, '2026-07-29', '07:35', '08:00', 25, 'Urgente', 1, 'Aprobado', NULL, '60782954');
INSERT INTO solicitud_permiso (id_permiso, fecha_solicitud, hora_registro, hora_de_inicio, duracion, subtipo, dias, estado, tiempo_laborar, dni) VALUES
(1068, '2026-07-29', '13:35', '14:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '47994000'),
(1069, '2026-07-29', '07:48', '08:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '66761224'),
(1070, '2026-07-30', '15:00', '16:00', 60, 'Personal', 1, 'Aprobado', '01:00', '72952513'),
(1071, '2026-07-31', '08:45', '09:00', 60, 'Personal', 1, 'Aprobado', '01:00', '41660226'),
(1072, '2026-07-31', '07:20', '08:00', 10, 'Urgente', 1, 'Rechazado', NULL, '74466276'),
(1073, '2026-07-31', '14:15', '15:00', 30, 'Personal', 1, 'Rechazado', NULL, '74423452'),
(1074, '2026-08-03', '07:52', '08:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '73981160'),
(1075, '2026-08-03', '10:00', '12:00', 45, 'Personal', 1, 'Rechazado', NULL, '56101703'),
(1076, '2026-08-04', '13:00', '15:00', 60, 'Personal', 1, 'Aprobado', '01:00', '49454857'),
(1077, '2026-08-04', '14:00', '15:00', 30, 'Personal', 2, 'Aprobado', '00:30', '46887842'),
(1078, '2026-08-05', '07:48', '08:00', 15, 'Urgente', 1, 'Aprobado', NULL, '62843493'),
(1079, '2026-08-05', '07:20', '08:00', 15, 'Urgente', 1, 'Aprobado', '00:15', '73698521'),
(1080, '2026-08-05', '09:30', '10:00', 60, 'Personal', 1, 'Aprobado', '01:00', '41258963'),
(1081, '2026-08-05', '07:20', '08:00', 30, 'Urgente', 1, 'Aprobado', '00:30', '77409872'),
(1082, '2026-08-06', '13:20', '14:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '79360747'),
(1083, '2026-08-07', '07:50', '08:00', 40, 'Urgente', 1, 'Rechazado', NULL, '41660226'),
(1084, '2026-08-07', '07:00', '07:30', 15, 'Urgente', 1, 'Aprobado', '00:15', '70451236'),
(1085, '2026-08-10', '08:30', '10:00', 30, 'Personal', 2, 'Rechazado', NULL, '70451236'),
(1086, '2026-08-10', '07:50', '08:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '68183451'),
(1087, '2026-08-11', '07:05', '07:30', 15, 'Urgente', 1, 'Aprobado', '00:15', '71324598'),
(1088, '2026-08-11', '10:45', '11:00', 60, 'Personal', 1, 'Aprobado', NULL, '77409872'),
(1089, '2026-08-11', '07:20', '07:30', 45, 'Urgente', 1, 'Aprobado', '00:45', '56101703'),
(1090, '2026-08-12', '06:50', '07:30', 40, 'Urgente', 1, 'Aprobado', '00:40', '41258963'),
(1091, '2026-08-12', '07:50', '08:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '78424442'),
(1092, '2026-08-13', '06:50', '07:30', 45, 'Urgente', 1, 'Aprobado', NULL, '72952513'),
(1093, '2026-08-13', '13:40', '14:00', 30, 'Urgente', 1, 'Rechazado', NULL, '70175825'),
(1094, '2026-08-13', '08:15', '09:00', 30, 'Personal', 1, 'Aprobado', '00:30', '77409872'),
(1095, '2026-08-14', '07:40', '08:00', 25, 'Urgente', 1, 'Aprobado', NULL, '73698521'),
(1096, '2026-08-17', '11:30', '12:00', 60, 'Personal', 1, 'Aprobado', NULL, '41258963'),
(1097, '2026-08-17', '07:48', '08:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '45612378'),
(1098, '2026-08-18', '07:30', '08:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '41660226'),
(1099, '2026-08-19', '07:25', '07:30', 15, 'Urgente', 1, 'Rechazado', NULL, '73981160'),
(1100, '2026-08-19', '15:00', '16:00', 45, 'Personal', 1, 'Rechazado', NULL, '47814689'),
(1101, '2026-08-19', '13:45', '14:00', 45, 'Urgente', 1, 'Aprobado', NULL, '79360747'),
(1102, '2026-08-20', '07:00', '07:30', 15, 'Urgente', 1, 'Aprobado', NULL, '47814689'),
(1103, '2026-08-20', '09:15', '10:00', 30, 'Personal', 1, 'Aprobado', '00:30', '41660226'),
(1104, '2026-08-20', '12:00', '15:00', 60, 'Personal', 1, 'Aprobado', '01:00', '59276364'),
(1105, '2026-08-21', '07:30', '09:00', 60, 'Personal', 1, 'Aprobado', '01:00', '74466276'),
(1106, '2026-08-21', '07:18', '07:30', 10, 'Urgente', 1, 'Aprobado', '00:10', '56878758'),
(1107, '2026-08-21', '14:00', '15:00', 30, 'Personal', 1, 'Aprobado', NULL, '56101703'),
(1108, '2026-08-24', '10:00', '11:00', 60, 'Personal', 1, 'Aprobado', NULL, '72221744'),
(1109, '2026-08-24', '07:35', '08:00', 30, 'Urgente', 2, 'Aprobado', '00:30', '46987123'),
(1110, '2026-08-24', '10:45', '11:00', 30, 'Personal', 2, 'Aprobado', '00:30', '49454857'),
(1111, '2026-08-24', '15:30', '16:00', 60, 'Personal', 1, 'Rechazado', NULL, '72952513'),
(1112, '2026-08-25', '10:15', '11:00', 45, 'Personal', 1, 'Aprobado', '00:45', '45612378'),
(1113, '2026-08-25', '07:50', '08:00', 15, 'Urgente', 1, 'Aprobado', '00:15', '63933440'),
(1114, '2026-08-25', '07:30', '08:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '75208847'),
(1115, '2026-08-26', '08:15', '09:00', 60, 'Personal', 1, 'Aprobado', '01:00', '45417273'),
(1116, '2026-08-26', '07:15', '07:30', 20, 'Urgente', 1, 'Aprobado', NULL, '64396906'),
(1117, '2026-08-27', '07:25', '07:30', 15, 'Urgente', 1, 'Aprobado', '00:15', '70451236');
INSERT INTO solicitud_permiso (id_permiso, fecha_solicitud, hora_registro, hora_de_inicio, duracion, subtipo, dias, estado, tiempo_laborar, dni) VALUES
(1118, '2026-08-27', '13:30', '14:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '46887842'),
(1119, '2026-08-27', '07:30', '09:00', 60, 'Personal', 1, 'Rechazado', NULL, '73981160'),
(1120, '2026-08-28', '13:48', '14:00', 15, 'Urgente', 2, 'Aprobado', '00:15', '62843493'),
(1121, '2026-08-28', '13:50', '14:00', 45, 'Urgente', 1, 'Aprobado', NULL, '73698521'),
(1122, '2026-08-28', '13:35', '14:00', 30, 'Urgente', 1, 'Aprobado', '00:30', '56878758'),
(1123, '2026-08-28', '07:18', '07:30', 40, 'Urgente', 1, 'Aprobado', NULL, '56101703'),
(1124, '2026-08-31', '07:48', '08:00', 15, 'Urgente', 1, 'Rechazado', NULL, '45417273'),
(1125, '2026-08-31', '13:00', '16:00', 60, 'Personal', 1, 'Aprobado', '01:00', '73723261'),
(1126, '2026-09-01', '08:00', '11:00', 30, 'Personal', 1, 'Aprobado', NULL, '77409872'),
(1127, '2026-09-01', '10:30', '11:00', 60, 'Personal', 1, 'Aprobado', NULL, '70451236'),
(1128, '2026-09-02', '07:25', '07:30', 25, 'Urgente', 1, 'Aprobado', NULL, '72952513'),
(1129, '2026-09-04', '06:00', '09:00', 60, 'Personal', 1, 'Aprobado', '01:00', '60782954'),
(1130, '2026-09-07', '07:45', '08:00', 10, 'Urgente', 1, 'Aprobado', '00:10', '72221744'),
(1131, '2026-09-07', '10:15', '11:00', 60, 'Personal', 1, 'Aprobado', '01:00', '63933440'),
(1132, '2026-09-08', '13:30', '14:00', 15, 'Urgente', 1, 'Rechazado', NULL, '72123249'),
(1133, '2026-09-09', '07:30', '09:00', 45, 'Personal', 1, 'Aprobado', '00:45', '73723261'),
(1134, '2026-09-09', '09:15', '10:00', 45, 'Personal', 1, 'Aprobado', '00:45', '68183451'),
(1135, '2026-09-09', '07:20', '08:00', 20, 'Urgente', 1, 'Rechazado', NULL, '79360747'),
(1136, '2026-09-10', '07:15', '07:30', 20, 'Urgente', 1, 'Aprobado', '00:20', '62843493'),
(1137, '2026-09-11', '07:22', '07:30', 30, 'Urgente', 1, 'Aprobado', '00:30', '47814689'),
(1138, '2026-09-11', '07:55', '08:00', 30, 'Urgente', 1, 'Rechazado', NULL, '71324598'),
(1139, '2026-09-11', '13:00', '16:00', 45, 'Personal', 1, 'Aprobado', '00:45', '72902585'),
(1140, '2026-09-11', '15:30', '16:00', 60, 'Personal', 1, 'Aprobado', NULL, '68183451'),
(1141, '2026-09-14', '07:52', '08:00', 45, 'Urgente', 1, 'Aprobado', NULL, '72902585'),
(1142, '2026-09-15', '07:35', '08:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '59300639'),
(1143, '2026-09-15', '13:55', '14:00', 10, 'Urgente', 1, 'Aprobado', '00:10', '46887842'),
(1144, '2026-09-15', '13:35', '14:00', 20, 'Urgente', 1, 'Rechazado', NULL, '64396906'),
(1145, '2026-09-16', '13:30', '14:00', 10, 'Urgente', 1, 'Aprobado', '00:10', '73698521'),
(1146, '2026-09-16', '07:10', '07:30', 30, 'Urgente', 1, 'Aprobado', NULL, '74839201'),
(1147, '2026-09-17', '07:55', '08:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '74466276'),
(1148, '2026-09-18', '14:00', '15:00', 45, 'Personal', 1, 'Aprobado', '00:45', '74423452'),
(1149, '2026-09-18', '08:00', '11:00', 45, 'Personal', 1, 'Aprobado', NULL, '56101703'),
(1150, '2026-09-21', '07:55', '08:00', 20, 'Urgente', 1, 'Aprobado', NULL, '77350043'),
(1151, '2026-09-21', '07:50', '08:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '68334536'),
(1152, '2026-09-21', '13:35', '14:00', 25, 'Urgente', 2, 'Aprobado', NULL, '73981160'),
(1153, '2026-09-21', '09:00', '12:00', 30, 'Personal', 1, 'Aprobado', '00:30', '41660226'),
(1154, '2026-09-22', '07:48', '08:00', 15, 'Urgente', 1, 'Aprobado', NULL, '54107938'),
(1155, '2026-09-23', '14:00', '15:00', 60, 'Personal', 1, 'Aprobado', '01:00', '41660226'),
(1156, '2026-09-23', '08:30', '10:00', 60, 'Personal', 1, 'Rechazado', NULL, '41258963'),
(1157, '2026-09-23', '13:52', '14:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '72123249'),
(1158, '2026-09-23', '07:20', '08:00', 10, 'Urgente', 1, 'Rechazado', NULL, '78622241'),
(1159, '2026-09-24', '13:30', '15:00', 60, 'Personal', 1, 'Aprobado', '01:00', '70451236'),
(1160, '2026-09-24', '14:00', '15:00', 60, 'Personal', 1, 'Aprobado', '01:00', '73698521'),
(1161, '2026-09-24', '10:15', '11:00', 45, 'Personal', 1, 'Aprobado', '00:45', '60782954'),
(1162, '2026-09-25', '14:30', '16:00', 60, 'Personal', 1, 'Aprobado', '01:00', '59276364'),
(1163, '2026-09-25', '07:30', '08:00', 15, 'Urgente', 1, 'Aprobado', '00:15', '70175825'),
(1164, '2026-09-28', '13:00', '16:00', 45, 'Personal', 1, 'Aprobado', '00:45', '63933440'),
(1165, '2026-09-29', '07:35', '08:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '68334536'),
(1166, '2026-09-29', '07:45', '08:00', 10, 'Urgente', 1, 'Aprobado', NULL, '75208847'),
(1167, '2026-09-29', '15:00', '16:00', 60, 'Personal', 1, 'Aprobado', NULL, '66761224');
INSERT INTO solicitud_permiso (id_permiso, fecha_solicitud, hora_registro, hora_de_inicio, duracion, subtipo, dias, estado, tiempo_laborar, dni) VALUES
(1168, '2026-09-30', '07:48', '08:00', 10, 'Urgente', 1, 'Aprobado', '00:10', '59276364'),
(1169, '2026-10-01', '08:45', '09:00', 60, 'Personal', 1, 'Aprobado', NULL, '41660226'),
(1170, '2026-10-01', '07:15', '07:30', 40, 'Urgente', 1, 'Rechazado', NULL, '66761224'),
(1171, '2026-10-02', '15:45', '16:00', 45, 'Personal', 1, 'Aprobado', '00:45', '68334536'),
(1172, '2026-10-02', '14:00', '15:00', 30, 'Personal', 1, 'Aprobado', '00:30', '56878758'),
(1173, '2026-10-02', '13:30', '14:00', 40, 'Urgente', 1, 'Aprobado', NULL, '79360747'),
(1174, '2026-10-05', '14:00', '15:00', 30, 'Personal', 1, 'Aprobado', NULL, '41660226'),
(1175, '2026-10-05', '07:20', '07:30', 25, 'Urgente', 1, 'Aprobado', '00:25', '70175825'),
(1176, '2026-10-05', '07:22', '07:30', 25, 'Urgente', 1, 'Aprobado', '00:25', '56101703'),
(1177, '2026-10-06', '15:15', '16:00', 45, 'Personal', 1, 'Aprobado', '00:45', '74466276'),
(1178, '2026-10-06', '13:20', '14:00', 15, 'Urgente', 1, 'Aprobado', '00:15', '78622241'),
(1179, '2026-10-06', '13:52', '14:00', 45, 'Urgente', 1, 'Rechazado', NULL, '73981160'),
(1180, '2026-10-06', '10:15', '11:00', 60, 'Personal', 1, 'Aprobado', '01:00', '73698521'),
(1181, '2026-10-07', '13:45', '14:00', 15, 'Urgente', 1, 'Aprobado', '00:15', '56878758'),
(1182, '2026-10-07', '07:40', '08:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '74466276'),
(1183, '2026-10-07', '13:20', '14:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '49454857'),
(1184, '2026-10-07', '07:00', '07:30', 20, 'Urgente', 1, 'Aprobado', '00:20', '73981160'),
(1185, '2026-10-08', '07:50', '08:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '68334536'),
(1186, '2026-10-08', '07:18', '07:30', 10, 'Urgente', 1, 'Aprobado', '00:10', '74839201'),
(1187, '2026-10-08', '11:30', '12:00', 60, 'Personal', 1, 'Aprobado', '01:00', '73981160'),
(1188, '2026-10-08', '07:52', '08:00', 10, 'Urgente', 1, 'Rechazado', NULL, '66761224'),
(1189, '2026-10-09', '13:45', '14:00', 45, 'Urgente', 1, 'Aprobado', '00:45', '46987123'),
(1190, '2026-10-12', '07:18', '07:30', 25, 'Urgente', 2, 'Aprobado', '00:25', '46887842'),
(1191, '2026-10-12', '07:30', '08:00', 15, 'Urgente', 1, 'Aprobado', NULL, '62843493'),
(1192, '2026-10-12', '11:15', '12:00', 60, 'Personal', 2, 'Aprobado', '01:00', '64396906'),
(1193, '2026-10-12', '06:00', '09:00', 60, 'Personal', 1, 'Aprobado', '01:00', '70175825'),
(1194, '2026-10-13', '07:20', '07:30', 40, 'Urgente', 1, 'Aprobado', NULL, '45612378'),
(1195, '2026-10-13', '13:00', '15:00', 60, 'Personal', 1, 'Aprobado', NULL, '46987123'),
(1196, '2026-10-13', '08:15', '09:00', 60, 'Personal', 1, 'Aprobado', NULL, '63933440'),
(1197, '2026-10-13', '07:20', '08:00', 45, 'Urgente', 1, 'Aprobado', '00:45', '71324598'),
(1198, '2026-10-14', '06:50', '07:30', 30, 'Urgente', 2, 'Aprobado', '00:30', '49454857'),
(1199, '2026-10-14', '07:20', '08:00', 30, 'Urgente', 1, 'Aprobado', '00:30', '73723261'),
(1200, '2026-10-14', '08:15', '09:00', 45, 'Personal', 1, 'Aprobado', '00:45', '47994000'),
(1201, '2026-10-15', '14:45', '15:00', 60, 'Personal', 1, 'Aprobado', '01:00', '70175825'),
(1202, '2026-10-15', '07:20', '08:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '56878758'),
(1203, '2026-10-15', '13:40', '14:00', 10, 'Urgente', 1, 'Aprobado', '00:10', '70451236'),
(1204, '2026-10-16', '15:45', '16:00', 45, 'Personal', 1, 'Aprobado', '00:45', '79360747'),
(1205, '2026-10-16', '07:30', '08:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '68183451'),
(1206, '2026-10-16', '07:48', '08:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '72952513'),
(1207, '2026-10-19', '08:30', '10:00', 30, 'Personal', 1, 'Rechazado', NULL, '54107938'),
(1208, '2026-10-19', '14:30', '16:00', 45, 'Personal', 1, 'Aprobado', '00:45', '41258963'),
(1209, '2026-10-20', '13:30', '15:00', 30, 'Personal', 1, 'Aprobado', '00:30', '47814689'),
(1210, '2026-10-20', '11:30', '12:00', 30, 'Personal', 1, 'Aprobado', '00:30', '78424442'),
(1211, '2026-10-21', '07:30', '08:00', 25, 'Urgente', 1, 'Aprobado', NULL, '68334536'),
(1212, '2026-10-21', '13:35', '14:00', 40, 'Urgente', 1, 'Aprobado', '00:40', '59300639'),
(1213, '2026-10-22', '07:48', '08:00', 15, 'Urgente', 1, 'Aprobado', NULL, '41258963'),
(1214, '2026-10-22', '08:00', '09:00', 60, 'Personal', 1, 'Aprobado', '01:00', '54107938'),
(1215, '2026-10-22', '14:00', '16:00', 60, 'Personal', 1, 'Aprobado', '01:00', '59276364'),
(1216, '2026-10-23', '13:52', '14:00', 20, 'Urgente', 2, 'Aprobado', NULL, '41660226'),
(1217, '2026-10-26', '13:35', '14:00', 15, 'Urgente', 1, 'Aprobado', '00:15', '59300639');
INSERT INTO solicitud_permiso (id_permiso, fecha_solicitud, hora_registro, hora_de_inicio, duracion, subtipo, dias, estado, tiempo_laborar, dni) VALUES
(1218, '2026-10-26', '13:35', '14:00', 15, 'Urgente', 1, 'Aprobado', '00:15', '72902585'),
(1219, '2026-10-26', '08:00', '09:00', 60, 'Personal', 1, 'Aprobado', NULL, '73698521'),
(1220, '2026-10-27', '10:00', '12:00', 60, 'Personal', 1, 'Aprobado', '01:00', '64396906'),
(1221, '2026-10-27', '14:30', '16:00', 30, 'Personal', 1, 'Aprobado', '00:30', '75208847'),
(1222, '2026-10-28', '07:35', '08:00', 30, 'Urgente', 1, 'Aprobado', '00:30', '56101703'),
(1223, '2026-10-28', '10:30', '11:00', 60, 'Personal', 2, 'Aprobado', NULL, '72123249'),
(1224, '2026-10-28', '07:00', '07:30', 45, 'Urgente', 1, 'Aprobado', '00:45', '71324598'),
(1225, '2026-10-29', '07:00', '09:00', 60, 'Personal', 1, 'Rechazado', NULL, '49454857'),
(1226, '2026-10-30', '13:00', '16:00', 60, 'Personal', 2, 'Aprobado', '01:00', '75208847'),
(1227, '2026-10-30', '13:30', '15:00', 60, 'Personal', 1, 'Aprobado', '01:00', '46987123'),
(1228, '2026-10-30', '09:00', '11:00', 60, 'Personal', 1, 'Rechazado', NULL, '72952513'),
(1229, '2026-11-02', '07:40', '08:00', 15, 'Urgente', 1, 'Aprobado', '00:15', '56101703'),
(1230, '2026-11-03', '14:45', '15:00', 60, 'Personal', 1, 'Aprobado', NULL, '73723261'),
(1231, '2026-11-04', '07:50', '08:00', 10, 'Urgente', 1, 'Rechazado', NULL, '73981160'),
(1232, '2026-11-04', '07:00', '07:30', 25, 'Urgente', 1, 'Aprobado', NULL, '70451236'),
(1233, '2026-11-04', '15:30', '16:00', 45, 'Personal', 1, 'Aprobado', '00:45', '72221744'),
(1234, '2026-11-04', '08:30', '10:00', 60, 'Personal', 2, 'Aprobado', '01:00', '45612378'),
(1235, '2026-11-05', '15:00', '16:00', 60, 'Personal', 1, 'Rechazado', NULL, '74466276'),
(1236, '2026-11-05', '07:55', '08:00', 25, 'Urgente', 1, 'Aprobado', '00:25', '59300639'),
(1237, '2026-11-05', '07:20', '08:00', 15, 'Urgente', 2, 'Aprobado', '00:15', '73698521'),
(1238, '2026-11-05', '08:00', '11:00', 45, 'Personal', 2, 'Aprobado', '00:45', '71324598'),
(1239, '2026-11-06', '07:48', '08:00', 20, 'Urgente', 2, 'Aprobado', '00:20', '78622241'),
(1240, '2026-11-06', '13:40', '14:00', 10, 'Urgente', 1, 'Aprobado', '00:10', '73723261'),
(1241, '2026-11-06', '09:00', '12:00', 60, 'Personal', 1, 'Aprobado', '01:00', '59276364'),
(1242, '2026-11-09', '11:00', '12:00', 60, 'Personal', 2, 'Aprobado', '01:00', '41258963'),
(1243, '2026-11-09', '09:15', '10:00', 60, 'Personal', 2, 'Aprobado', '01:00', '73698521'),
(1244, '2026-11-10', '10:45', '11:00', 30, 'Personal', 1, 'Rechazado', NULL, '68183451'),
(1245, '2026-11-10', '07:55', '08:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '46987123'),
(1246, '2026-11-10', '07:25', '07:30', 15, 'Urgente', 1, 'Rechazado', NULL, '72221744'),
(1247, '2026-11-11', '13:30', '14:00', 45, 'Urgente', 1, 'Aprobado', '00:45', '63933440'),
(1248, '2026-11-12', '13:00', '16:00', 30, 'Personal', 1, 'Rechazado', NULL, '78424442'),
(1249, '2026-11-12', '08:30', '09:00', 30, 'Personal', 1, 'Aprobado', NULL, '72221744'),
(1250, '2026-11-12', '07:15', '07:30', 45, 'Urgente', 1, 'Aprobado', NULL, '68334536'),
(1251, '2026-11-13', '07:50', '08:00', 10, 'Urgente', 1, 'Aprobado', NULL, '70451236'),
(1252, '2026-11-13', '14:30', '16:00', 45, 'Personal', 1, 'Aprobado', '00:45', '46887842'),
(1253, '2026-11-16', '14:30', '16:00', 30, 'Personal', 1, 'Aprobado', '00:30', '77409872'),
(1254, '2026-11-16', '10:00', '11:00', 60, 'Personal', 1, 'Aprobado', NULL, '68334536'),
(1255, '2026-11-16', '07:40', '08:00', 20, 'Urgente', 1, 'Aprobado', '00:20', '75208847'),
(1256, '2026-11-17', '07:52', '08:00', 30, 'Urgente', 1, 'Pendiente', NULL, '60782954'),
(1257, '2026-11-17', '15:30', '16:00', 30, 'Personal', 1, 'Pendiente', NULL, '63933440'),
(1258, '2026-11-17', '11:30', '12:00', 60, 'Personal', 1, 'Pendiente', NULL, '73698521'),
(1259, '2026-11-18', '11:15', '12:00', 30, 'Personal', 1, 'Aprobado', NULL, '47814689'),
(1260, '2026-11-19', '10:15', '11:00', 60, 'Personal', 1, 'Pendiente', NULL, '77409872'),
(1261, '2026-11-19', '07:30', '08:00', 25, 'Urgente', 1, 'Pendiente', NULL, '66761224'),
(1262, '2026-11-20', '15:30', '16:00', 60, 'Personal', 1, 'Pendiente', NULL, '71324598'),
(1263, '2026-11-20', '13:48', '14:00', 20, 'Urgente', 1, 'Pendiente', NULL, '77409872'),
(1264, '2026-11-20', '13:20', '14:00', 25, 'Urgente', 1, 'Pendiente', NULL, '54107938');

INSERT INTO historial_permiso (id_permiso, tipo_de_permiso, motivo, fecha) VALUES
(1018, 'Personal', 'Trámite en SUNAT', '2026-07-02'),
(1019, 'Tardanza justificada', 'Falla del transporte público', '2026-07-01'),
(1020, 'Salida anticipada', 'Trámite en SUNAT', '2026-07-02'),
(1021, 'Tardanza justificada', 'Paro de transportistas', '2026-07-04'),
(1022, 'Tardanza', 'Paro de transportistas', '2026-07-03'),
(1023, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-07-03'),
(1024, 'Tardanza', 'Trámite urgente en el banco', '2026-07-06'),
(1025, 'Tardanza', 'Tráfico', '2026-07-06'),
(1026, 'Tardanza justificada', 'Trámite urgente en el banco', '2026-07-08'),
(1027, 'Personal', 'Control médico', '2026-07-07'),
(1028, 'Tardanza', 'Lluvia intensa', '2026-07-07'),
(1029, 'Tardanza justificada', 'Emergencia familiar', '2026-07-08'),
(1030, 'Tardanza', 'Malestar estomacal', '2026-07-08'),
(1031, 'Tardanza', 'Paro de transportistas', '2026-07-09'),
(1032, 'Personal', 'Trámite en RENIEC', '2026-07-09'),
(1033, 'Personal', 'Reunión en colegio del hijo', '2026-07-09'),
(1034, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-07-10'),
(1035, 'Tardanza justificada', 'Falla del transporte público', '2026-07-13'),
(1036, 'Salida anticipada', 'Reunión en colegio del hijo', '2026-07-14'),
(1037, 'Salida anticipada', 'Trámite notarial', '2026-07-14'),
(1038, 'Salida anticipada', 'Trámite notarial', '2026-07-13'),
(1039, 'Tardanza justificada', 'Corte de agua en domicilio', '2026-07-14'),
(1040, 'Salida anticipada', 'Trámite bancario', '2026-07-15'),
(1041, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-07-15'),
(1042, 'Salida anticipada', 'Matrícula de hijo', '2026-07-15'),
(1043, 'Tardanza', 'Corte de agua en domicilio', '2026-07-15'),
(1044, 'Tardanza', 'Lluvia intensa', '2026-07-16'),
(1045, 'Tardanza', 'Cita médica', '2026-07-16'),
(1046, 'Tardanza justificada', 'Lluvia intensa', '2026-07-16'),
(1047, 'Tardanza justificada', 'Paro de transportistas', '2026-07-17'),
(1048, 'Tardanza', 'Falla del transporte público', '2026-07-17'),
(1049, 'Salida anticipada', 'Cita odontológica', '2026-07-20'),
(1050, 'Salida anticipada', 'Cita en EsSalud', '2026-07-21'),
(1051, 'Salida anticipada', 'Trámite bancario', '2026-07-20'),
(1052, 'Tardanza justificada', 'Malestar estomacal', '2026-07-21'),
(1053, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-07-21'),
(1054, 'Personal', 'Trámite en RENIEC', '2026-07-21'),
(1055, 'Tardanza', 'Tráfico', '2026-07-21'),
(1056, 'Tardanza', 'Lluvia intensa', '2026-07-22'),
(1057, 'Tardanza justificada', 'Falla del transporte público', '2026-07-23'),
(1058, 'Tardanza', 'Emergencia familiar', '2026-07-23'),
(1059, 'Tardanza justificada', 'Corte de agua en domicilio', '2026-07-23'),
(1060, 'Salida anticipada', 'Trámite en SUNAT', '2026-07-23'),
(1061, 'Personal', 'Trámite en RENIEC', '2026-07-24'),
(1062, 'Tardanza justificada', 'Cita médica', '2026-07-25'),
(1063, 'Tardanza', 'Cita médica', '2026-07-24'),
(1064, 'Personal', 'Trámite en SUNAT', '2026-07-27'),
(1065, 'Salida anticipada', 'Control médico', '2026-07-28'),
(1066, 'Tardanza', 'Paro de transportistas', '2026-07-28'),
(1067, 'Tardanza justificada', 'Malestar estomacal', '2026-07-29'),
(1068, 'Tardanza justificada', 'Emergencia familiar', '2026-07-30'),
(1069, 'Tardanza', 'Paro de transportistas', '2026-07-29'),
(1070, 'Salida anticipada', 'Reunión en colegio del hijo', '2026-07-30'),
(1071, 'Salida anticipada', 'Control médico', '2026-08-01'),
(1072, 'Tardanza justificada', 'Trámite urgente en el banco', '2026-07-31'),
(1073, 'Personal', 'Cita en EsSalud', '2026-07-31'),
(1074, 'Tardanza justificada', 'Cita médica', '2026-08-03'),
(1075, 'Personal', 'Trámite en SUNAT', '2026-08-03'),
(1076, 'Personal', 'Cita en EsSalud', '2026-08-05'),
(1077, 'Personal', 'Matrícula de hijo', '2026-08-04');
INSERT INTO historial_permiso (id_permiso, tipo_de_permiso, motivo, fecha) VALUES
(1078, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-08-05'),
(1079, 'Tardanza justificada', 'Emergencia familiar', '2026-08-06'),
(1080, 'Personal', 'Trámite en RENIEC', '2026-08-05'),
(1081, 'Tardanza justificada', 'Malestar estomacal', '2026-08-06'),
(1082, 'Tardanza', 'Cita médica', '2026-08-07'),
(1083, 'Tardanza', 'Emergencia familiar', '2026-08-08'),
(1084, 'Tardanza', 'Emergencia familiar', '2026-08-08'),
(1085, 'Personal', 'Reunión en colegio del hijo', '2026-08-11'),
(1086, 'Tardanza justificada', 'Cita médica', '2026-08-11'),
(1087, 'Tardanza', 'Malestar estomacal', '2026-08-11'),
(1088, 'Salida anticipada', 'Matrícula de hijo', '2026-08-11'),
(1089, 'Tardanza justificada', 'Falla del transporte público', '2026-08-11'),
(1090, 'Tardanza justificada', 'Corte de agua en domicilio', '2026-08-12'),
(1091, 'Tardanza justificada', 'Emergencia familiar', '2026-08-13'),
(1092, 'Tardanza', 'Tráfico', '2026-08-13'),
(1093, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-08-14'),
(1094, 'Personal', 'Cita en EsSalud', '2026-08-14'),
(1095, 'Tardanza justificada', 'Malestar estomacal', '2026-08-14'),
(1096, 'Salida anticipada', 'Trámite bancario', '2026-08-18'),
(1097, 'Tardanza', 'Lluvia intensa', '2026-08-17'),
(1098, 'Tardanza', 'Falla del transporte público', '2026-08-18'),
(1099, 'Tardanza justificada', 'Corte de agua en domicilio', '2026-08-19'),
(1100, 'Personal', 'Matrícula de hijo', '2026-08-20'),
(1101, 'Tardanza justificada', 'Corte de agua en domicilio', '2026-08-19'),
(1102, 'Tardanza justificada', 'Corte de agua en domicilio', '2026-08-20'),
(1103, 'Personal', 'Trámite bancario', '2026-08-20'),
(1104, 'Salida anticipada', 'Trámite en SUNAT', '2026-08-21'),
(1105, 'Salida anticipada', 'Control médico', '2026-08-22'),
(1106, 'Tardanza justificada', 'Trámite urgente en el banco', '2026-08-22'),
(1107, 'Personal', 'Cita odontológica', '2026-08-21'),
(1108, 'Personal', 'Cita en EsSalud', '2026-08-24'),
(1109, 'Tardanza justificada', 'Emergencia familiar', '2026-08-24'),
(1110, 'Salida anticipada', 'Control médico', '2026-08-25'),
(1111, 'Salida anticipada', 'Cita odontológica', '2026-08-24'),
(1112, 'Personal', 'Control médico', '2026-08-25'),
(1113, 'Tardanza justificada', 'Trámite urgente en el banco', '2026-08-26'),
(1114, 'Tardanza justificada', 'Lluvia intensa', '2026-08-25'),
(1115, 'Personal', 'Trámite notarial', '2026-08-26'),
(1116, 'Tardanza', 'Paro de transportistas', '2026-08-26'),
(1117, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-08-28'),
(1118, 'Tardanza justificada', 'Malestar estomacal', '2026-08-28'),
(1119, 'Personal', 'Trámite en SUNAT', '2026-08-27'),
(1120, 'Tardanza', 'Paro de transportistas', '2026-08-28'),
(1121, 'Tardanza justificada', 'Falla del transporte público', '2026-08-28'),
(1122, 'Tardanza', 'Trámite urgente en el banco', '2026-08-29'),
(1123, 'Tardanza justificada', 'Lluvia intensa', '2026-08-28'),
(1124, 'Tardanza justificada', 'Emergencia familiar', '2026-08-31'),
(1125, 'Salida anticipada', 'Trámite bancario', '2026-09-01'),
(1126, 'Salida anticipada', 'Matrícula de hijo', '2026-09-01'),
(1127, 'Salida anticipada', 'Trámite en SUNAT', '2026-09-01'),
(1128, 'Tardanza justificada', 'Lluvia intensa', '2026-09-03'),
(1129, 'Personal', 'Matrícula de hijo', '2026-09-04'),
(1130, 'Tardanza', 'Falla del transporte público', '2026-09-08'),
(1131, 'Personal', 'Control médico', '2026-09-07'),
(1132, 'Tardanza justificada', 'Paro de transportistas', '2026-09-08'),
(1133, 'Personal', 'Matrícula de hijo', '2026-09-09'),
(1134, 'Personal', 'Trámite notarial', '2026-09-09'),
(1135, 'Tardanza', 'Corte de agua en domicilio', '2026-09-09'),
(1136, 'Tardanza', 'Llevar a hijo al colegio', '2026-09-10'),
(1137, 'Tardanza', 'Falla del transporte público', '2026-09-11');
INSERT INTO historial_permiso (id_permiso, tipo_de_permiso, motivo, fecha) VALUES
(1138, 'Tardanza', 'Tráfico', '2026-09-12'),
(1139, 'Salida anticipada', 'Gestión municipal', '2026-09-11'),
(1140, 'Salida anticipada', 'Trámite en RENIEC', '2026-09-11'),
(1141, 'Tardanza', 'Falla del transporte público', '2026-09-15'),
(1142, 'Tardanza justificada', 'Paro de transportistas', '2026-09-15'),
(1143, 'Tardanza justificada', 'Trámite urgente en el banco', '2026-09-15'),
(1144, 'Tardanza', 'Paro de transportistas', '2026-09-15'),
(1145, 'Tardanza justificada', 'Malestar estomacal', '2026-09-16'),
(1146, 'Tardanza', 'Paro de transportistas', '2026-09-16'),
(1147, 'Tardanza justificada', 'Cita médica', '2026-09-17'),
(1148, 'Personal', 'Control médico', '2026-09-18'),
(1149, 'Personal', 'Control médico', '2026-09-19'),
(1150, 'Tardanza justificada', 'Lluvia intensa', '2026-09-22'),
(1151, 'Tardanza', 'Cita médica', '2026-09-22'),
(1152, 'Tardanza justificada', 'Paro de transportistas', '2026-09-21'),
(1153, 'Salida anticipada', 'Trámite en SUNAT', '2026-09-21'),
(1154, 'Tardanza', 'Falla del transporte público', '2026-09-23'),
(1155, 'Personal', 'Trámite notarial', '2026-09-23'),
(1156, 'Salida anticipada', 'Trámite bancario', '2026-09-23'),
(1157, 'Tardanza', 'Tráfico', '2026-09-24'),
(1158, 'Tardanza justificada', 'Malestar estomacal', '2026-09-24'),
(1159, 'Personal', 'Gestión municipal', '2026-09-24'),
(1160, 'Salida anticipada', 'Gestión municipal', '2026-09-24'),
(1161, 'Salida anticipada', 'Trámite en SUNAT', '2026-09-25'),
(1162, 'Personal', 'Trámite notarial', '2026-09-25'),
(1163, 'Tardanza', 'Cita médica', '2026-09-26'),
(1164, 'Personal', 'Trámite en RENIEC', '2026-09-28'),
(1165, 'Tardanza', 'Falla del transporte público', '2026-09-30'),
(1166, 'Tardanza', 'Trámite urgente en el banco', '2026-09-29'),
(1167, 'Salida anticipada', 'Control médico', '2026-09-29'),
(1168, 'Tardanza justificada', 'Tráfico', '2026-09-30'),
(1169, 'Personal', 'Trámite en RENIEC', '2026-10-01'),
(1170, 'Tardanza', 'Llevar a hijo al colegio', '2026-10-01'),
(1171, 'Personal', 'Matrícula de hijo', '2026-10-02'),
(1172, 'Salida anticipada', 'Gestión municipal', '2026-10-02'),
(1173, 'Tardanza justificada', 'Corte de agua en domicilio', '2026-10-02'),
(1174, 'Salida anticipada', 'Trámite bancario', '2026-10-05'),
(1175, 'Tardanza justificada', 'Paro de transportistas', '2026-10-06'),
(1176, 'Tardanza justificada', 'Trámite urgente en el banco', '2026-10-06'),
(1177, 'Salida anticipada', 'Trámite notarial', '2026-10-07'),
(1178, 'Tardanza', 'Corte de agua en domicilio', '2026-10-07'),
(1179, 'Tardanza justificada', 'Tráfico', '2026-10-06'),
(1180, 'Salida anticipada', 'Reunión en colegio del hijo', '2026-10-07'),
(1181, 'Tardanza', 'Tráfico', '2026-10-07'),
(1182, 'Tardanza justificada', 'Emergencia familiar', '2026-10-08'),
(1183, 'Tardanza justificada', 'Paro de transportistas', '2026-10-07'),
(1184, 'Tardanza justificada', 'Corte de agua en domicilio', '2026-10-08'),
(1185, 'Tardanza', 'Emergencia familiar', '2026-10-08'),
(1186, 'Tardanza', 'Cita médica', '2026-10-09'),
(1187, 'Salida anticipada', 'Control médico', '2026-10-08'),
(1188, 'Tardanza', 'Trámite urgente en el banco', '2026-10-08'),
(1189, 'Tardanza', 'Llevar a hijo al colegio', '2026-10-09'),
(1190, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-10-12'),
(1191, 'Tardanza justificada', 'Malestar estomacal', '2026-10-12'),
(1192, 'Personal', 'Cita odontológica', '2026-10-12'),
(1193, 'Salida anticipada', 'Cita odontológica', '2026-10-12'),
(1194, 'Tardanza justificada', 'Cita médica', '2026-10-13'),
(1195, 'Personal', 'Gestión municipal', '2026-10-13'),
(1196, 'Salida anticipada', 'Cita en EsSalud', '2026-10-13'),
(1197, 'Tardanza', 'Emergencia familiar', '2026-10-13');
INSERT INTO historial_permiso (id_permiso, tipo_de_permiso, motivo, fecha) VALUES
(1198, 'Tardanza', 'Cita médica', '2026-10-14'),
(1199, 'Tardanza', 'Tráfico', '2026-10-14'),
(1200, 'Salida anticipada', 'Reunión en colegio del hijo', '2026-10-15'),
(1201, 'Personal', 'Matrícula de hijo', '2026-10-16'),
(1202, 'Tardanza justificada', 'Cita médica', '2026-10-15'),
(1203, 'Tardanza', 'Emergencia familiar', '2026-10-15'),
(1204, 'Personal', 'Trámite en SUNAT', '2026-10-16'),
(1205, 'Tardanza justificada', 'Cita médica', '2026-10-16'),
(1206, 'Tardanza justificada', 'Cita médica', '2026-10-16'),
(1207, 'Salida anticipada', 'Trámite en SUNAT', '2026-10-20'),
(1208, 'Personal', 'Control médico', '2026-10-20'),
(1209, 'Personal', 'Trámite en SUNAT', '2026-10-20'),
(1210, 'Salida anticipada', 'Reunión en colegio del hijo', '2026-10-20'),
(1211, 'Tardanza justificada', 'Cita médica', '2026-10-21'),
(1212, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-10-21'),
(1213, 'Tardanza justificada', 'Falla del transporte público', '2026-10-23'),
(1214, 'Personal', 'Trámite notarial', '2026-10-22'),
(1215, 'Salida anticipada', 'Trámite en RENIEC', '2026-10-22'),
(1216, 'Tardanza', 'Llevar a hijo al colegio', '2026-10-23'),
(1217, 'Tardanza', 'Cita médica', '2026-10-26'),
(1218, 'Tardanza justificada', 'Paro de transportistas', '2026-10-26'),
(1219, 'Salida anticipada', 'Trámite en RENIEC', '2026-10-27'),
(1220, 'Personal', 'Trámite en RENIEC', '2026-10-27'),
(1221, 'Salida anticipada', 'Trámite bancario', '2026-10-27'),
(1222, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-10-28'),
(1223, 'Personal', 'Trámite notarial', '2026-10-28'),
(1224, 'Tardanza', 'Falla del transporte público', '2026-10-29'),
(1225, 'Salida anticipada', 'Trámite bancario', '2026-10-30'),
(1226, 'Salida anticipada', 'Trámite en RENIEC', '2026-10-31'),
(1227, 'Personal', 'Trámite en SUNAT', '2026-10-30'),
(1228, 'Salida anticipada', 'Gestión municipal', '2026-10-30'),
(1229, 'Tardanza justificada', 'Malestar estomacal', '2026-11-02'),
(1230, 'Salida anticipada', 'Trámite en SUNAT', '2026-11-03'),
(1231, 'Tardanza', 'Tráfico', '2026-11-04'),
(1232, 'Tardanza justificada', 'Cita médica', '2026-11-05'),
(1233, 'Personal', 'Cita odontológica', '2026-11-04'),
(1234, 'Personal', 'Cita odontológica', '2026-11-04'),
(1235, 'Personal', 'Gestión municipal', '2026-11-06'),
(1236, 'Tardanza', 'Cita médica', '2026-11-05'),
(1237, 'Tardanza justificada', 'Cita médica', '2026-11-05'),
(1238, 'Personal', 'Trámite notarial', '2026-11-06'),
(1239, 'Tardanza justificada', 'Cita médica', '2026-11-06'),
(1240, 'Tardanza', 'Paro de transportistas', '2026-11-07'),
(1241, 'Personal', 'Trámite bancario', '2026-11-06'),
(1242, 'Salida anticipada', 'Cita odontológica', '2026-11-10'),
(1243, 'Personal', 'Cita odontológica', '2026-11-10'),
(1244, 'Personal', 'Control médico', '2026-11-10'),
(1245, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-11-10'),
(1246, 'Tardanza justificada', 'Falla del transporte público', '2026-11-10'),
(1247, 'Tardanza justificada', 'Cita médica', '2026-11-12'),
(1248, 'Personal', 'Trámite en SUNAT', '2026-11-13'),
(1249, 'Salida anticipada', 'Gestión municipal', '2026-11-12'),
(1250, 'Tardanza', 'Trámite urgente en el banco', '2026-11-13'),
(1251, 'Tardanza', 'Lluvia intensa', '2026-11-13'),
(1252, 'Personal', 'Trámite notarial', '2026-11-13'),
(1253, 'Personal', 'Cita odontológica', '2026-11-17'),
(1254, 'Personal', 'Trámite en RENIEC', '2026-11-17'),
(1255, 'Tardanza justificada', 'Llevar a hijo al colegio', '2026-11-16'),
(1259, 'Salida anticipada', 'Reunión en colegio del hijo', '2026-11-18');

INSERT INTO compensacion (id_compensacion, fecha_compensacion, hora_inicio, hora_fin, id_permiso) VALUES
(5012, '2026-07-02', '17:00', '17:20', 1019),
(5013, '2026-07-06', '17:00', '17:10', 1019),
(5014, '2026-07-03', '17:00', '17:45', 1020),
(5015, '2026-07-06', '17:00', '17:15', 1020),
(5016, '2026-07-06', '17:00', '17:15', 1023),
(5017, '2026-07-08', '17:00', '17:15', 1023),
(5018, '2026-07-07', '17:00', '17:30', 1024),
(5019, '2026-07-08', '17:00', '17:15', 1027),
(5020, '2026-07-09', '17:00', '17:30', 1027),
(5021, '2026-07-08', '17:00', '17:20', 1028),
(5022, '2026-07-09', '17:00', '17:05', 1028),
(5023, '2026-07-09', '17:00', '17:15', 1030),
(5024, '2026-07-10', '17:00', '17:10', 1030),
(5025, '2026-07-09', '17:00', '17:10', 1031),
(5026, '2026-07-10', '17:00', '17:45', 1032),
(5027, '2026-07-10', '17:00', '17:15', 1033),
(5028, '2026-07-13', '17:00', '17:30', 1033),
(5029, '2026-07-15', '17:00', '17:15', 1033),
(5030, '2026-07-13', '17:00', '17:10', 1034),
(5031, '2026-07-14', '17:00', '17:15', 1037),
(5032, '2026-07-15', '17:00', '17:20', 1037),
(5033, '2026-07-16', '17:00', '17:15', 1037),
(5034, '2026-07-17', '17:00', '17:10', 1037),
(5035, '2026-07-14', '17:00', '18:00', 1038),
(5036, '2026-07-15', '17:00', '17:20', 1039),
(5037, '2026-07-16', '17:00', '17:20', 1042),
(5038, '2026-07-17', '17:00', '17:40', 1042),
(5039, '2026-07-17', '17:00', '17:20', 1045),
(5040, '2026-07-17', '17:00', '17:15', 1046),
(5041, '2026-07-21', '17:00', '17:45', 1051),
(5042, '2026-07-24', '17:00', '17:15', 1051),
(5043, '2026-07-22', '17:00', '17:20', 1052),
(5044, '2026-07-22', '17:00', '17:40', 1053),
(5045, '2026-07-22', '17:00', '17:45', 1054),
(5046, '2026-07-23', '17:00', '17:15', 1056),
(5047, '2026-07-24', '17:00', '17:30', 1056),
(5048, '2026-07-24', '17:00', '17:20', 1057),
(5049, '2026-07-27', '17:00', '17:20', 1057),
(5050, '2026-07-24', '17:00', '17:20', 1059),
(5051, '2026-07-27', '17:00', '17:30', 1062),
(5052, '2026-07-27', '17:00', '17:30', 1063),
(5053, '2026-07-29', '17:00', '17:15', 1066),
(5054, '2026-07-30', '17:00', '17:40', 1068),
(5055, '2026-07-30', '17:00', '17:20', 1069),
(5056, '2026-08-03', '17:00', '17:20', 1069),
(5057, '2026-07-31', '17:00', '17:30', 1070),
(5058, '2026-08-03', '17:00', '17:15', 1070),
(5059, '2026-08-04', '17:00', '17:15', 1070),
(5060, '2026-08-03', '17:00', '17:45', 1071),
(5061, '2026-08-04', '17:00', '17:15', 1071),
(5062, '2026-08-04', '17:00', '17:30', 1074),
(5063, '2026-08-05', '17:00', '17:10', 1074),
(5064, '2026-08-05', '17:00', '17:15', 1076),
(5065, '2026-08-10', '17:00', '17:20', 1076),
(5066, '2026-08-12', '17:00', '17:20', 1076),
(5067, '2026-08-14', '17:00', '17:05', 1076),
(5068, '2026-08-05', '17:00', '17:20', 1077),
(5069, '2026-08-06', '17:00', '17:10', 1077),
(5070, '2026-08-06', '17:00', '17:15', 1079),
(5071, '2026-08-06', '17:00', '17:45', 1080);
INSERT INTO compensacion (id_compensacion, fecha_compensacion, hora_inicio, hora_fin, id_permiso) VALUES
(5072, '2026-08-07', '17:00', '17:15', 1080),
(5073, '2026-08-06', '17:00', '17:30', 1081),
(5074, '2026-08-07', '17:00', '17:20', 1082),
(5075, '2026-08-10', '17:00', '17:05', 1082),
(5076, '2026-08-10', '17:00', '17:15', 1084),
(5077, '2026-08-11', '17:00', '17:20', 1086),
(5078, '2026-08-12', '17:00', '17:15', 1087),
(5079, '2026-08-12', '17:00', '17:45', 1089),
(5080, '2026-08-13', '17:00', '17:30', 1090),
(5081, '2026-08-14', '17:00', '17:10', 1090),
(5082, '2026-08-13', '17:00', '17:15', 1091),
(5083, '2026-08-17', '17:00', '17:05', 1091),
(5084, '2026-08-14', '17:00', '17:20', 1094),
(5085, '2026-08-17', '17:00', '17:10', 1094),
(5086, '2026-08-18', '17:00', '17:20', 1097),
(5087, '2026-08-19', '17:00', '17:25', 1098),
(5088, '2026-08-21', '17:00', '17:30', 1103),
(5089, '2026-08-21', '17:00', '17:30', 1104),
(5090, '2026-08-24', '17:00', '17:30', 1104),
(5091, '2026-08-24', '17:00', '17:15', 1105),
(5092, '2026-08-25', '17:00', '17:30', 1105),
(5093, '2026-08-28', '17:00', '17:15', 1105),
(5094, '2026-08-24', '17:00', '17:10', 1106),
(5095, '2026-08-25', '17:00', '17:30', 1109),
(5096, '2026-08-25', '17:00', '17:20', 1110),
(5097, '2026-08-26', '17:00', '17:10', 1110),
(5098, '2026-08-26', '17:00', '17:45', 1112),
(5099, '2026-08-26', '17:00', '17:15', 1113),
(5100, '2026-08-26', '17:00', '17:20', 1114),
(5101, '2026-08-27', '17:00', '17:15', 1115),
(5102, '2026-08-31', '17:00', '17:45', 1115),
(5103, '2026-08-28', '17:00', '17:15', 1117),
(5104, '2026-08-28', '17:00', '17:30', 1118),
(5105, '2026-08-31', '17:00', '17:10', 1118),
(5106, '2026-08-31', '17:00', '17:15', 1120),
(5107, '2026-08-31', '17:00', '17:30', 1122),
(5108, '2026-09-01', '17:00', '17:15', 1125),
(5109, '2026-09-04', '17:00', '17:45', 1125),
(5110, '2026-09-07', '17:00', '17:30', 1129),
(5111, '2026-09-08', '17:00', '17:20', 1129),
(5112, '2026-09-09', '17:00', '17:10', 1129),
(5113, '2026-09-08', '17:00', '17:10', 1130),
(5114, '2026-09-08', '17:00', '17:15', 1131),
(5115, '2026-09-09', '17:00', '17:30', 1131),
(5116, '2026-09-10', '17:00', '17:15', 1131),
(5117, '2026-09-10', '17:00', '17:30', 1133),
(5118, '2026-09-11', '17:00', '17:15', 1133),
(5119, '2026-09-10', '17:00', '17:15', 1134),
(5120, '2026-09-11', '17:00', '17:30', 1134),
(5121, '2026-09-11', '17:00', '17:20', 1136),
(5122, '2026-09-14', '17:00', '17:20', 1137),
(5123, '2026-09-17', '17:00', '17:10', 1137),
(5124, '2026-09-14', '17:00', '17:20', 1139),
(5125, '2026-09-15', '17:00', '17:25', 1139),
(5126, '2026-09-16', '17:00', '17:15', 1142),
(5127, '2026-09-17', '17:00', '17:10', 1142),
(5128, '2026-09-16', '17:00', '17:10', 1143),
(5129, '2026-09-17', '17:00', '17:10', 1145),
(5130, '2026-09-18', '17:00', '17:30', 1147),
(5131, '2026-09-21', '17:00', '17:10', 1147);
INSERT INTO compensacion (id_compensacion, fecha_compensacion, hora_inicio, hora_fin, id_permiso) VALUES
(5132, '2026-09-21', '17:00', '17:45', 1148),
(5133, '2026-09-22', '17:00', '17:20', 1151),
(5134, '2026-09-22', '17:00', '17:30', 1153),
(5135, '2026-09-24', '17:00', '17:20', 1155),
(5136, '2026-09-25', '17:00', '17:30', 1155),
(5137, '2026-09-28', '17:00', '17:10', 1155),
(5138, '2026-09-24', '17:00', '17:20', 1157),
(5139, '2026-09-25', '17:00', '17:30', 1159),
(5140, '2026-09-28', '17:00', '17:15', 1159),
(5141, '2026-10-01', '17:00', '17:15', 1159),
(5142, '2026-09-25', '17:00', '17:30', 1160),
(5143, '2026-09-28', '17:00', '17:15', 1160),
(5144, '2026-10-01', '17:00', '17:15', 1160),
(5145, '2026-09-25', '17:00', '17:20', 1161),
(5146, '2026-09-28', '17:00', '17:25', 1161),
(5147, '2026-09-28', '17:00', '17:20', 1162),
(5148, '2026-09-29', '17:00', '17:20', 1162),
(5149, '2026-10-02', '17:00', '17:20', 1162),
(5150, '2026-09-28', '17:00', '17:15', 1163),
(5151, '2026-09-29', '17:00', '17:30', 1164),
(5152, '2026-09-30', '17:00', '17:15', 1164),
(5153, '2026-09-30', '17:00', '17:25', 1165),
(5154, '2026-10-01', '17:00', '17:10', 1168),
(5155, '2026-10-05', '17:00', '17:45', 1171),
(5156, '2026-10-05', '17:00', '17:30', 1172),
(5157, '2026-10-06', '17:00', '17:25', 1175),
(5158, '2026-10-06', '17:00', '17:25', 1176),
(5159, '2026-10-07', '17:00', '17:15', 1177),
(5160, '2026-10-12', '17:00', '17:30', 1177),
(5161, '2026-10-07', '17:00', '17:15', 1178),
(5162, '2026-10-07', '17:00', '17:30', 1180),
(5163, '2026-10-08', '17:00', '17:30', 1180),
(5164, '2026-10-08', '17:00', '17:15', 1181),
(5165, '2026-10-08', '17:00', '17:40', 1182),
(5166, '2026-10-08', '17:00', '17:25', 1183),
(5167, '2026-10-08', '17:00', '17:20', 1184),
(5168, '2026-10-09', '17:00', '17:25', 1185),
(5169, '2026-10-09', '17:00', '17:10', 1186),
(5170, '2026-10-09', '17:00', '18:00', 1187),
(5171, '2026-10-12', '17:00', '17:15', 1189),
(5172, '2026-10-14', '17:00', '17:30', 1189),
(5173, '2026-10-13', '17:00', '17:25', 1190),
(5174, '2026-10-13', '17:00', '17:20', 1192),
(5175, '2026-10-14', '17:00', '17:30', 1192),
(5176, '2026-10-15', '17:00', '17:10', 1192),
(5177, '2026-10-13', '17:00', '17:45', 1193),
(5178, '2026-10-16', '17:00', '17:15', 1193),
(5179, '2026-10-14', '17:00', '17:30', 1197),
(5180, '2026-10-19', '17:00', '17:15', 1197),
(5181, '2026-10-15', '17:00', '17:30', 1198),
(5182, '2026-10-15', '17:00', '17:30', 1199),
(5183, '2026-10-15', '17:00', '17:20', 1200),
(5184, '2026-10-19', '17:00', '17:25', 1200),
(5185, '2026-10-16', '17:00', '17:15', 1201),
(5186, '2026-10-19', '17:00', '17:15', 1201),
(5187, '2026-10-20', '17:00', '17:30', 1201),
(5188, '2026-10-16', '17:00', '17:40', 1202),
(5189, '2026-10-16', '17:00', '17:10', 1203),
(5190, '2026-10-19', '17:00', '17:15', 1204),
(5191, '2026-10-20', '17:00', '17:30', 1204);
INSERT INTO compensacion (id_compensacion, fecha_compensacion, hora_inicio, hora_fin, id_permiso) VALUES
(5192, '2026-10-19', '17:00', '17:25', 1205),
(5193, '2026-10-19', '17:00', '17:15', 1206),
(5194, '2026-10-21', '17:00', '17:05', 1206),
(5195, '2026-10-20', '17:00', '17:45', 1208),
(5196, '2026-10-21', '17:00', '17:30', 1209),
(5197, '2026-10-21', '17:00', '17:30', 1210),
(5198, '2026-10-22', '17:00', '17:40', 1212),
(5199, '2026-10-23', '17:00', '17:30', 1214),
(5200, '2026-10-26', '17:00', '17:15', 1214),
(5201, '2026-10-28', '17:00', '17:15', 1214),
(5202, '2026-10-23', '17:00', '17:45', 1215),
(5203, '2026-10-26', '17:00', '17:15', 1215),
(5204, '2026-10-27', '17:00', '17:15', 1217),
(5205, '2026-10-27', '17:00', '17:15', 1218),
(5206, '2026-10-28', '17:00', '17:30', 1220),
(5207, '2026-10-29', '17:00', '17:30', 1220),
(5208, '2026-10-28', '17:00', '17:30', 1221),
(5209, '2026-10-29', '17:00', '17:30', 1222),
(5210, '2026-10-29', '17:00', '17:20', 1224),
(5211, '2026-11-02', '17:00', '17:25', 1224),
(5212, '2026-11-02', '17:00', '17:30', 1226),
(5213, '2026-11-03', '17:00', '17:30', 1226),
(5214, '2026-11-02', '17:00', '17:15', 1227),
(5215, '2026-11-05', '17:00', '17:45', 1227),
(5216, '2026-11-03', '17:00', '17:15', 1229),
(5217, '2026-11-05', '17:00', '17:15', 1233),
(5218, '2026-11-06', '17:00', '17:30', 1233),
(5219, '2026-11-05', '17:00', '18:00', 1234),
(5220, '2026-11-06', '17:00', '17:25', 1236),
(5221, '2026-11-06', '17:00', '17:15', 1237),
(5222, '2026-11-06', '17:00', '17:20', 1238),
(5223, '2026-11-09', '17:00', '17:15', 1238),
(5224, '2026-11-10', '17:00', '17:10', 1238),
(5225, '2026-11-09', '17:00', '17:15', 1239),
(5226, '2026-11-10', '17:00', '17:05', 1239),
(5227, '2026-11-09', '17:00', '17:10', 1240),
(5228, '2026-11-09', '17:00', '17:30', 1241),
(5229, '2026-11-10', '17:00', '17:15', 1241),
(5230, '2026-11-13', '17:00', '17:15', 1241),
(5231, '2026-11-10', '17:00', '17:15', 1242),
(5232, '2026-11-11', '17:00', '17:15', 1242),
(5233, '2026-11-10', '17:00', '17:15', 1243),
(5234, '2026-11-11', '17:00', '17:15', 1243),
(5235, '2026-11-11', '17:00', '17:10', 1245),
(5236, '2026-11-12', '17:00', '17:15', 1247),
(5237, '2026-11-13', '17:00', '17:15', 1247),
(5238, '2026-11-16', '17:00', '17:15', 1247),
(5239, '2026-11-16', '17:00', '17:45', 1252),
(5240, '2026-11-17', '17:00', '17:15', 1253),
(5241, '2026-11-17', '17:00', '17:10', 1255);

INSERT INTO firma_compensacion (id_compensacion, firmante) VALUES
(5012, 'Colaborador'),
(5012, 'Administrador'),
(5013, 'Colaborador'),
(5013, 'Administrador'),
(5014, 'Colaborador'),
(5014, 'Administrador'),
(5015, 'Colaborador'),
(5015, 'Administrador'),
(5016, 'Colaborador'),
(5016, 'Administrador'),
(5017, 'Colaborador'),
(5017, 'Administrador'),
(5018, 'Colaborador'),
(5018, 'Administrador'),
(5019, 'Colaborador'),
(5019, 'Administrador'),
(5020, 'Colaborador'),
(5020, 'Administrador'),
(5021, 'Colaborador'),
(5021, 'Administrador'),
(5022, 'Colaborador'),
(5022, 'Administrador'),
(5023, 'Colaborador'),
(5023, 'Administrador'),
(5024, 'Colaborador'),
(5024, 'Administrador'),
(5025, 'Colaborador'),
(5025, 'Administrador'),
(5026, 'Colaborador'),
(5026, 'Administrador'),
(5027, 'Colaborador'),
(5027, 'Administrador'),
(5028, 'Colaborador'),
(5028, 'Administrador'),
(5029, 'Colaborador'),
(5029, 'Administrador'),
(5030, 'Colaborador'),
(5030, 'Administrador'),
(5031, 'Colaborador'),
(5031, 'Administrador'),
(5032, 'Colaborador'),
(5032, 'Administrador'),
(5033, 'Colaborador'),
(5033, 'Administrador'),
(5034, 'Colaborador'),
(5034, 'Administrador'),
(5035, 'Colaborador'),
(5035, 'Administrador'),
(5036, 'Colaborador'),
(5036, 'Administrador'),
(5037, 'Colaborador'),
(5037, 'Administrador'),
(5038, 'Colaborador'),
(5038, 'Administrador'),
(5039, 'Colaborador'),
(5039, 'Administrador'),
(5040, 'Colaborador'),
(5040, 'Administrador'),
(5041, 'Colaborador'),
(5041, 'Administrador'),
(5042, 'Colaborador'),
(5042, 'Administrador'),
(5043, 'Colaborador'),
(5043, 'Administrador'),
(5044, 'Colaborador'),
(5044, 'Administrador'),
(5045, 'Colaborador'),
(5045, 'Administrador'),
(5046, 'Colaborador'),
(5046, 'Administrador'),
(5047, 'Colaborador'),
(5047, 'Administrador'),
(5048, 'Colaborador'),
(5048, 'Administrador'),
(5049, 'Colaborador'),
(5049, 'Administrador'),
(5050, 'Colaborador'),
(5050, 'Administrador'),
(5051, 'Colaborador'),
(5051, 'Administrador');
INSERT INTO firma_compensacion (id_compensacion, firmante) VALUES
(5052, 'Colaborador'),
(5052, 'Administrador'),
(5053, 'Colaborador'),
(5053, 'Administrador'),
(5054, 'Colaborador'),
(5054, 'Administrador'),
(5055, 'Colaborador'),
(5055, 'Administrador'),
(5056, 'Colaborador'),
(5056, 'Administrador'),
(5057, 'Colaborador'),
(5057, 'Administrador'),
(5058, 'Colaborador'),
(5058, 'Administrador'),
(5059, 'Colaborador'),
(5059, 'Administrador'),
(5060, 'Colaborador'),
(5060, 'Administrador'),
(5061, 'Colaborador'),
(5061, 'Administrador'),
(5062, 'Colaborador'),
(5062, 'Administrador'),
(5063, 'Colaborador'),
(5063, 'Administrador'),
(5064, 'Colaborador'),
(5064, 'Administrador'),
(5065, 'Colaborador'),
(5065, 'Administrador'),
(5066, 'Colaborador'),
(5066, 'Administrador'),
(5067, 'Colaborador'),
(5067, 'Administrador'),
(5068, 'Colaborador'),
(5068, 'Administrador'),
(5069, 'Colaborador'),
(5069, 'Administrador'),
(5070, 'Colaborador'),
(5070, 'Administrador'),
(5071, 'Colaborador'),
(5071, 'Administrador'),
(5072, 'Colaborador'),
(5072, 'Administrador'),
(5073, 'Colaborador'),
(5073, 'Administrador'),
(5074, 'Colaborador'),
(5074, 'Administrador'),
(5075, 'Colaborador'),
(5075, 'Administrador'),
(5076, 'Colaborador'),
(5076, 'Administrador'),
(5077, 'Colaborador'),
(5077, 'Administrador'),
(5078, 'Colaborador'),
(5078, 'Administrador'),
(5079, 'Colaborador'),
(5079, 'Administrador'),
(5080, 'Colaborador'),
(5080, 'Administrador'),
(5081, 'Colaborador'),
(5081, 'Administrador'),
(5082, 'Colaborador'),
(5082, 'Administrador'),
(5083, 'Colaborador'),
(5083, 'Administrador'),
(5084, 'Colaborador'),
(5084, 'Administrador'),
(5085, 'Colaborador'),
(5085, 'Administrador'),
(5086, 'Colaborador'),
(5086, 'Administrador'),
(5087, 'Colaborador'),
(5087, 'Administrador'),
(5088, 'Colaborador'),
(5088, 'Administrador'),
(5089, 'Colaborador'),
(5089, 'Administrador'),
(5090, 'Colaborador'),
(5090, 'Administrador'),
(5091, 'Colaborador'),
(5091, 'Administrador');
INSERT INTO firma_compensacion (id_compensacion, firmante) VALUES
(5092, 'Colaborador'),
(5092, 'Administrador'),
(5093, 'Colaborador'),
(5093, 'Administrador'),
(5094, 'Colaborador'),
(5094, 'Administrador'),
(5095, 'Colaborador'),
(5095, 'Administrador'),
(5096, 'Colaborador'),
(5096, 'Administrador'),
(5097, 'Colaborador'),
(5097, 'Administrador'),
(5098, 'Colaborador'),
(5098, 'Administrador'),
(5099, 'Colaborador'),
(5099, 'Administrador'),
(5100, 'Colaborador'),
(5100, 'Administrador'),
(5101, 'Colaborador'),
(5101, 'Administrador'),
(5102, 'Colaborador'),
(5102, 'Administrador'),
(5103, 'Colaborador'),
(5103, 'Administrador'),
(5104, 'Colaborador'),
(5104, 'Administrador'),
(5105, 'Colaborador'),
(5105, 'Administrador'),
(5106, 'Colaborador'),
(5106, 'Administrador'),
(5107, 'Colaborador'),
(5107, 'Administrador'),
(5108, 'Colaborador'),
(5108, 'Administrador'),
(5109, 'Colaborador'),
(5109, 'Administrador'),
(5110, 'Colaborador'),
(5110, 'Administrador'),
(5111, 'Colaborador'),
(5111, 'Administrador'),
(5112, 'Colaborador'),
(5112, 'Administrador'),
(5113, 'Colaborador'),
(5113, 'Administrador'),
(5114, 'Colaborador'),
(5114, 'Administrador'),
(5115, 'Colaborador'),
(5115, 'Administrador'),
(5116, 'Colaborador'),
(5116, 'Administrador'),
(5117, 'Colaborador'),
(5117, 'Administrador'),
(5118, 'Colaborador'),
(5118, 'Administrador'),
(5119, 'Colaborador'),
(5119, 'Administrador'),
(5120, 'Colaborador'),
(5120, 'Administrador'),
(5121, 'Colaborador'),
(5121, 'Administrador'),
(5122, 'Colaborador'),
(5122, 'Administrador'),
(5123, 'Colaborador'),
(5123, 'Administrador'),
(5124, 'Colaborador'),
(5124, 'Administrador'),
(5125, 'Colaborador'),
(5125, 'Administrador'),
(5126, 'Colaborador'),
(5126, 'Administrador'),
(5127, 'Colaborador'),
(5127, 'Administrador'),
(5128, 'Colaborador'),
(5128, 'Administrador'),
(5129, 'Colaborador'),
(5129, 'Administrador'),
(5130, 'Colaborador'),
(5130, 'Administrador'),
(5131, 'Colaborador'),
(5131, 'Administrador');
INSERT INTO firma_compensacion (id_compensacion, firmante) VALUES
(5132, 'Colaborador'),
(5132, 'Administrador'),
(5133, 'Colaborador'),
(5133, 'Administrador'),
(5134, 'Colaborador'),
(5134, 'Administrador'),
(5135, 'Colaborador'),
(5135, 'Administrador'),
(5136, 'Colaborador'),
(5136, 'Administrador'),
(5137, 'Colaborador'),
(5137, 'Administrador'),
(5138, 'Colaborador'),
(5138, 'Administrador'),
(5139, 'Colaborador'),
(5139, 'Administrador'),
(5140, 'Colaborador'),
(5140, 'Administrador'),
(5141, 'Colaborador'),
(5141, 'Administrador'),
(5142, 'Colaborador'),
(5142, 'Administrador'),
(5143, 'Colaborador'),
(5143, 'Administrador'),
(5144, 'Colaborador'),
(5144, 'Administrador'),
(5145, 'Colaborador'),
(5145, 'Administrador'),
(5146, 'Colaborador'),
(5146, 'Administrador'),
(5147, 'Colaborador'),
(5147, 'Administrador'),
(5148, 'Colaborador'),
(5148, 'Administrador'),
(5149, 'Colaborador'),
(5149, 'Administrador'),
(5150, 'Colaborador'),
(5150, 'Administrador'),
(5151, 'Colaborador'),
(5151, 'Administrador'),
(5152, 'Colaborador'),
(5152, 'Administrador'),
(5153, 'Colaborador'),
(5153, 'Administrador'),
(5154, 'Colaborador'),
(5154, 'Administrador'),
(5155, 'Colaborador'),
(5155, 'Administrador'),
(5156, 'Colaborador'),
(5156, 'Administrador'),
(5157, 'Colaborador'),
(5157, 'Administrador'),
(5158, 'Colaborador'),
(5158, 'Administrador'),
(5159, 'Colaborador'),
(5159, 'Administrador'),
(5160, 'Colaborador'),
(5160, 'Administrador'),
(5161, 'Colaborador'),
(5161, 'Administrador'),
(5162, 'Colaborador'),
(5162, 'Administrador'),
(5163, 'Colaborador'),
(5163, 'Administrador'),
(5164, 'Colaborador'),
(5164, 'Administrador'),
(5165, 'Colaborador'),
(5165, 'Administrador'),
(5166, 'Colaborador'),
(5166, 'Administrador'),
(5167, 'Colaborador'),
(5167, 'Administrador'),
(5168, 'Colaborador'),
(5168, 'Administrador'),
(5169, 'Colaborador'),
(5169, 'Administrador'),
(5170, 'Colaborador'),
(5170, 'Administrador'),
(5171, 'Colaborador'),
(5171, 'Administrador');
INSERT INTO firma_compensacion (id_compensacion, firmante) VALUES
(5172, 'Colaborador'),
(5172, 'Administrador'),
(5173, 'Colaborador'),
(5173, 'Administrador'),
(5174, 'Colaborador'),
(5174, 'Administrador'),
(5175, 'Colaborador'),
(5175, 'Administrador'),
(5176, 'Colaborador'),
(5176, 'Administrador'),
(5177, 'Colaborador'),
(5177, 'Administrador'),
(5178, 'Colaborador'),
(5178, 'Administrador'),
(5179, 'Colaborador'),
(5179, 'Administrador'),
(5180, 'Colaborador'),
(5180, 'Administrador'),
(5181, 'Colaborador'),
(5181, 'Administrador'),
(5182, 'Colaborador'),
(5182, 'Administrador'),
(5183, 'Colaborador'),
(5183, 'Administrador'),
(5184, 'Colaborador'),
(5184, 'Administrador'),
(5185, 'Colaborador'),
(5185, 'Administrador'),
(5186, 'Colaborador'),
(5186, 'Administrador'),
(5187, 'Colaborador'),
(5187, 'Administrador'),
(5188, 'Colaborador'),
(5188, 'Administrador'),
(5189, 'Colaborador'),
(5189, 'Administrador'),
(5190, 'Colaborador'),
(5190, 'Administrador'),
(5191, 'Colaborador'),
(5191, 'Administrador'),
(5192, 'Colaborador'),
(5192, 'Administrador'),
(5193, 'Colaborador'),
(5193, 'Administrador'),
(5194, 'Colaborador'),
(5194, 'Administrador'),
(5195, 'Colaborador'),
(5195, 'Administrador'),
(5196, 'Colaborador'),
(5196, 'Administrador'),
(5197, 'Colaborador'),
(5197, 'Administrador'),
(5198, 'Colaborador'),
(5198, 'Administrador'),
(5199, 'Colaborador'),
(5199, 'Administrador'),
(5200, 'Colaborador'),
(5200, 'Administrador'),
(5201, 'Colaborador'),
(5201, 'Administrador'),
(5202, 'Colaborador'),
(5202, 'Administrador'),
(5203, 'Colaborador'),
(5203, 'Administrador'),
(5204, 'Colaborador'),
(5204, 'Administrador'),
(5205, 'Colaborador'),
(5205, 'Administrador'),
(5206, 'Colaborador'),
(5206, 'Administrador'),
(5207, 'Colaborador'),
(5207, 'Administrador'),
(5208, 'Colaborador'),
(5208, 'Administrador'),
(5209, 'Colaborador'),
(5209, 'Administrador'),
(5210, 'Colaborador'),
(5210, 'Administrador'),
(5211, 'Colaborador'),
(5211, 'Administrador');
INSERT INTO firma_compensacion (id_compensacion, firmante) VALUES
(5212, 'Colaborador'),
(5212, 'Administrador'),
(5213, 'Colaborador'),
(5213, 'Administrador'),
(5214, 'Colaborador'),
(5214, 'Administrador'),
(5215, 'Colaborador'),
(5215, 'Administrador'),
(5216, 'Colaborador'),
(5216, 'Administrador'),
(5217, 'Colaborador'),
(5217, 'Administrador'),
(5218, 'Colaborador'),
(5218, 'Administrador'),
(5219, 'Colaborador'),
(5219, 'Administrador'),
(5220, 'Colaborador'),
(5220, 'Administrador'),
(5221, 'Colaborador'),
(5221, 'Administrador'),
(5222, 'Colaborador'),
(5222, 'Administrador'),
(5223, 'Colaborador'),
(5223, 'Administrador'),
(5224, 'Colaborador'),
(5224, 'Administrador'),
(5225, 'Colaborador'),
(5225, 'Administrador'),
(5226, 'Colaborador'),
(5226, 'Administrador'),
(5227, 'Colaborador'),
(5227, 'Administrador'),
(5228, 'Colaborador'),
(5228, 'Administrador'),
(5229, 'Colaborador'),
(5229, 'Administrador'),
(5230, 'Colaborador'),
(5230, 'Administrador'),
(5231, 'Colaborador'),
(5231, 'Administrador'),
(5232, 'Colaborador'),
(5232, 'Administrador'),
(5233, 'Colaborador'),
(5233, 'Administrador'),
(5234, 'Colaborador'),
(5234, 'Administrador'),
(5235, 'Colaborador'),
(5235, 'Administrador'),
(5236, 'Colaborador'),
(5236, 'Administrador'),
(5237, 'Colaborador'),
(5237, 'Administrador'),
(5238, 'Colaborador'),
(5239, 'Colaborador'),
(5240, 'Colaborador'),
(5241, 'Colaborador'),
(5241, 'Administrador');

-- Parte C ------------------------------------------------------------
-- Bajas lógicas de ejemplo (el disparador registra la fecha y la bitácora).
UPDATE empleado SET activo = 0 WHERE dni = '47994000';
UPDATE empleado SET activo = 0 WHERE dni = '73723261';
UPDATE solicitud_permiso SET activo = 0 WHERE id_permiso = 1256;
UPDATE solicitud_permiso SET activo = 0 WHERE id_permiso = 1257;
UPDATE solicitud_permiso SET activo = 0 WHERE id_permiso = 1258;

-- >>>>>>>>>>>>>>>>>>>> 04_usuario_aplicativo.sql >>>>>>>>>>>>>>>>>>>>
-- =====================================================================
-- Script 4 (Entrega 5): usuario del aplicativo.
-- El aplicativo se conecta con un usuario que SOLO puede ejecutar los
-- procedimientos almacenados: no tiene SELECT, INSERT, UPDATE ni DELETE
-- directos sobre las tablas. Cambie la contraseña antes de usarlo.
-- =====================================================================
DROP USER IF EXISTS 'permisos_app'@'%';
-- mysql_native_password: el driver PyMySQL no necesita el paquete 'cryptography'.
-- (Válido en MySQL 8.0; en MySQL 8.4+ instale cryptography y use el método por defecto.)
CREATE USER 'permisos_app'@'%' IDENTIFIED WITH mysql_native_password BY 'Cambiar_Esta_Clave_2026';
GRANT EXECUTE ON permisos_hora.* TO 'permisos_app'@'%';
FLUSH PRIVILEGES;
