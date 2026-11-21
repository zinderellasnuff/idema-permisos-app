"""Genera 03_datos.sql: los datos de la Entrega 4 más un volumen mayor de
datos de prueba coherentes con las reglas del negocio (topes, compensación
exacta, historial solo de solicitudes resueltas). Es determinista (semilla fija).
Uso: python generar_datos.py > 03_datos.sql
"""
import random
from datetime import date, time, timedelta, datetime

random.seed(2026)
HOY = date(2026, 11, 20)

ORIGINAL = open(__file__.replace("generar_datos.py", "datos_entrega4.sql"), encoding="utf-8").read()

# --- 10 empleados de la Entrega 4 -----------------------------------------
EMP = [
    ("72123249", "Milagros", "Cáceres", "Docente", "Enfermería Técnica"),
    ("60782954", "Deyanira", "Casaperalta", "Líder de Administración", "Administración"),
    ("72221744", "Jose", "Molina", "Asistente administrativo", "Administración"),
    ("74839201", "Julián", "Rivas Rodríguez", "Docente", "Contabilidad"),
    ("45612378", "Rosa", "Quispe Mamani", "Docente", "Producción Agropecuaria"),
    ("70451236", "Carlos", "Huamán Torres", "Coordinador académico", "Administración de Empresas"),
    ("41258963", "Lucía", "Flores Ccama", "Secretaria académica", "Secretaría Académica"),
    ("73698521", "Miguel", "Apaza Condori", "Técnico de soporte", "Sistemas"),
    ("46987123", "Karina", "Zúñiga Paredes", "Docente", "Administración Bancaria"),
    ("71324598", "Renzo", "Valdivia Ríos", "Asistente de RR.HH.", "Recursos Humanos"),
]
# --- solicitudes de la Entrega 4 (para respetar topes) ---------------------
ORIG_SOL = [  # (fecha, subtipo, estado, dni, hora_inicio)
    ("2026-08-17", "Urgente", "Aprobado", "72123249", "08:00"), ("2026-08-10", "Personal", "Aprobado", "60782954", "08:00"),
    ("2026-08-07", "Urgente", "Aprobado", "72221744", "08:00"), ("2026-08-05", "Personal", "Aprobado", "74839201", "08:00"),
    ("2026-08-12", "Urgente", "Aprobado", "45612378", "08:00"), ("2026-08-14", "Personal", "Rechazado", "70451236", "12:00"),
    ("2026-08-19", "Urgente", "Aprobado", "41258963", "08:00"), ("2026-08-20", "Personal", "Aprobado", "73698521", "11:00"),
    ("2026-08-24", "Urgente", "Aprobado", "72123249", "08:00"), ("2026-08-25", "Personal", "Aprobado", "72123249", "15:00"),
    ("2026-08-26", "Urgente", "Rechazado", "46987123", "08:00"), ("2026-08-27", "Personal", "Aprobado", "71324598", "16:00"),
    ("2026-09-01", "Urgente", "Pendiente", "74839201", "08:00"), ("2026-09-01", "Personal", "Pendiente", "45612378", "10:30"),
    ("2026-09-02", "Urgente", "Pendiente", "73698521", "08:00"), ("2026-09-02", "Personal", "Pendiente", "72221744", "14:00"),
    ("2026-08-28", "Personal", "Aprobado", "72123249", "10:00"),
]

NOMBRES = ["Ana", "Luis", "María", "Jorge", "Patricia", "Ricardo", "Elena", "Fernando", "Sofía", "Diego",
           "Gabriela", "Óscar", "Valeria", "Héctor", "Carmen", "Raúl", "Daniela", "Edwin", "Paola", "Víctor",
           "Silvia", "Alberto", "Natalia", "Wilber", "Roxana", "Iván", "Yesenia", "Marco", "Fiorella", "Néstor"]
APELLIDOS = ["Mamani Quispe", "Condori Huanca", "Ramos Tapia", "Ccahuana Puma", "Salas Medina", "Choque Lima",
             "Pari Cutipa", "Vargas Núñez", "Delgado Zevallos", "Huanca Arapa", "Chávez Benavides", "Llerena Paz",
             "Bustamante Rey", "Ticona Mendoza", "Coaguila Rojas", "Pinto Linares", "Gutiérrez Vera", "Ochoa Salinas",
             "Cornejo Málaga", "Arce Valdivia", "Yucra Ccori", "Torres Lazo", "Begazo Díaz", "Quispe Apaza",
             "Mendoza Rivera", "Flores Zegarra", "Paredes Chirinos", "Rojas Cuba", "Herrera Talavera", "Molina Bedoya"]
