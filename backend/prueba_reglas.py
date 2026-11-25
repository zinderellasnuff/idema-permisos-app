"""Intenta saltar cada regla llamando directo a la API (sin el formulario).

Crea datos de prueba: úsese solo sobre una base local que se pueda recargar.
Uso:  python prueba_reglas.py http://127.0.0.1:8091
"""
import json
import sys
import threading
import urllib.error
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080"


def pedir(metodo, ruta, cuerpo=None, **cabeceras):
    datos = cuerpo if isinstance(cuerpo, bytes) else None if cuerpo is None else json.dumps(cuerpo).encode()
    req = urllib.request.Request(f"{BASE}/api{ruta}", datos, cabeceras, method=metodo)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def rechaza(caso, respuesta, texto=""):
    estado, cuerpo = respuesta
    assert estado in (400, 403), f"{caso}: se esperaba rechazo y devolvió {estado} {cuerpo}"
    assert texto in cuerpo["error"], f"{caso}: {cuerpo['error']}"
    print(f"  rechazado  {caso}: {cuerpo['error']}")


def acepta(respuesta):
    estado, cuerpo = respuesta
    assert estado in (200, 201), respuesta
    return cuerpo


DNI = "70112244"
sol = lambda **c: {"dni": DNI, "fecha_solicitud": "2027-03-01", "hora_registro": "08:00", "hora_de_inicio": "09:00",
                   "duracion": 30, "subtipo": "Personal", "dias": 1, "tiempo_laborar": "", **c}
nueva = lambda **c: pedir("POST", "/solicitudes", sol(**c))

print("Empleado")
emp = {"dni": DNI, "nombres": "Ana", "apellidos": "Prueba", "cargo": "Docente", "area": "Sistemas"}
acepta(pedir("POST", "/empleados", emp))
for caso, cambio in {"DNI corto": {"dni": "123"}, "DNI con letras": {"dni": "7011224A"}, "DNI numérico": {"dni": 70112255},
                     "DNI repetido": {}, "nombre vacío": {"dni": "70112255", "nombres": "   "},
                     "nombre con números": {"dni": "70112255", "nombres": "Ana 3"},
                     "nombre largo": {"dni": "70112255", "nombres": "a" * 51},
                     "cargo vacío": {"dni": "70112255", "cargo": ""}, "área como lista": {"dni": "70112255", "area": ["x"]}}.items():
    rechaza(caso, pedir("POST", "/empleados", {**emp, **cambio}))

print("Solicitud")
for caso, cambio in {"61 minutos": {"duracion": 61}, "0 minutos": {"duracion": 0}, "duración decimal": {"duracion": 30.9},
                     "subtipo inventado": {"subtipo": "Vacaciones"}, "0 días": {"dias": 0}, "fecha imposible": {"fecha_solicitud": "2027-02-30"},
                     "fecha vacía": {"fecha_solicitud": ""}, "fecha numérica": {"fecha_solicitud": 20270301}, "hora 25:00": {"hora_de_inicio": "25:00"},
                     "compensar 0 min": {"tiempo_laborar": "00:00"}, "registro después del inicio": {"hora_registro": "09:01"},
                     "pasa de medianoche": {"hora_de_inicio": "23:50"}, "empleado inexistente": {"dni": "00000000"}}.items():
    rechaza(caso, nueva(**cambio))
a = acepta(nueva(tiempo_laborar="00:30"))["id_permiso"]
rechaza("horario cruzado", nueva(hora_de_inicio="09:15", subtipo="Urgente"), "se cruza")
b = acepta(nueva(hora_de_inicio="11:00", subtipo="Urgente"))["id_permiso"]
rechaza("2.º Urgente de la semana", nueva(fecha_solicitud="2027-03-03", subtipo="Urgente"), "Tope")
c = acepta(nueva(fecha_solicitud="2027-03-04"))["id_permiso"]
rechaza("3.er Personal del mes", nueva(fecha_solicitud="2027-03-20"), "Tope")
editar = lambda i, **k: pedir("PUT", f"/solicitudes/{i}", {x: y for x, y in sol(**k).items() if x != "dni"})
rechaza("editar Personal a Urgente para saltar el tope", editar(c, fecha_solicitud="2027-03-04", subtipo="Urgente"), "Tope")
d = acepta(nueva(fecha_solicitud="2027-04-05"))["id_permiso"]
rechaza("mover de mes para saltar el tope", editar(d, fecha_solicitud="2027-03-25"), "Tope")
acepta(editar(c, fecha_solicitud="2027-03-04", duracion=45))  # editar sin cambiar de tope sí se puede

