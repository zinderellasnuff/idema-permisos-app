"""Servidor del aplicativo Sistema de permisos - Permisos por hora.

Backend nativo en Python: usa solo la biblioteca estándar (http.server) para
la API REST y el driver PyMySQL para llamar a los procedimientos almacenados.
También sirve la interfaz React compilada (carpeta frontend/dist).

Uso:  python server.py            (lee la configuración de .env)
"""
import json
import mimetypes
import os
import re
import sys
from datetime import date
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

BASE = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))


def cargar_env(ruta):
    """Lee un archivo .env sencillo (CLAVE=valor) sin dependencias externas."""
    if ruta.exists():
        for linea in ruta.read_text(encoding="utf-8").splitlines():
            linea = linea.strip()
            if linea and not linea.startswith("#") and "=" in linea:
                clave, valor = linea.split("=", 1)
                os.environ.setdefault(clave.strip(), valor.strip())


cargar_env(Path.cwd() / ".env")
cargar_env(Path(__file__).resolve().parent / ".env")

from db import ErrorNegocio, llamar  # noqa: E402  (después de cargar .env)

ESTATICOS = Path(os.environ.get("PERMISOS_STATIC_DIR", BASE / "static"))
if not ESTATICOS.exists():
    ESTATICOS = BASE.parent / "frontend" / "dist"


# ---------------------------------------------------------------------------
# Validación de entradas (frontera de confianza: todo llega del navegador)
# ---------------------------------------------------------------------------
class EntradaInvalida(Exception):
    pass


def texto(datos, campo, maximo, obligatorio=True):
    valor = datos.get(campo) or ""
    if not isinstance(valor, str):
        raise EntradaInvalida(f"El campo {campo} debe ser texto")
    valor = valor.strip()
    if obligatorio and not valor:
        raise EntradaInvalida(f"El campo {campo} es obligatorio")
    if len(valor) > maximo:
        raise EntradaInvalida(f"El campo {campo} admite como máximo {maximo} caracteres")
    return valor or None


def dni(valor):
    if not isinstance(valor, str) or not re.fullmatch(r"[0-9]{8}", valor):
        raise EntradaInvalida("El DNI debe tener exactamente 8 dígitos")
    return valor


def nombre(datos, campo):
    valor = " ".join(texto(datos, campo, 50).split())
    if not re.fullmatch(r"[^\W\d_]+(?:[ '.\-]+[^\W\d_]+)*\.?", valor):
        raise EntradaInvalida(f"El campo {campo} solo admite letras, espacios, guion o apóstrofo")
    return valor


def fecha(valor, campo="fecha", obligatorio=True):
    if not valor:
        if obligatorio:
            raise EntradaInvalida(f"El campo {campo} es obligatorio")
        return None
    try:
        if len(valor) != 10:  # fromisoformat también acepta otros formatos, como 2026W471
            raise ValueError
        return date.fromisoformat(valor).isoformat()
    except (TypeError, ValueError):
        raise EntradaInvalida(f"El campo {campo} debe tener el formato AAAA-MM-DD") from None


def hora(valor, campo="hora", obligatorio=True):
    if not valor:
        if obligatorio:
            raise EntradaInvalida(f"El campo {campo} es obligatorio")
        return None
    if not re.fullmatch(r"([01][0-9]|2[0-3]):[0-5][0-9]", str(valor)):
        raise EntradaInvalida(f"El campo {campo} debe tener el formato HH:MM")
    return valor


def entero(valor, campo, minimo, maximo):
    try:
        if isinstance(valor, (bool, float)):  # 30.9 no debe convertirse en 30
            raise ValueError
        numero = int(valor)
    except (TypeError, ValueError):
        raise EntradaInvalida(f"El campo {campo} debe ser un número entero") from None
    if not minimo <= numero <= maximo:
        raise EntradaInvalida(f"El campo {campo} debe estar entre {minimo} y {maximo}")
    return numero


def opcion(valor, campo, opciones):
    if not isinstance(valor, str) or valor not in opciones:
        raise EntradaInvalida(f"El campo {campo} debe ser uno de: {', '.join(opciones)}")
    return valor