AREAS = {
    "Enfermería Técnica": ["Docente", "Docente", "Coordinador de carrera"],
    "Producción Agropecuaria": ["Docente", "Docente", "Técnico de campo"],
    "Contabilidad": ["Docente", "Asistente contable"],
    "Administración de Empresas": ["Docente", "Docente"],
    "Administración Bancaria": ["Docente", "Coordinador de carrera"],
    "Administración": ["Asistente administrativo", "Cajera"],
    "Secretaría Académica": ["Asistente académico"],
    "Sistemas": ["Técnico de soporte", "Desarrollador"],
    "Recursos Humanos": ["Analista de RR.HH."],
    "Bienestar Estudiantil": ["Psicóloga", "Asistenta social"],
    "Biblioteca": ["Bibliotecario"],
    "Mantenimiento": ["Técnico de mantenimiento", "Vigilante"],
}
areas = list(AREAS)
nuevos = []
usados_dni = {e[0] for e in EMP}
for k in range(30):
    while True:
        dni = str(random.randint(40000000, 79999999))
        if dni not in usados_dni:
            usados_dni.add(dni); break
    area = areas[k % len(areas)]
    nuevos.append((dni, NOMBRES[k], APELLIDOS[k], random.choice(AREAS[area]), area))
TODOS = EMP + nuevos

MOT_URG = ["Tráfico", "Paro de transportistas", "Cita médica", "Malestar estomacal", "Corte de agua en domicilio",
           "Llevar a hijo al colegio", "Falla del transporte público", "Emergencia familiar", "Lluvia intensa",
           "Trámite urgente en el banco"]
MOT_PER = ["Trámite en RENIEC", "Cita odontológica", "Gestión municipal", "Trámite notarial", "Reunión en colegio del hijo",
           "Trámite bancario", "Cita en EsSalud", "Trámite en SUNAT", "Control médico", "Matrícula de hijo"]

def hhmm(m): return f"{m // 60:02d}:{m % 60:02d}"
def semana(d): return d - timedelta(days=d.weekday())

urg_sem, per_mes, unicos = {}, {}, set()
for f, sub, est, dni, hi in ORIG_SOL:
    d = date.fromisoformat(f)
    unicos.add((dni, d, hi))
    if est != "Rechazado":
        if sub == "Urgente": urg_sem[(dni, semana(d))] = urg_sem.get((dni, semana(d)), 0) + 1
        else: per_mes[(dni, d.year, d.month)] = per_mes.get((dni, d.year, d.month), 0) + 1

sol, hist, comp, firmas = [], [], [], []
next_id, next_comp = 1018, 5012
dias = [date(2026, 7, 1) + timedelta(days=i) for i in range((HOY - date(2026, 7, 1)).days + 1)]
dias_lab = [d for d in dias if d.weekday() < 5]

