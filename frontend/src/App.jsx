import { useCallback, useEffect, useState } from 'react'
import { api } from './api.js'
import { Aviso, Campo, Modal, Tabla, aCSV } from './componentes.jsx'

const VISTAS = [
  ['panel', 'Panel', '◧'],
  ['empleados', 'Empleados', '☺'],
  ['solicitudes', 'Solicitudes', '✎'],
  ['reportes', 'Reportes', '▤'],
  ['bitacora', 'Bitácora', '⟲'],
]
const hoy = () => new Date().toISOString().slice(0, 10)
const ahora = () => new Date().toTimeString().slice(0, 5)

export default function App() {
  // La vista activa se guarda en la URL (#solicitudes, #reportes…) para poder enlazarla.
  const [vista, setVistaEstado] = useState(() => VISTAS.some(([id]) => `#${id}` === location.hash) ? location.hash.slice(1) : 'panel')
  const setVista = useCallback((v) => { setVistaEstado(v); history.replaceState(null, '', `#${v}`) }, [])
  useEffect(() => {
    const alCambiar = () => VISTAS.some(([id]) => `#${id}` === location.hash) && setVistaEstado(location.hash.slice(1))
    window.addEventListener('hashchange', alCambiar)
    return () => window.removeEventListener('hashchange', alCambiar)
  }, [])
  const [aviso, setAviso] = useState(null)
  const notificar = useCallback((texto, tipo = 'ok') => setAviso({ texto, tipo }), [])
  const cerrarAviso = useCallback(() => setAviso(null), [])
  const Vista = { panel: Panel, empleados: Empleados, solicitudes: Solicitudes, reportes: Reportes, bitacora: Bitacora }[vista]
  return (
    <div className="app">
      <aside className="lateral">
        <div className="marca">
          <strong>IDEMA</strong>
          <span>Permisos por hora</span>
        </div>
        <nav>
          {VISTAS.map(([id, nombre, icono]) => (
            <button key={id} className={vista === id ? 'activo' : ''} onClick={() => setVista(id)}
                    aria-current={vista === id ? 'page' : undefined}>
              <span aria-hidden="true">{icono}</span> {nombre}
            </button>
          ))}
        </nav>
        <p className="pie-lateral">Instituto Superior Tecnológico Santiago Ramón y Cajal</p>
      </aside>
      <main className="contenido">
        <Vista notificar={notificar} irA={setVista} />
      </main>
      <Aviso aviso={aviso} onCerrar={cerrarAviso} />
    </div>
  )
}

// Ejecuta una acción del API y muestra el resultado o el mensaje de error
// que devuelve la base de datos (topes, validaciones de los disparadores, etc.).
function useAccion(notificar) {
  return async (fn, ok) => {
    try {
      const r = await fn()
      if (ok) notificar(ok)
      return r
    } catch (e) {
      notificar(e.message, 'error')
      return undefined
    }
  }
}

/* ============================== PANEL ============================== */
function Panel({ notificar, irA }) {
  const [datos, setDatos] = useState(null)
  useEffect(() => { api.panel().then(setDatos).catch((e) => notificar(e.message, 'error')) }, [notificar])
  if (!datos) return <p className="vacio">Cargando…</p>
  const r = datos.resumen
  const tarjetas = [
    ['Empleados activos', r.empleados_activos, 'empleados'],
    ['Solicitudes', r.solicitudes, 'solicitudes'],
    ['Pendientes', r.pendientes, 'solicitudes', 'alerta'],
    ['Aprobadas', r.aprobadas, 'solicitudes'],
    ['Rechazadas', r.rechazadas, 'solicitudes'],
    ['Compensaciones sin firma del administrador', r.compensaciones_sin_firma, 'reportes', 'alerta'],
  ]
  return (
    <>
      <Encabezado titulo="Panel" texto="Resumen del registro de permisos por hora." />
      <div className="tarjetas">
        {tarjetas.map(([t, v, destino, tono]) => (
          <button key={t} className={`tarjeta ${tono || ''}`} onClick={() => irA(destino)}>
            <span className="valor">{v}</span>
            <span>{t}</span>
          </button>
        ))}
      </div>
      <div className="dos-columnas">
        <section className="caja">
          <h3>Pendientes por área</h3>
          <Tabla filas={datos.pendientes_por_area} vacio="No hay solicitudes pendientes" />
        </section>
        <section className="caja">
          <h3>Últimos movimientos</h3>
          <Tabla filas={datos.bitacora.map(({ fecha_hora, operacion, tabla, detalle }) => ({ fecha_hora, operacion, tabla, detalle }))} />
        </section>
      </div>
    </>
  )
}

