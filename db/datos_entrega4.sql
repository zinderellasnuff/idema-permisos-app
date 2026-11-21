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