for d in dias_lab:
    for emp in random.sample(TODOS, k=random.randint(1, 4)):
        dni = emp[0]
        sub = "Urgente" if random.random() < 0.55 else "Personal"
        if sub == "Urgente":
            if urg_sem.get((dni, semana(d)), 0) >= 1: continue
            inicio = random.choice([8 * 60, 8 * 60, 7 * 60 + 30, 14 * 60])
            dur = random.choice([10, 15, 20, 25, 30, 40, 45])
            antic = random.choice([5, 8, 10, 12, 15, 20, 25, 30, 40])
        else:
            if per_mes.get((dni, d.year, d.month), 0) >= 2: continue
            inicio = random.choice([9 * 60, 10 * 60, 11 * 60, 12 * 60, 15 * 60, 16 * 60])
            dur = random.choice([30, 45, 60, 60])
            antic = random.choice([30, 45, 60, 90, 120, 180, 15])
        hi = hhmm(inicio)
        if (dni, d, hi) in unicos: continue
        unicos.add((dni, d, hi))
        hreg = hhmm(inicio - antic)
        # estado: lo reciente queda pendiente
        if d >= HOY - timedelta(days=3):
            est = "Pendiente" if random.random() < 0.8 else "Aprobado"
        else:
            est = "Aprobado" if random.random() < 0.85 else "Rechazado"
        tl = None
        if est == "Aprobado" and random.random() < 0.7:
            tl = dur
        diasp = 1 if random.random() < 0.92 else 2
        sid = next_id; next_id += 1
        sol.append((sid, d, hreg, hi, dur, sub, diasp, est, tl, dni))
        if est != "Rechazado":
            if sub == "Urgente": urg_sem[(dni, semana(d))] = urg_sem.get((dni, semana(d)), 0) + 1
            else: per_mes[(dni, d.year, d.month)] = per_mes.get((dni, d.year, d.month), 0) + 1
        if est != "Pendiente":
            tipo = (random.choice(["Tardanza", "Tardanza justificada"]) if sub == "Urgente"
                    else random.choice(["Personal", "Salida anticipada"]))
            mot = random.choice(MOT_URG if sub == "Urgente" else MOT_PER)
            hist.append((sid, tipo, mot, min(d + timedelta(days=random.choice([0, 0, 1])), HOY)))
        # compensación exacta (o parcial si es reciente)
        if tl:
            restante = tl
            if d >= HOY - timedelta(days=12) and random.random() < 0.6:
                restante = max(5, (tl // 2) // 5 * 5)  # queda saldo pendiente
            fecha_c = d + timedelta(days=1)
            while restante > 0:
                blk = min(restante, random.choice([15, 20, 30, 30, 45, 60]))
                while fecha_c.weekday() >= 5: fecha_c += timedelta(days=1)
                if fecha_c > HOY: break
                comp.append((next_comp, fecha_c, "17:00", hhmm(17 * 60 + blk), sid))
                firmas.append((next_comp, "Colaborador"))
                if fecha_c < HOY - timedelta(days=4) or random.random() < 0.3:
                    firmas.append((next_comp, "Administrador"))
                next_comp += 1; restante -= blk
                fecha_c += timedelta(days=random.choice([1, 1, 2, 3]))

def q(v):
    if v is None: return "NULL"
    if isinstance(v, int): return str(v)
    return "'" + str(v).replace("'", "''") + "'"

out = []
out.append("-- =====================================================================")
out.append("-- Script 3 (Entrega 5): datos de prueba ampliados.")
out.append("-- Parte A: datos de la Entrega 4 (sin cambios).")
out.append(f"-- Parte B: {len(nuevos)} empleados, {len(sol)} solicitudes, {len(hist)} registros de historial,")
out.append(f"--          {len(comp)} bloques de compensación y {len(firmas)} firmas generados con")
out.append("--          generar_datos.py (semilla fija), respetando los topes y la")
out.append("--          regla de compensación (los disparadores validan cada fila).")
out.append("-- Parte C: bajas lógicas de ejemplo.")
out.append("-- =====================================================================")
out.append("USE idema_permisos;")
out.append("")
out.append("-- Parte A ------------------------------------------------------------")
out.append(ORIGINAL.strip())
out.append("")
out.append("-- Parte B ------------------------------------------------------------")
out.append("INSERT INTO empleado (dni, nombres, apellidos, cargo, area) VALUES")
out.append(",\n".join(f"({q(a)}, {q(b)}, {q(c)}, {q(dd)}, {q(e)})" for a, b, c, dd, e in nuevos) + ";")
out.append("")
for i in range(0, len(sol), 50):
    out.append("INSERT INTO solicitud_permiso (id_permiso, fecha_solicitud, hora_registro, hora_de_inicio, duracion, subtipo, dias, estado, tiempo_laborar, dni) VALUES")
    out.append(",\n".join(f"({s[0]}, {q(s[1].isoformat())}, {q(s[2])}, {q(s[3])}, {s[4]}, {q(s[5])}, {s[6]}, {q(s[7])}, {q(hhmm(s[8]) if s[8] else None)}, {q(s[9])})"
                          for s in sol[i:i + 50]) + ";")
out.append("")
for i in range(0, len(hist), 60):
    out.append("INSERT INTO historial_permiso (id_permiso, tipo_de_permiso, motivo, fecha) VALUES")
    out.append(",\n".join(f"({h[0]}, {q(h[1])}, {q(h[2])}, {q(h[3].isoformat())})" for h in hist[i:i + 60]) + ";")
out.append("")
for i in range(0, len(comp), 60):
    out.append("INSERT INTO compensacion (id_compensacion, fecha_compensacion, hora_inicio, hora_fin, id_permiso) VALUES")
    out.append(",\n".join(f"({c[0]}, {q(c[1].isoformat())}, {q(c[2])}, {q(c[3])}, {c[4]})" for c in comp[i:i + 60]) + ";")
out.append("")
for i in range(0, len(firmas), 80):
    out.append("INSERT INTO firma_compensacion (id_compensacion, firmante) VALUES")
    out.append(",\n".join(f"({f[0]}, {q(f[1])})" for f in firmas[i:i + 80]) + ";")
out.append("")
# Parte C: bajas lógicas (empleados sin pendientes) y anulaciones de solicitudes pendientes
pend_dni = {s[9] for s in sol if s[7] == "Pendiente"} | {o[3] for o in ORIG_SOL if o[2] == "Pendiente"}
bajas = [e[0] for e in nuevos if e[0] not in pend_dni][:2]
anular = [s[0] for s in sol if s[7] == "Pendiente"][:3]
out.append("-- Parte C ------------------------------------------------------------")
out.append("-- Bajas lógicas de ejemplo (el disparador registra la fecha y la bitácora).")
for b in bajas: out.append(f"UPDATE empleado SET activo = 0 WHERE dni = {q(b)};")
for a in anular: out.append(f"UPDATE solicitud_permiso SET activo = 0 WHERE id_permiso = {a};")
print("\n".join(out))