print("Dos registros a la vez")
salidas = []
hilos = [threading.Thread(target=lambda h=h: salidas.append(nueva(fecha_solicitud="2027-05-03", hora_de_inicio=f"{h}:00", subtipo="Urgente")[0])) for h in range(10, 18)]
[h.start() for h in hilos], [h.join() for h in hilos]
assert salidas.count(201) == 1, salidas
print("  de 8 simultáneos entró 1")

print("Resolución")
res = {"estado": "Aprobado", "tipo_de_permiso": "Personal", "motivo": "Trámite"}
for caso, cambio in {"sin motivo": {"motivo": "  "}, "motivo de 151": {"motivo": "x" * 151}, "estado inventado": {"estado": "Pendiente"},
                     "tipo inventado": {"tipo_de_permiso": "Otro"}}.items():
    rechaza(caso, pedir("POST", f"/solicitudes/{a}/resolver", {**res, **cambio}))
rechaza("baja con pendientes", pedir("POST", f"/empleados/{DNI}/baja"), "pendientes")
acepta(pedir("POST", f"/solicitudes/{a}/resolver", res))
rechaza("resolver dos veces", pedir("POST", f"/solicitudes/{a}/resolver", {**res, "estado": "Rechazado"}))
rechaza("cambiar el tiempo a compensar ya aprobado", editar(a, tiempo_laborar="00:01"), "pendientes")
rechaza("cambiar la hora de registro ya aprobada", editar(a, tiempo_laborar="00:30", hora_registro="08:50"), "pendientes")

print("Compensación y firmas")
bloque = lambda i=a, f="2027-03-02", x="17:00", y="17:20": pedir("POST", f"/solicitudes/{i}/compensaciones", {"fecha_compensacion": f, "hora_inicio": x, "hora_fin": y})
rechaza("solicitud pendiente", bloque(i=c), "aprobadas")
rechaza("fin antes del inicio", bloque(y="16:00"))
rechaza("antes del permiso", bloque(f="2027-02-28"), "anterior")
rechaza("más del tiempo a compensar", bloque(y="17:31"), "supera")
k = acepta(bloque())[0]["id_compensacion"]
rechaza("bloque cruzado", bloque(x="17:10", y="17:15"), "se cruza")
rechaza("excede el saldo", bloque(x="18:00", y="18:11"), "supera")
firma = lambda q: pedir("POST", f"/compensaciones/{k}/firmas", {"firmante": q})
rechaza("administrador firma primero", firma("Administrador"), "Primero")
rechaza("firmante inventado", firma("Otro"))
acepta(firma("Colaborador"))
rechaza("firmar dos veces", firma("Colaborador"), "ya está registrada")
acepta(firma("Administrador"))
rechaza("borrar bloque firmado", pedir("DELETE", f"/compensaciones/{k}"), "firmada")
rechaza("quitar la firma del administrador", pedir("DELETE", f"/compensaciones/{k}/firmas/Administrador"), "definitiva")
rechaza("anular con compensaciones", pedir("POST", f"/solicitudes/{a}/anular"), "compensaciones")

print("Anuladas y bajas")
acepta(pedir("POST", f"/solicitudes/{b}/anular"))
rechaza("editar anulada", editar(b, hora_de_inicio="12:00"), "anulada")
rechaza("resolver anulada", pedir("POST", f"/solicitudes/{b}/resolver", res))

print("Servidor")
rechaza("otra página web", pedir("POST", f"/empleados/{DNI}/reactivar", Origin="http://sitio-malo.com"), "Origen")
rechaza("JSON roto", pedir("POST", "/empleados", b"{"))
rechaza("JSON que no es objeto", pedir("POST", "/empleados", b"[]"))
rechaza("número gigante", pedir("POST", f"/solicitudes/{10**30}/anular"))
print("\nREGLAS: OK")
