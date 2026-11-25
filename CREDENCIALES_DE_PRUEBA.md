# Credenciales de prueba

| Uso | Usuario | Contraseña | Dónde se configura |
|---|---|---|---|
| Conexión del aplicativo a MySQL | `permisos_app` | `Cambiar_Esta_Clave_2026` | `db/04_usuario_aplicativo.sql` y `backend/.env` |
| Administración de MySQL | `root` (o el administrador de su instalación) | La de su instalación de MySQL | Solo para ejecutar los scripts |

- El usuario `permisos_app` **solo tiene permiso EXECUTE**: puede ejecutar los procedimientos almacenados, pero no leer ni modificar las tablas directamente.
- El aplicativo no tiene inicio de sesión: se abre en http://127.0.0.1:8080 después de ejecutar `iniciar.bat`.
- Datos de prueba para usar en el aplicativo:
  - Empleada con topes ya usados en agosto de 2026: **Milagros Cáceres** (DNI `72123249`). Registrar otra solicitud Urgente en la semana del 17/08/2026 o una tercera Personal en agosto muestra el rechazo por tope.
  - Empleado con solicitud pendiente (no se puede dar de baja): **Julián Rivas Rodríguez** (DNI `74839201`).
  - Compensación pendiente de firma del administrador: bloque **5011** (permiso 1012).

> Son credenciales de prueba. Cambie la contraseña de `permisos_app` antes de usar el aplicativo en un servidor real.