function Encabezado({ titulo, texto, children }) {
  return (
    <header className="encabezado">
      <div>
        <h1>{titulo}</h1>
        {texto && <p>{texto}</p>}
      </div>
      <div className="botones">{children}</div>
    </header>
  )
}

/* ============================ EMPLEADOS ============================ */
const EMPLEADO_VACIO = { dni: '', nombres: '', apellidos: '', cargo: '', area: '' }

function Empleados({ notificar }) {
  const [filas, setFilas] = useState([])
  const [buscar, setBuscar] = useState('')
  const [soloActivos, setSoloActivos] = useState(false)
  const [form, setForm] = useState(null) // {datos, nuevo}
  const [areas, setAreas] = useState([])
  const accion = useAccion(notificar)

  const cargar = useCallback(() => {
    api.empleados({ buscar, solo_activos: soloActivos ? 1 : 0 }).then(setFilas).catch((e) => notificar(e.message, 'error'))
  }, [buscar, soloActivos, notificar])
  useEffect(() => { const t = setTimeout(cargar, 250); return () => clearTimeout(t) }, [cargar])
  useEffect(() => { api.areas().then(setAreas).catch(() => {}) }, [])

  const guardar = async (e) => {
    e.preventDefault()
    const { dni, ...resto } = form.datos
    const ok = form.nuevo
      ? await accion(() => api.crearEmpleado(form.datos), 'Empleado registrado')
      : await accion(() => api.editarEmpleado(dni, resto), 'Empleado actualizado')
    if (ok) { setForm(null); cargar() }
  }
  const baja = async (f) => {
    if (!confirm(`¿Dar de baja a ${f.nombres} ${f.apellidos}? Se conservará su historial.`)) return
    if (await accion(() => api.bajaEmpleado(f.dni), 'Empleado dado de baja')) cargar()
  }
  const reactivar = async (f) => { if (await accion(() => api.reactivarEmpleado(f.dni), 'Empleado reactivado')) cargar() }

  return (
    <>
      <Encabezado titulo="Empleados" texto="Registro del personal. La eliminación es lógica: el empleado se da de baja y conserva su historial.">
        <button className="btn" onClick={() => setForm({ datos: EMPLEADO_VACIO, nuevo: true })}>+ Nuevo empleado</button>
      </Encabezado>
      <div className="filtros">
        <input type="search" placeholder="Buscar por DNI, nombre o área" value={buscar} onChange={(e) => setBuscar(e.target.value)} aria-label="Buscar empleados" />
        <label className="check"><input type="checkbox" checked={soloActivos} onChange={(e) => setSoloActivos(e.target.checked)} /> Solo activos</label>
        <span className="tenue">{filas.length} registros</span>
      </div>
      <Tabla
        filas={filas}
        resaltar={(f) => (f.activo ? '' : 'fila-baja')}
        acciones={(f) => (
          <>
            <button className="btn-link" onClick={() => setForm({ datos: { dni: f.dni, nombres: f.nombres, apellidos: f.apellidos, cargo: f.cargo, area: f.area }, nuevo: false })}>Editar</button>
            {f.activo
              ? <button className="btn-link peligro" onClick={() => baja(f)}>Dar de baja</button>
              : <button className="btn-link" onClick={() => reactivar(f)}>Reactivar</button>}
          </>
        )}
      />
      {form && (
        <Modal titulo={form.nuevo ? 'Nuevo empleado' : `Editar empleado ${form.datos.dni}`} onCerrar={() => setForm(null)}>
          <form onSubmit={guardar} className="formulario">
            <Campo etiqueta="DNI" ayuda="8 dígitos">
              <input required pattern="\d{8}" maxLength={8} disabled={!form.nuevo} value={form.datos.dni}
                     onChange={(e) => setForm({ ...form, datos: { ...form.datos, dni: e.target.value } })} />
            </Campo>
            {[['nombres', 'Nombres', 50], ['apellidos', 'Apellidos', 50], ['cargo', 'Cargo', 30]].map(([k, et, max]) => (
              <Campo key={k} etiqueta={et}>
                <input required maxLength={max} value={form.datos[k]} onChange={(e) => setForm({ ...form, datos: { ...form.datos, [k]: e.target.value } })} />
              </Campo>
            ))}
            <Campo etiqueta="Área">
              <input required maxLength={30} list="lista-areas" value={form.datos.area}
                     onChange={(e) => setForm({ ...form, datos: { ...form.datos, area: e.target.value } })} />
              <datalist id="lista-areas">{areas.map((a) => <option key={a} value={a} />)}</datalist>
            </Campo>
            <div className="botones-form">
              <button type="button" className="btn secundario" onClick={() => setForm(null)}>Cancelar</button>
              <button className="btn">Guardar</button>
            </div>
          </form>
        </Modal>
      )}
    </>
  )
}

