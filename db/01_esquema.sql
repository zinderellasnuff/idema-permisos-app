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
