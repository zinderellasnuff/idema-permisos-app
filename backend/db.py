"""Acceso a la base de datos IDEMA.

Toda operación se hace con CALL a un procedimiento almacenado: el backend no
contiene sentencias SELECT, INSERT, UPDATE ni DELETE sobre las tablas. Se usa
el driver PyMySQL de forma nativa (sin ORM ni framework).
"""
import os
import pymysql

# Códigos de error de MySQL que se traducen a mensajes para el usuario.
ERRORES_NEGOCIO = {
    1644: None,   # SIGNAL de un disparador o procedimiento: se usa su propio mensaje
    3819: "Los datos no cumplen una restricción de la base de datos (CHECK)",
    1062: "Ya existe un registro con esos datos (valor duplicado)",
    1452: "El registro relacionado no existe (clave foránea)",
    1451: "No se puede eliminar: hay registros que dependen de este",
    1265: "Valor no válido para el campo",
    1366: "Valor no válido para el campo",
    1292: "Fecha u hora con formato no válido",
}


class ErrorNegocio(Exception):
    """Error esperado (regla de negocio o validación) que se muestra al usuario."""


def conectar():
    return pymysql.connect(
        host=os.environ.get("IDEMA_DB_HOST", "127.0.0.1"),
        port=int(os.environ.get("IDEMA_DB_PORT", "3306")),
        user=os.environ.get("IDEMA_DB_USER", "idema_app"),
        password=os.environ.get("IDEMA_DB_PASSWORD", ""),
        database=os.environ.get("IDEMA_DB_NAME", "idema_permisos"),
        charset="utf8mb4",
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=5,
    )


def _limpiar(fila):
    """Convierte tipos de MySQL (Decimal, timedelta, date) a valores JSON."""
    salida = {}
    for clave, valor in fila.items():
        if valor is None or isinstance(valor, (str, int, float, bool)):
            salida[clave] = valor
        elif hasattr(valor, "total_seconds"):  # TIME llega como timedelta
            seg = int(valor.total_seconds())
            salida[clave] = f"{seg // 3600:02d}:{seg % 3600 // 60:02d}"
        elif hasattr(valor, "isoformat"):
            salida[clave] = valor.isoformat()
        else:  # Decimal
            salida[clave] = float(valor)
    return salida


def llamar(procedimiento, *parametros):
    """Ejecuta CALL procedimiento(parametros) y devuelve el primer conjunto de filas."""
    marcadores = ", ".join(["%s"] * len(parametros))
    conexion = conectar()
    try:
        with conexion.cursor() as cursor:
            cursor.execute(f"CALL {procedimiento}({marcadores})", parametros)
            filas = [_limpiar(f) for f in cursor.fetchall()]
            while cursor.nextset():  # consume los resultados restantes del CALL
                pass
            return filas
    except pymysql.MySQLError as error:
        codigo = error.args[0] if error.args else None
        if codigo in ERRORES_NEGOCIO:
            raise ErrorNegocio(ERRORES_NEGOCIO[codigo] or error.args[1]) from error
        raise
    finally:
        conexion.close()