/* =========================== SOLICITUDES =========================== */
const SOLICITUD_VACIA = () => ({ dni: '', fecha_solicitud: hoy(), hora_registro: ahora(), hora_de_inicio: '08:00', duracion: 30, subtipo: 'Urgente', dias: 1, tiempo_laborar: '' })

function Solicitudes({ notificar }) {
  const [filas, setFilas] = useState([])
  const [filtro, setFiltro] = useState({ buscar: '', estado: '', desde: '', hasta: '', incluir_anuladas: 0 })
  const [form, setForm] = useState(null)       // nueva / editar
  const [resolver, setResolver] = useState(null)
  const [comp, setComp] = useState(null)       // solicitud cuyas compensaciones se ven
  const [empleados, setEmpleados] = useState([])
  const accion = useAccion(notificar)

  const cargar = useCallback(() => {
    api.solicitudes(filtro).then(setFilas).catch((e) => notificar(e.message, 'error'))
  }, [filtro, notificar])
  useEffect(() => { const t = setTimeout(cargar, 250); return () => clearTimeout(t) }, [cargar])
  useEffect(() => { api.empleados({ solo_activos: 1 }).then(setEmpleados).catch(() => {}) }, [])

  const guardar = async (e) => {
    e.preventDefault()
    const d = { ...form.datos, duracion: Number(form.datos.duracion), dias: Number(form.datos.dias) }
    const ok = form.id
      ? await accion(() => api.editarSolicitud(form.id, d), 'Solicitud actualizada')
      : await accion(() => api.crearSolicitud(d), 'Solicitud registrada')
    if (ok) { setForm(null); cargar() }
  }
  const anular = async (f) => {
    if (!confirm(`¿Anular la solicitud ${f.id_permiso}? Quedará registrada como anulada.`)) return
    if (await accion(() => api.anularSolicitud(f.id_permiso), 'Solicitud anulada')) cargar()
  }
  const set = (k, v) => setFiltro((x) => ({ ...x, [k]: v }))
  const vista = filas.map(({ id_permiso, fecha_solicitud, empleado, area, subtipo, hora_de_inicio, duracion, destino, estado, tiempo_laborar, activo, ...resto }) =>
    ({ id_permiso, fecha_solicitud, empleado, area, subtipo, hora_de_inicio, duracion, destino, estado, tiempo_laborar, ...(filtro.incluir_anuladas ? { activo } : {}), _f: { id_permiso, activo, estado, ...resto, fecha_solicitud, hora_de_inicio, duracion, subtipo, tiempo_laborar, empleado } }))

  return (
    <>
      <Encabezado titulo="Solicitudes de permiso" texto="Permisos por hora: registro, aprobación, compensación de horas y anulación.">
        <button className="btn" onClick={() => setForm({ datos: SOLICITUD_VACIA() })}>+ Nueva solicitud</button>
      </Encabezado>
      <div className="filtros">
        <input type="search" placeholder="Buscar por N.º, DNI, empleado o área" value={filtro.buscar} onChange={(e) => set('buscar', e.target.value)} aria-label="Buscar solicitudes" />
        <select value={filtro.estado} onChange={(e) => set('estado', e.target.value)} aria-label="Estado">
          <option value="">Todos los estados</option><option>Pendiente</option><option>Aprobado</option><option>Rechazado</option>
        </select>
        <label className="en-linea">Desde <input type="date" value={filtro.desde} onChange={(e) => set('desde', e.target.value)} /></label>
        <label className="en-linea">Hasta <input type="date" value={filtro.hasta} onChange={(e) => set('hasta', e.target.value)} /></label>
        <label className="check"><input type="checkbox" checked={!!filtro.incluir_anuladas} onChange={(e) => set('incluir_anuladas', e.target.checked ? 1 : 0)} /> Ver anuladas</label>
        <span className="tenue">{filas.length} registros</span>
      </div>
      <Tabla
        filas={vista.map(({ _f, ...v }) => v)}
        resaltar={(f) => (f.activo === 0 ? 'fila-baja' : '')}
        acciones={(v) => {
          const f = vista.find((x) => x.id_permiso === v.id_permiso)._f
          if (!f.activo) return <span className="tenue">Anulada</span>
          return (
            <>
              {f.estado === 'Pendiente' && <>
                <button className="btn-link" onClick={() => setResolver({ f, estado: 'Aprobado', tipo_de_permiso: f.subtipo === 'Urgente' ? 'Tardanza justificada' : 'Personal', motivo: '' })}>Resolver</button>
                <button className="btn-link" onClick={() => setForm({ id: f.id_permiso, datos: { dni: f.dni, fecha_solicitud: f.fecha_solicitud, hora_registro: f.hora_registro, hora_de_inicio: f.hora_de_inicio, duracion: f.duracion, subtipo: f.subtipo, dias: f.dias, tiempo_laborar: f.tiempo_laborar || '' } })}>Editar</button>
              </>}
              {f.estado === 'Aprobado' && f.tiempo_laborar && <button className="btn-link" onClick={() => setComp(f)}>Compensación</button>}
              <button className="btn-link peligro" onClick={() => anular(f)}>Anular</button>
            </>
          )
        }}
      />
      {form && (
        <Modal titulo={form.id ? `Editar solicitud ${form.id}` : 'Nueva solicitud de permiso'} onCerrar={() => setForm(null)}>
          <form onSubmit={guardar} className="formulario">
            <Campo etiqueta="Empleado">
              <select required disabled={!!form.id} value={form.datos.dni} onChange={(e) => setForm({ ...form, datos: { ...form.datos, dni: e.target.value } })}>
                <option value="">Seleccione…</option>
                {empleados.map((e) => <option key={e.dni} value={e.dni}>{e.apellidos}, {e.nombres} — {e.area}</option>)}
              </select>
            </Campo>
            <div className="fila-campos">
              <Campo etiqueta="Subtipo">
                <select value={form.datos.subtipo} onChange={(e) => setForm({ ...form, datos: { ...form.datos, subtipo: e.target.value } })}>
                  <option>Urgente</option><option>Personal</option>
                </select>
              </Campo>
              <Campo etiqueta="Fecha del permiso">
                <input type="date" required value={form.datos.fecha_solicitud} onChange={(e) => setForm({ ...form, datos: { ...form.datos, fecha_solicitud: e.target.value } })} />
              </Campo>
            </div>
            <div className="fila-campos">
              <Campo etiqueta="Hora de registro"><input type="time" required value={form.datos.hora_registro} onChange={(e) => setForm({ ...form, datos: { ...form.datos, hora_registro: e.target.value } })} /></Campo>
              <Campo etiqueta="Hora de inicio"><input type="time" required value={form.datos.hora_de_inicio} onChange={(e) => setForm({ ...form, datos: { ...form.datos, hora_de_inicio: e.target.value } })} /></Campo>
            </div>
            <div className="fila-campos">
              <Campo etiqueta="Duración (minutos)" ayuda="Máximo 60"><input type="number" min={1} max={60} required value={form.datos.duracion} onChange={(e) => setForm({ ...form, datos: { ...form.datos, duracion: e.target.value } })} /></Campo>
              <Campo etiqueta="Tiempo a compensar" ayuda="Opcional (HH:MM)"><input type="time" value={form.datos.tiempo_laborar} onChange={(e) => setForm({ ...form, datos: { ...form.datos, tiempo_laborar: e.target.value } })} /></Campo>
            </div>
            <p className="nota">Topes: 1 solicitud Urgente por semana y 2 Personales por mes. Si se superan, la base de datos rechaza el registro.</p>
            <div className="botones-form">
              <button type="button" className="btn secundario" onClick={() => setForm(null)}>Cancelar</button>
              <button className="btn">Guardar</button>
            </div>
          </form>
        </Modal>
      )}
      {resolver && (
        <Modal titulo={`Resolver solicitud ${resolver.f.id_permiso}`} onCerrar={() => setResolver(null)}>
          <form className="formulario" onSubmit={async (e) => {
            e.preventDefault()
            const ok = await accion(() => api.resolverSolicitud(resolver.f.id_permiso, { estado: resolver.estado, tipo_de_permiso: resolver.tipo_de_permiso, motivo: resolver.motivo }), `Solicitud ${resolver.estado === 'Aprobado' ? 'aprobada' : 'rechazada'}`)
            if (ok) { setResolver(null); cargar() }
          }}>
            <p className="nota">{resolver.f.empleado} · {resolver.f.subtipo} · {resolver.f.fecha_solicitud} {resolver.f.hora_de_inicio} · {resolver.f.duracion} min · Destino: {resolver.f.destino}</p>
            <Campo etiqueta="Decisión">
              <select value={resolver.estado} onChange={(e) => setResolver({ ...resolver, estado: e.target.value })}><option>Aprobado</option><option>Rechazado</option></select>
            </Campo>
            <Campo etiqueta="Tipo de permiso">
              <select value={resolver.tipo_de_permiso} onChange={(e) => setResolver({ ...resolver, tipo_de_permiso: e.target.value })}>
                <option>Tardanza</option><option>Tardanza justificada</option><option>Salida anticipada</option><option>Personal</option>
              </select>
            </Campo>
            <Campo etiqueta="Motivo"><input required maxLength={150} value={resolver.motivo} onChange={(e) => setResolver({ ...resolver, motivo: e.target.value })} /></Campo>
            <div className="botones-form">
              <button type="button" className="btn secundario" onClick={() => setResolver(null)}>Cancelar</button>
              <button className="btn">Confirmar</button>
            </div>
          </form>
        </Modal>
      )}
      {comp && <Compensaciones solicitud={comp} onCerrar={() => setComp(null)} accion={accion} />}
    </>
  )
}