# ---------------------------------------------------------------------------
# Catálogo de reportes: cada uno llama a un procedimiento sp_rep_XX
# ---------------------------------------------------------------------------
REPORTES = [
    {"id": 1, "proc": "sp_rep_01_permisos_por_empleado", "nombre": "Permisos por empleado",
     "descripcion": "Solicitudes por subtipo y estado, y minutos aprobados de cada empleado en un período.",
     "params": [("desde", "fecha"), ("hasta", "fecha")], "tecnica": "JOIN, GROUP BY, SUM condicional"},
    {"id": 2, "proc": "sp_rep_02_tope_semanal", "nombre": "Tope semanal de tolerancia",
     "descripcion": "Para la semana de la fecha indicada, quién puede registrar una solicitud Urgente.",
     "params": [("fecha", "fecha")], "tecnica": "LEFT JOIN, COUNT, IF"},
    {"id": 3, "proc": "sp_rep_03_tope_mensual", "nombre": "Tope mensual de permisos personales",
     "descripcion": "Permisos personales usados y disponibles por empleado en el mes de la fecha.",
     "params": [("fecha", "fecha")], "tecnica": "LEFT JOIN, COUNT, LAST_DAY"},
    {"id": 4, "proc": "sp_rep_04_pendientes_por_area", "nombre": "Pendientes por área",
     "descripcion": "Bandeja de aprobación: solicitudes pendientes agrupadas por área.",
     "params": [], "tecnica": "JOIN, GROUP BY, GROUP_CONCAT"},
    {"id": 5, "proc": "sp_rep_05_compensaciones_firmas", "nombre": "Compensaciones con firmas",
     "descripcion": "Bloques de compensación del período, su duración y el estado de las firmas.",
     "params": [("desde", "fecha"), ("hasta", "fecha")], "tecnica": "JOIN de 3 tablas, LEFT JOIN"},
    {"id": 6, "proc": "sp_rep_06_saldo_por_compensar", "nombre": "Saldo por compensar",
     "descripcion": "Permisos aprobados con horas todavía pendientes de compensar.",
     "params": [], "tecnica": "JOIN, LEFT JOIN, SUM de tiempos"},
    {"id": 7, "proc": "sp_rep_07_historial", "nombre": "Historial de permisos",
     "descripcion": "Historial de permisos resueltos con el empleado y su área.",
     "params": [("desde", "fecha"), ("hasta", "fecha")], "tecnica": "JOIN de 3 tablas"},
    {"id": 8, "proc": "sp_rep_08_resumen_mensual_area", "nombre": "Resumen mensual por área",
     "descripcion": "Solicitudes, tasa de aprobación y minutos aprobados por mes y área.",
     "params": [("anio", "anio")], "tecnica": "JOIN, GROUP BY, porcentaje"},
    {"id": 9, "proc": "sp_rep_09_enrutamiento", "nombre": "Enrutamiento de la aprobación",
     "descripcion": "Solicitudes dirigidas al líder de área o a RRHH según la anticipación (regla de 20 min).",
     "params": [("desde", "fecha"), ("hasta", "fecha")], "tecnica": "JOIN, CASE, AVG"},
    {"id": 10, "proc": "sp_rep_10_ranking_minutos", "nombre": "Ranking de minutos de permiso",
     "descripcion": "Empleados con más minutos de permiso aprobados y su avance de compensación.",
     "params": [("desde", "fecha"), ("hasta", "fecha"), ("top", "entero")],
     "tecnica": "JOIN, LEFT JOIN a subconsulta"},
]


def ejecutar_reporte(numero, consulta):
    rep = next((r for r in REPORTES if r["id"] == numero), None)
    if rep is None:
        raise EntradaInvalida("Reporte no encontrado")
    valores = []
    for nombre, tipo in rep["params"]:
        bruto = consulta.get(nombre)
        if tipo == "fecha":
            valores.append(fecha(bruto, nombre))
        elif tipo == "anio":
            valores.append(entero(bruto, nombre, 2000, 2100))
        else:
            valores.append(entero(bruto or 10, nombre, 1, 100))
    return llamar(rep["proc"], *valores)


# ---------------------------------------------------------------------------
# Rutas de la API
# ---------------------------------------------------------------------------
RUTAS = []


def ruta(metodo, patron):
    def registrar(funcion):
        RUTAS.append((metodo, re.compile(f"^{patron}$"), funcion))
        return funcion
    return registrar


@ruta("GET", r"/api/salud")
def salud(q, d):
    return {"ok": True, "panel": llamar("sp_panel_resumen")[0]}


@ruta("GET", r"/api/panel")
def panel(q, d):
    return {"resumen": llamar("sp_panel_resumen")[0],
            "pendientes_por_area": llamar("sp_rep_04_pendientes_por_area"),
            "bitacora": llamar("sp_bitacora_listar", 8)}


@ruta("GET", r"/api/areas")
def areas(q, d):
    return [f["area"] for f in llamar("sp_areas_listar")]


@ruta("GET", r"/api/empleados")
def empleados_listar(q, d):
    return llamar("sp_empleado_listar", q.get("buscar", ""), 1 if q.get("solo_activos") == "1" else 0)


