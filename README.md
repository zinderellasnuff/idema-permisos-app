# IDEMA · Registro de permisos por hora

Aplicativo cliente de la base de datos **idema_permisos** (MySQL 8.0) para el proceso de permisos por hora del Instituto Superior Tecnológico Particular Santiago Ramón y Cajal – IDEMA. Proyecto del curso Gestión de Datos e Información, Entrega 5 (Universidad Católica de Santa María).

**Integrantes:** Chipana Flores, Alexander Tomas · Gonzales Palacios, Noelia Patricia · Guzmán Flores, Aron Daniel · Kana Zambrano, Luz Clarita · Ramírez Garay, Jesús Esteban.

## Arquitectura

```
Navegador (React)  --HTTP/JSON-->  backend/server.py (Python, http.server)  --CALL sp_...-->  MySQL 8.0
```

- **Sin frameworks de acceso a datos.** El backend usa solo la biblioteca estándar de Python (`http.server`) y el driver `PyMySQL`. No hay ORM ni modelos: toda operación es un `CALL` a un procedimiento almacenado.
- **El usuario `idema_app` solo tiene `EXECUTE`**: no puede leer ni modificar las tablas directamente.
- **Reglas en la base de datos:** 13 disparadores (topes de uso, bloqueo del borrado físico, transiciones de estado, reglas de compensación y bitácora de auditoría) y 30 procedimientos (CRUD, resolución y 10 reportes con JOIN).
- **Borrado lógico:** empleados (baja/reactivación) y solicitudes (anulación). El borrado físico está bloqueado por disparador.

## Estructura

| Carpeta | Contenido |
|---|---|
| `db/` | `01_esquema.sql` (tablas, índices, disparadores), `02_procedimientos.sql`, `03_datos.sql` (datos ampliados), `04_usuario_aplicativo.sql`, `generar_datos.py` |
| `backend/` | `server.py` (API REST y servidor de la interfaz), `db.py` (llamadas a procedimientos) |
| `frontend/` | Interfaz React (Vite) y la prueba de punta a punta `e2e/prueba_e2e.mjs` |
| `docs/` | Capturas del aplicativo |

## Instalación

1. **Base de datos** (MySQL 8.0), en este orden:
   ```bash
   mysql -u root -p < db/01_esquema.sql
   mysql -u root -p < db/02_procedimientos.sql
   mysql -u root -p < db/03_datos.sql
   mysql -u root -p < db/04_usuario_aplicativo.sql   # cambie la contraseña antes
   ```
2. **Aplicativo:** descargue el ejecutable de la sección *Releases* (incluye la interfaz compilada) o compílela con `cd frontend && npm install && npm run build`.
3. Copie `backend/.env.example` como `backend/.env`, ajuste los datos de conexión y ejecute `iniciar.bat` (Windows) o `./iniciar.sh` (Linux/macOS). Abra http://127.0.0.1:8080.

Requisitos: Python 3.10+ y MySQL 8.0. Node.js 18+ solo para compilar la interfaz.

## Módulos

- **Panel:** indicadores y pendientes por área.
- **Empleados:** registro, búsqueda, edición, baja y reactivación.
- **Solicitudes:** registro, edición (solo pendientes), aprobación o rechazo, anulación y compensación de horas con firmas.
- **Reportes:** 10 reportes con JOIN y exportación a CSV.
- **Bitácora:** auditoría generada por los disparadores.

## Prueba

Con el servidor en marcha: `cd frontend && node e2e/prueba_e2e.mjs http://127.0.0.1:8080 ../docs/capturas`. Recorre todos los módulos y verifica el alta, el rechazo por tope, la aprobación, la compensación, la baja lógica, los reportes y la bitácora.