function Compensaciones({ solicitud, onCerrar, accion }) {
  const [bloques, setBloques] = useState([])
  const [nuevo, setNuevo] = useState({ fecha_compensacion: hoy(), hora_inicio: '17:00', hora_fin: '17:30' })
  const id = solicitud.id_permiso
  const cargar = useCallback(() => { accion(() => api.compensaciones(id)).then((r) => r && setBloques(r)) }, [id]) // eslint-disable-line
  useEffect(cargar, [cargar])
  const ejecutar = async (fn, ok) => { await accion(fn, ok); cargar() }

  return (
    <Modal titulo={`Compensación de horas · solicitud ${id}`} onCerrar={onCerrar} ancho={760}>
      <p className="nota">{solicitud.empleado} · tiempo a compensar: <strong>{solicitud.tiempo_laborar}</strong> · máximo 7 bloques.</p>
      <Tabla filas={bloques.map(({ id_compensacion, fecha_compensacion, hora_inicio, hora_fin, hrs_min, firma_colaborador, firma_administrador }) => ({ id_compensacion, fecha_compensacion, hora_inicio, hora_fin, hrs_min, colaborador: firma_colaborador ? 'Firmado' : '—', administrador: firma_administrador ? 'Firmado' : '—' }))}
        vacio="Aún no hay bloques de compensación"
        acciones={(b) => (
          <>
            {b.colaborador === '—'
              ? <button className="btn-link" onClick={() => ejecutar(() => api.firmar(b.id_compensacion, 'Colaborador'), 'Firma del colaborador registrada')}>Firma colaborador</button>
              : b.administrador === '—' && <button className="btn-link" onClick={() => ejecutar(() => api.firmar(b.id_compensacion, 'Administrador'), 'Firma del administrador registrada')}>Firma administrador</button>}
            {b.administrador === '—' && <button className="btn-link peligro" onClick={() => ejecutar(() => api.eliminarCompensacion(b.id_compensacion), 'Bloque eliminado')}>Eliminar</button>}
          </>
        )} />
      <form className="fila-campos alto" onSubmit={async (e) => { e.preventDefault(); await ejecutar(() => api.crearCompensacion(id, nuevo), 'Bloque registrado') }}>
        <Campo etiqueta="Fecha"><input type="date" required value={nuevo.fecha_compensacion} onChange={(e) => setNuevo({ ...nuevo, fecha_compensacion: e.target.value })} /></Campo>
        <Campo etiqueta="Inicio"><input type="time" required value={nuevo.hora_inicio} onChange={(e) => setNuevo({ ...nuevo, hora_inicio: e.target.value })} /></Campo>
        <Campo etiqueta="Fin"><input type="time" required value={nuevo.hora_fin} onChange={(e) => setNuevo({ ...nuevo, hora_fin: e.target.value })} /></Campo>
        <button className="btn">+ Agregar bloque</button>
      </form>
    </Modal>
  )
}