def datos_empleado(d):
    return (nombre(d, "nombres"), nombre(d, "apellidos"), texto(d, "cargo", 30), texto(d, "area", 30))


@ruta("POST", r"/api/empleados")
def empleados_crear(q, d):
    return llamar("sp_empleado_insertar", dni(d.get("dni")), *datos_empleado(d))[0]


@ruta("PUT", r"/api/empleados/(?P<dni>\d{8})")
def empleados_actualizar(q, d, dni):
    return llamar("sp_empleado_actualizar", dni, *datos_empleado(d))[0]


@ruta("POST", r"/api/empleados/(?P<dni>\d{8})/baja")
def empleados_baja(q, d, dni):
    return llamar("sp_empleado_baja", dni)[0]


@ruta("POST", r"/api/empleados/(?P<dni>\d{8})/reactivar")
def empleados_reactivar(q, d, dni):
    return llamar("sp_empleado_reactivar", dni)[0]


@ruta("GET", r"/api/solicitudes")
def solicitudes_listar(q, d):
    estado = q.get("estado", "")
    if estado:
        opcion(estado, "estado", ("Pendiente", "Aprobado", "Rechazado"))
    return llamar("sp_solicitud_listar", q.get("buscar", ""), estado,
                  fecha(q.get("desde"), "desde", False), fecha(q.get("hasta"), "hasta", False),
                  1 if q.get("incluir_anuladas") == "1" else 0)


def datos_solicitud(d):
    return (fecha(d.get("fecha_solicitud"), "fecha_solicitud"),
            hora(d.get("hora_registro"), "hora_registro"),
            hora(d.get("hora_de_inicio"), "hora_de_inicio"),
            entero(d.get("duracion"), "duracion", 1, 60),
            opcion(d.get("subtipo"), "subtipo", ("Urgente", "Personal")),
            entero(d.get("dias", 1), "dias", 1, 30),
            hora(d.get("tiempo_laborar"), "tiempo_laborar", obligatorio=False))


@ruta("POST", r"/api/solicitudes")
def solicitudes_crear(q, d):
    return llamar("sp_solicitud_insertar", *datos_solicitud(d), dni(d.get("dni")))[0]


@ruta("PUT", r"/api/solicitudes/(?P<id>\d+)")
def solicitudes_actualizar(q, d, id):
    return llamar("sp_solicitud_actualizar", int(id), *datos_solicitud(d))[0]


@ruta("POST", r"/api/solicitudes/(?P<id>\d+)/resolver")
def solicitudes_resolver(q, d, id):
    return llamar("sp_solicitud_resolver", int(id),
                  opcion(d.get("estado"), "estado", ("Aprobado", "Rechazado")),
                  opcion(d.get("tipo_de_permiso"), "tipo_de_permiso",
                         ("Tardanza", "Tardanza justificada", "Salida anticipada", "Personal")),
                  texto(d, "motivo", 150))[0]


@ruta("POST", r"/api/solicitudes/(?P<id>\d+)/anular")
def solicitudes_anular(q, d, id):
    return llamar("sp_solicitud_anular", int(id))[0]


@ruta("GET", r"/api/solicitudes/(?P<id>\d+)/compensaciones")
def compensaciones_listar(q, d, id):
    return llamar("sp_compensacion_listar", int(id))


@ruta("POST", r"/api/solicitudes/(?P<id>\d+)/compensaciones")
def compensaciones_crear(q, d, id):
    inicio, fin = hora(d.get("hora_inicio"), "hora_inicio"), hora(d.get("hora_fin"), "hora_fin")
    if fin <= inicio:
        raise EntradaInvalida("La hora de fin debe ser posterior a la hora de inicio")
    return llamar("sp_compensacion_insertar", fecha(d.get("fecha_compensacion"), "fecha_compensacion"),
                  inicio, fin, int(id))


@ruta("DELETE", r"/api/compensaciones/(?P<id>\d+)")
def compensaciones_eliminar(q, d, id):
    return llamar("sp_compensacion_eliminar", int(id))


@ruta("POST", r"/api/compensaciones/(?P<id>\d+)/firmas")
def firmas_registrar(q, d, id):
    return llamar("sp_firma_registrar", int(id),
                  opcion(d.get("firmante"), "firmante", ("Colaborador", "Administrador")))


@ruta("DELETE", r"/api/compensaciones/(?P<id>\d+)/firmas/(?P<firmante>Colaborador|Administrador)")
def firmas_quitar(q, d, id, firmante):
    return llamar("sp_firma_quitar", int(id), firmante)


