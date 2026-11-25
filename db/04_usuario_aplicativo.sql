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