/* ============================ REPORTES ============================= */
const VALOR_PARAM = { desde: '2026-08-01', hasta: '2026-11-30', fecha: '2026-08-19', anio: 2026, top: 10 }

function Reportes({ notificar }) {
  const [catalogo, setCatalogo] = useState([])
  const [sel, setSel] = useState(null)
  const [params, setParams] = useState({})
  const [filas, setFilas] = useState(null)
  useEffect(() => { api.reportes().then(setCatalogo).catch((e) => notificar(e.message, 'error')) }, [notificar])

  const elegir = (r) => { setSel(r); setFilas(null); setParams(Object.fromEntries(r.params.map((p) => [p, VALOR_PARAM[p]]))) }
  const ejecutar = async (e) => {
    e?.preventDefault()
    try { setFilas(await api.reporte(sel.id, params)) } catch (err) { notificar(err.message, 'error') }
  }
  useEffect(() => { if (sel && !sel.params.length) ejecutar() }, [sel]) // eslint-disable-line

  return (
    <>
      <Encabezado titulo="Reportes" texto="Diez consultas sobre la base de datos, cada una ejecutada mediante un procedimiento almacenado." />
      <div className="reportes">
        <ul className="lista-reportes">
          {catalogo.map((r) => (
            <li key={r.id}>
              <button className={sel?.id === r.id ? 'activo' : ''} onClick={() => elegir(r)}>
                <span className="num">{String(r.id).padStart(2, '0')}</span>
                <span><strong>{r.nombre}</strong><small>{r.tecnica}</small></span>
              </button>
            </li>
          ))}
        </ul>
        <section className="caja">
          {!sel ? <p className="vacio">Seleccione un reporte de la lista.</p> : (
            <>
              <h3>{sel.nombre}</h3>
              <p className="tenue">{sel.descripcion}</p>
              {sel.params.length > 0 && (
                <form className="filtros" onSubmit={ejecutar}>
                  {sel.params.map((p) => (
                    <label key={p} className="en-linea">{p}
                      <input type={['desde', 'hasta', 'fecha'].includes(p) ? 'date' : 'number'} value={params[p] ?? ''} required
                             onChange={(e) => setParams({ ...params, [p]: e.target.value })} />
                    </label>
                  ))}
                  <button className="btn">Ejecutar</button>
                </form>
              )}
              {filas && <>
                <div className="filtros"><span className="tenue">{filas.length} filas</span>
                  <button className="btn secundario" onClick={() => aCSV(filas, `reporte_${sel.id}`)} disabled={!filas.length}>Exportar CSV</button></div>
                <Tabla filas={filas} vacio="El reporte no devolvió filas para esos parámetros" />
              </>}
            </>
          )}
        </section>
      </div>
    </>
  )
}

/* ============================ BITÁCORA ============================= */
function Bitacora({ notificar }) {
  const [filas, setFilas] = useState([])
  useEffect(() => { api.bitacora().then(setFilas).catch((e) => notificar(e.message, 'error')) }, [notificar])
  return (
    <>
      <Encabezado titulo="Bitácora" texto="Auditoría registrada automáticamente por los disparadores de la base de datos." />
      <Tabla filas={filas} />
    </>
  )
}