@ruta("GET", r"/api/reportes")
def reportes_catalogo(q, d):
    return [{k: v for k, v in r.items() if k != "proc"} | {"params": [p[0] for p in r["params"]]}
            for r in REPORTES]


@ruta("GET", r"/api/reportes/(?P<n>\d+)")
def reportes_ejecutar(q, d, n):
    return ejecutar_reporte(int(n), q)


@ruta("GET", r"/api/bitacora")
def bitacora(q, d):
    return llamar("sp_bitacora_listar", entero(q.get("limite") or 200, "limite", 1, 1000))


# ---------------------------------------------------------------------------
# Servidor HTTP
# ---------------------------------------------------------------------------
class Manejador(BaseHTTPRequestHandler):
    server_version = "Permisos/1.0"

    def _responder(self, estado, cuerpo, tipo="application/json; charset=utf-8"):
        datos = cuerpo if isinstance(cuerpo, bytes) else json.dumps(cuerpo, ensure_ascii=False).encode("utf-8")
        self.send_response(estado)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(datos)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(datos)

    def _api(self, metodo):
        # Solo la propia interfaz puede llamar a la API: otra página abierta en el navegador no.
        host = self.headers.get("Host", "")
        origen = self.headers.get("Origin")
        if urlparse(f"//{host}").hostname not in ("127.0.0.1", "localhost") or (
                origen and urlparse(origen).hostname not in ("127.0.0.1", "localhost")):
            return self._responder(HTTPStatus.FORBIDDEN, {"error": "Origen no permitido"})
        url = urlparse(self.path)
        consulta = {k: v[0] for k, v in parse_qs(url.query).items()}
        cuerpo = {}
        if metodo in ("POST", "PUT"):
            largo = self.headers.get("Content-Length") or "0"
            largo = int(largo) if largo.isdecimal() else 100_001
            if largo > 100_000:
                return self._responder(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "Petición demasiado grande"})
            try:
                cuerpo = json.loads(self.rfile.read(largo) or b"{}")
            except ValueError:  # JSON mal formado o texto que no es UTF-8
                return self._responder(HTTPStatus.BAD_REQUEST, {"error": "JSON no válido"})
            if not isinstance(cuerpo, dict):
                return self._responder(HTTPStatus.BAD_REQUEST, {"error": "Se esperaba un objeto JSON"})
        for m, patron, funcion in RUTAS:
            coincide = patron.match(url.path)
            if m == metodo and coincide:
                try:
                    resultado = funcion(consulta, cuerpo, **coincide.groupdict())
                    return self._responder(HTTPStatus.CREATED if metodo == "POST" else HTTPStatus.OK, resultado)
                except (EntradaInvalida, ErrorNegocio) as error:
                    return self._responder(HTTPStatus.BAD_REQUEST, {"error": str(error)})
                except OverflowError:
                    return self._responder(HTTPStatus.BAD_REQUEST, {"error": "Valor fuera del rango permitido"})
                except Exception as error:  # error inesperado: no se expone el detalle
                    self.log_error("Error interno en %s %s: %r", metodo, url.path, error)
                    return self._responder(HTTPStatus.INTERNAL_SERVER_ERROR,
                                           {"error": "Error interno del servidor o sin conexión a la base de datos"})
        return self._responder(HTTPStatus.NOT_FOUND, {"error": "Ruta no encontrada"})

    def _estatico(self):
        ruta_rel = unquote(urlparse(self.path).path).lstrip("/") or "index.html"
        archivo = (ESTATICOS / ruta_rel).resolve()
        if not archivo.is_relative_to(ESTATICOS.resolve()) or not archivo.is_file():
            archivo = ESTATICOS / "index.html"  # la SPA resuelve sus propias vistas
        if not archivo.is_file():
            return self._responder(HTTPStatus.NOT_FOUND, b"Interfaz no compilada: ejecute npm run build",
                                   "text/plain; charset=utf-8")
        tipo = mimetypes.guess_type(archivo.name)[0] or "application/octet-stream"
        self._responder(HTTPStatus.OK, archivo.read_bytes(), tipo)

    def do_GET(self):
        self._api("GET") if self.path.startswith("/api/") else self._estatico()

    def do_POST(self):
        self._api("POST")

    def do_PUT(self):
        self._api("PUT")

    def do_DELETE(self):
        self._api("DELETE")


def main():
    puerto = int(os.environ.get("PERMISOS_APP_PORT", "8080"))
    servidor = ThreadingHTTPServer(("127.0.0.1", puerto), Manejador)
    print(f"Sistema de permisos escuchando en http://127.0.0.1:{puerto}  (Ctrl+C para salir)")
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
