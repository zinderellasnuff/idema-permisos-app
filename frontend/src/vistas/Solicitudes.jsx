import { useEffect, useState } from 'react'
import { api } from '../api.js'
import { Buscador, Campo, Confirmar, Encabezado, Estado, Falla, Formulario, Icono, Modal, Opciones, Reloj, Seccion, Selector, Tabla, useAccion, useCarga, validar } from '../componentes.jsx'
import { aHora, aMinutos, ahora, destinoDe, fechaCorta, fechaRelativa, hoy, tramo } from '../formato.js'

const VACIA = () => ({ dni: '', fecha_solicitud: hoy(), hora_registro: ahora(), hora_de_inicio: aHora((Math.floor(aMinutos(ahora()) / 60) + 1) * 60), duracion: 30, subtipo: 'Urgente', dias: 1, compensar: '' })
const FILTRO = { buscar: '', estado: '', desde: '', hasta: '', incluir_anuladas: 0 }
const ESTADOS = [['', 'Todas'], ['Pendiente', 'Pendientes'], ['Aprobado', 'Aprobadas'], ['Rechazado', 'Rechazadas']]
const COLUMNAS = [
  { id: 'id_permiso', titulo: 'N.º' },
  { id: 'empleado', titulo: 'Empleado', celda: (f) => <><strong>{f.empleado}</strong><small>{f.area}</small></> },
  { id: 'fecha_solicitud', titulo: 'Permiso', celda: (f) => (
    <span className="horario">
      <Reloj inicio={f.hora_de_inicio} duracion={f.duracion} />
      <span><strong>{fechaCorta(f.fecha_solicitud)}</strong><small>{tramo(f.hora_de_inicio, f.duracion)} ({f.duracion} min)</small></span>
    </span>) },
  { id: 'subtipo', titulo: 'Tipo', celda: (f) => <>{f.subtipo}{f.tiempo_laborar && <small>Compensa {aMinutos(f.tiempo_laborar)} min</small>}</> },
  { id: 'destino', titulo: 'Aprueba' },
  { id: 'estado', titulo: 'Estado', celda: (f) => (f.activo ? <Estado>{f.estado}</Estado> : <Estado tono="baja">Anulada</Estado>) },
]
const paraEditar = (f) => ({ id: f.id_permiso, empleado: f.empleado, datos: { dni: f.dni, fecha_solicitud: f.fecha_solicitud, hora_registro: f.hora_registro, hora_de_inicio: f.hora_de_inicio, duracion: f.duracion, subtipo: f.subtipo, dias: f.dias, compensar: f.tiempo_laborar ? aMinutos(f.tiempo_laborar) : '' } })

export default function Solicitudes({ notificar, alCambiar, opciones, resumen }) {
  const [filtro, setFiltro] = useState({ ...FILTRO, estado: opciones?.estado || (opciones?.resolver ? 'Pendiente' : '') })
  const [form, setForm] = useState(null) // nueva o editar
  const [resolver, setResolver] = useState(null)
  const [anular, setAnular] = useState(null)
  const [comp, setComp] = useState(null) // solicitud cuyas compensaciones se ven
  const [filas, recargar, error] = useCarga(() => api.solicitudes(filtro), [filtro], filtro.buscar ? 250 : 0)
  const accion = useAccion(notificar, alCambiar)
  const set = (k, v) => setFiltro((x) => ({ ...x, [k]: v }))

  // Desde el panel se llega con una solicitud para resolver: se abre al cargar la lista.
  const [porAbrir, setPorAbrir] = useState(opciones?.resolver)
  useEffect(() => {
    if (!porAbrir || !filas) return
    setResolver(filas.find((f) => f.id_permiso === porAbrir) || null)
    setPorAbrir(null)
  }, [porAbrir, filas])

  const guardar = async (datos) => {
    // El tiempo a compensar se escribe en minutos y la API lo recibe como HH:MM.
    const { compensar, ...resto } = datos
    const d = { ...resto, duracion: Number(resto.duracion), dias: Number(resto.dias), tiempo_laborar: Number(compensar) ? aHora(Number(compensar)) : '' }
    await (form.id
      ? accion(() => api.editarSolicitud(form.id, d), 'Solicitud actualizada', true)
      : accion(() => api.crearSolicitud(d), 'Solicitud registrada', true))
    setForm(null)
    recargar()
  }
  const anularYa = async () => {
    await accion(() => api.anularSolicitud(anular.id_permiso), 'Solicitud anulada', true)
    setAnular(null)
    recargar()
  }
  const filtrado = JSON.stringify(filtro) !== JSON.stringify(FILTRO)

  return (
    <>
      <Encabezado titulo="Solicitudes de permiso" texto="Registra, aprueba y compensa los permisos por hora.">
        <button className="btn" onClick={() => setForm({ datos: VACIA() })}><Icono de="mas" /> Nueva solicitud</button>
      </Encabezado>
      <div className="pestanas" role="group" aria-label="Estado">
        {ESTADOS.map(([v, t]) => (
          <button key={t} aria-pressed={filtro.estado === v} onClick={() => set('estado', v)}>
            {t}{v === 'Pendiente' && resumen?.resumen.pendientes > 0 && <b className="contador">{resumen.resumen.pendientes}</b>}
          </button>
        ))}
      </div>
      <div className="filtros">
        <Buscador valor={filtro.buscar} onCambio={(v) => set('buscar', v)} ayuda="Buscar por N.º, DNI, empleado o área" etiqueta="Buscar solicitudes" />
        <label className="en-linea">Desde <input type="date" value={filtro.desde} max={filtro.hasta || undefined} onChange={(e) => set('desde', e.target.value)} /></label>
        <label className="en-linea">Hasta <input type="date" value={filtro.hasta} min={filtro.desde || undefined} onChange={(e) => set('hasta', e.target.value)} /></label>
        <label className="check"><input type="checkbox" checked={!!filtro.incluir_anuladas} onChange={(e) => set('incluir_anuladas', e.target.checked ? 1 : 0)} /> Ver anuladas</label>
        {filas && <span className="tenue">{filas.length} {filas.length === 1 ? 'solicitud' : 'solicitudes'}</span>}
        {filtrado && <button className="btn-link" onClick={() => setFiltro(FILTRO)}>Limpiar filtros</button>}
      </div>
      {error && !filas ? <Falla error={error} reintentar={recargar} /> : (
        <Tabla
          filas={filas} columnas={COLUMNAS} clave={JSON.stringify(filtro)}
          vacio="Ninguna solicitud coincide con los filtros."
          resaltar={(f) => (f.activo ? '' : 'fila-baja')}
          acciones={(f) => f.activo ? (
            <>
              {f.estado === 'Pendiente' && <>
                <button className="btn chico" onClick={() => setResolver(f)}>Resolver</button>
                <button className="btn-link" onClick={() => setForm(paraEditar(f))}>Editar</button>
              </>}
              {f.estado === 'Aprobado' && f.tiempo_laborar && <button className="btn secundario chico" onClick={() => setComp(f)}>Compensación</button>}
              <button className="btn-link peligro" onClick={() => setAnular(f)}>Anular</button>
            </>
          ) : null}
        />
      )}
      {form && <FormSolicitud {...form} guardar={guardar} onCerrar={() => setForm(null)} />}
      {resolver && <Resolver solicitud={resolver} onCerrar={() => setResolver(null)} accion={accion} alTerminar={() => { setResolver(null); recargar() }} />}
      {anular && (
        <Confirmar titulo={`¿Anular la solicitud ${anular.id_permiso}?`} boton="Anular solicitud" onSi={anularYa} onCerrar={() => setAnular(null)}>
          Permiso de {anular.empleado}, {fechaCorta(anular.fecha_solicitud)}. Dejará de contar para los topes y no se puede reactivar.
        </Confirmar>
      )}
      {comp && <Compensaciones solicitud={comp} onCerrar={() => setComp(null)} accion={accion} />}
    </>
  )
}

const DURACIONES = [15, 20, 30, 45, 60]

function FormSolicitud({ id, empleado, datos, guardar, onCerrar }) {
  const [d, setD] = useState(datos)
  const [compensa, setCompensa] = useState(!!datos.compensar)
  const cambiar = (k, v) => setD((x) => ({ ...x, [k]: v }))
  const set = (k) => (e) => cambiar(k, e.target.value)
  const [empleados] = useCarga(() => (id ? Promise.resolve([]) : api.empleados({ solo_activos: 1 })), [])
  // Aviso previo del tope (reportes 2 y 3, misma regla que el disparador). Al editar no aplica: ya cuenta la propia solicitud.
  const [topes] = useCarga(async () => {
    if (id || !d.fecha_solicitud) return null
    const [semana, mes] = await Promise.all([2, 3].map((n) => api.reporte(n, { fecha: d.fecha_solicitud })))
    return { Urgente: semana, Personal: mes }
  }, [d.fecha_solicitud])
  const libres = (tipo) => topes?.[tipo].find((t) => t.dni === d.dni)?.disponibles
  const ayuda = (tipo, regla) => {
    const n = libres(tipo)
    return n === undefined ? regla : n > 0 ? `${regla}. Le ${n === 1 ? 'queda 1' : `quedan ${n}`}.` : `${regla}. Ya no le quedan.`
  }
  const agotado = libres(d.subtipo) === 0
  const pasaDia = aMinutos(d.hora_de_inicio) + Number(d.duracion) > 1440
  const completo = d.hora_de_inicio && d.hora_registro && d.fecha_solicitud && d.duracion > 0 && d.duracion <= 60
  const opciones = id ? [{ valor: d.dni, texto: empleado, detalle: '' }] : (empleados || []).map((e) => ({ valor: e.dni, texto: `${e.apellidos}, ${e.nombres}`, detalle: `${e.area}, DNI ${e.dni}` }))
  return (
    <Modal titulo={id ? `Editar solicitud ${id}` : 'Nueva solicitud de permiso'} onCerrar={onCerrar} ancho={700}>
      <Formulario boton={id ? 'Guardar cambios' : 'Registrar solicitud'} onGuardar={() => guardar({ ...d, compensar: compensa ? d.compensar : '' })}>
        <Seccion titulo="Quién lo pide">
          <Campo etiqueta="Empleado" ayuda={id ? 'El empleado no se puede cambiar' : ''}>
            <Selector opciones={opciones} valor={d.dni} onCambio={(v) => cambiar('dni', v)} deshabilitado={!!id} ayuda="Escribe un nombre, DNI o área" />
          </Campo>
          <Opciones etiqueta="Tipo" nombre="subtipo" valor={d.subtipo} onCambio={(v) => cambiar('subtipo', v)} opciones={[
            ['Urgente', 'Urgente', ayuda('Urgente', '1 por semana'), libres('Urgente') === 0 ? 'agotada' : ''],
            ['Personal', 'Personal', ayuda('Personal', '2 por mes'), libres('Personal') === 0 ? 'agotada' : ''],
          ]} regla={agotado ? `Ya usó su tope de permisos de tipo ${d.subtipo} en ese período` : ''} />
        </Seccion>
        <Seccion titulo="Cuándo">
          <div className="fila-campos">
            <Campo etiqueta="Fecha del permiso" ayuda={d.fecha_solicitud && fechaRelativa(d.fecha_solicitud)}><input type="date" required value={d.fecha_solicitud} onChange={set('fecha_solicitud')} /></Campo>
            <Campo etiqueta="Hora de registro" ayuda="Cuándo lo pidió"><input type="time" required value={d.hora_registro} onChange={set('hora_registro')} /></Campo>
            <Campo etiqueta="Hora de inicio" ayuda="Cuándo empieza" regla={d.hora_registro > d.hora_de_inicio ? 'Debe ser después del registro' : pasaDia ? 'Debe terminar el mismo día' : ''}><input type="time" required value={d.hora_de_inicio} onChange={set('hora_de_inicio')} /></Campo>
          </div>
        </Seccion>
        <Seccion titulo="Cuánto tiempo">
          <div className="fila-campos">
            <Campo etiqueta="Minutos" ayuda="De 1 a 60"><input type="number" min={1} max={60} step={1} required value={d.duracion} onChange={set('duracion')} /></Campo>
            <Campo etiqueta="Días" ayuda="Días que abarca"><input type="number" min={1} max={30} step={1} required value={d.dias} onChange={set('dias')} /></Campo>
            <div className="rapidas" role="group" aria-label="Duraciones frecuentes">
              {DURACIONES.map((m) => <button key={m} type="button" aria-pressed={Number(d.duracion) === m} onClick={() => cambiar('duracion', m)}>{m} min</button>)}
            </div>
          </div>
          <div className="fila-campos compensa">
            <label className="check">
              <input type="checkbox" checked={compensa} onChange={(e) => { setCompensa(e.target.checked); if (e.target.checked && !d.compensar) cambiar('compensar', d.duracion) }} />
              Recuperará el tiempo
            </label>
            {compensa && <Campo etiqueta="Minutos a compensar"><input type="number" min={1} max={1439} step={1} required value={d.compensar} onChange={set('compensar')} /></Campo>}
          </div>
        </Seccion>
        {completo && (
          <div className={`resumen ${agotado ? 'con-error' : ''}`} aria-live="polite">
            <Reloj inicio={d.hora_de_inicio} duracion={d.duracion} tamano={56} />
            <p>
              <strong>{fechaCorta(d.fecha_solicitud)}, de {tramo(d.hora_de_inicio, d.duracion)}</strong>
              {agotado
                ? <span>Ya usó su tope de permisos de tipo {d.subtipo} en ese período. No se podrá registrar.</span>
                : <span>La aprueba {destinoDe(d.hora_registro, d.hora_de_inicio) === 'RRHH' ? 'RRHH, porque se registra con 20 minutos o menos de anticipación.' : 'el líder de área, porque se registra con más de 20 minutos de anticipación.'}</span>}
            </p>
          </div>
        )}
      </Formulario>
    </Modal>
  )
}

function Resolver({ solicitud: s, onCerrar, accion, alTerminar }) {
  const [d, setD] = useState({ estado: 'Aprobado', tipo_de_permiso: s.subtipo === 'Urgente' ? 'Tardanza justificada' : 'Personal', motivo: '' })
  const aprueba = d.estado === 'Aprobado'
  const guardar = async () => {
    await accion(() => api.resolverSolicitud(s.id_permiso, { ...d, motivo: d.motivo.trim() }), `Solicitud ${aprueba ? 'aprobada' : 'rechazada'}`, true)
    alTerminar()
  }
  return (
    <Modal titulo={`Resolver solicitud ${s.id_permiso}`} onCerrar={onCerrar}>
      <Formulario onGuardar={guardar} boton={aprueba ? 'Aprobar solicitud' : 'Rechazar solicitud'} peligro={!aprueba}>
        <div className="resumen">
          <Reloj inicio={s.hora_de_inicio} duracion={s.duracion} tamano={56} />
          <p>
            <strong>{s.empleado}</strong>
            <span>{s.subtipo}, {fechaCorta(s.fecha_solicitud)}, {tramo(s.hora_de_inicio, s.duracion)} ({s.duracion} min)</span>
            <span>Le toca aprobar a: {s.destino}</span>
          </p>
        </div>
        <Opciones etiqueta="Decisión" nombre="decision" valor={d.estado} onCambio={(estado) => setD({ ...d, estado })}
                  opciones={[['Aprobado', 'Aprobar', '', 'si'], ['Rechazado', 'Rechazar', '', 'no']]} />
        <Campo etiqueta="Tipo de permiso">
          <select value={d.tipo_de_permiso} onChange={(e) => setD({ ...d, tipo_de_permiso: e.target.value })}>
            <option>Tardanza</option><option>Tardanza justificada</option><option>Salida anticipada</option><option>Personal</option>
          </select>
        </Campo>
        <Campo etiqueta="Motivo" ayuda="Razón que declaró el colaborador. Queda en el historial." cuenta={`${d.motivo.length} de 150`} regla={d.motivo && !d.motivo.trim() ? 'Completa este campo' : ''}>
          <textarea required rows={3} maxLength={150} value={d.motivo} onChange={(e) => setD({ ...d, motivo: e.target.value })} />
        </Campo>
      </Formulario>
    </Modal>
  )
}

function Compensaciones({ solicitud: s, onCerrar, accion }) {
  const id = s.id_permiso
  const [bloques, recargar, error] = useCarga(() => api.compensaciones(id), [id])
  // hora_fin vacía = propuesta automática: lo que falta por compensar.
  const [nuevo, setNuevo] = useState({ fecha_compensacion: hoy(), hora_inicio: '17:00', hora_fin: null })
  const [borrar, setBorrar] = useState(null)
  const [ocupado, setOcupado] = useState(false)
  const ejecutar = async (fn, ok) => { setOcupado(true); const r = await accion(fn, ok); setOcupado(false); recargar(); return r }
  const total = aMinutos(s.tiempo_laborar)
  const hecho = (bloques || []).reduce((n, b) => n + aMinutos(b.hrs_min), 0)
  const completo = hecho >= total
  const lleno = bloques?.length >= 7
  const bloque = { ...nuevo, hora_fin: nuevo.hora_fin ?? aHora(aMinutos(nuevo.hora_inicio) + total - hecho) }
  const largo = aMinutos(bloque.hora_fin) - aMinutos(bloque.hora_inicio)
  const cruza = bloques?.find((b) => b.fecha_compensacion === bloque.fecha_compensacion && b.hora_inicio < bloque.hora_fin && bloque.hora_inicio < b.hora_fin)
  const reglaFin = largo <= 0 ? 'Debe ser después del inicio' : largo > total - hecho ? `Solo faltan ${total - hecho} min` : ''
  const set = (k) => (e) => setNuevo({ ...nuevo, [k]: e.target.value })
  const agregar = async (e) => {
    e.preventDefault()
    if (validar(e.currentTarget) && await ejecutar(() => api.crearCompensacion(id, bloque), 'Bloque registrado')) setNuevo({ ...nuevo, hora_fin: null })
  }
  const firma = (f) => (f ? <span className="firmado"><Icono de="ok" /> Firmado</span> : <span className="tenue">Falta</span>)
  const columnas = [
    { id: 'fecha_compensacion', titulo: 'Bloque', celda: (b) => <><strong>{fechaCorta(b.fecha_compensacion)}</strong><small>{b.hora_inicio} a {b.hora_fin}</small></> },
    { id: 'hrs_min', titulo: 'Duración', celda: (b) => `${aMinutos(b.hrs_min)} min` },
    { id: 'firma_colaborador', titulo: 'Colaborador', celda: (b) => firma(b.firma_colaborador) },
    { id: 'firma_administrador', titulo: 'Administrador', celda: (b) => firma(b.firma_administrador) },
  ]
  return (
    <Modal titulo={`Compensación de la solicitud ${id}`} onCerrar={onCerrar} ancho={800}>
      <div className="resumen avance">
        <p>
          <strong>{s.empleado}</strong>
          <span>{completo ? `Compensó los ${total} minutos del permiso.` : `Faltan ${total - hecho} de ${total} minutos. Bloques usados: ${bloques?.length ?? 0} de 7.`}</span>
        </p>
        <i className="barra" aria-hidden="true"><b style={{ width: `${Math.min(100, total ? hecho / total * 100 : 0)}%` }} /></i>
      </div>
      {error && !bloques ? <Falla error={error} reintentar={recargar} /> : (
        <Tabla filas={bloques} columnas={columnas} vacio="Aún no hay bloques. Agrega el primero abajo."
          acciones={(b) => !b.firma_administrador && (
            <>
              {b.firma_colaborador
                ? <button className="btn secundario chico" disabled={ocupado} onClick={() => ejecutar(() => api.firmar(b.id_compensacion, 'Administrador'), 'Firma del administrador registrada')}>Firma administrador</button>
                : <button className="btn secundario chico" disabled={ocupado} onClick={() => ejecutar(() => api.firmar(b.id_compensacion, 'Colaborador'), 'Firma del colaborador registrada')}>Firma colaborador</button>}
              <button className="btn-link peligro" onClick={() => setBorrar(b)}>Eliminar</button>
            </>
          )} />
      )}
      {!completo && !lleno && (
        <form className="nuevo-bloque" noValidate onSubmit={agregar}>
          <Campo etiqueta="Fecha" regla={bloque.fecha_compensacion && bloque.fecha_compensacion < s.fecha_solicitud ? `El permiso es del ${fechaCorta(s.fecha_solicitud)}` : ''}><input type="date" required value={bloque.fecha_compensacion} onChange={set('fecha_compensacion')} /></Campo>
          <Campo etiqueta="Inicio" regla={cruza ? 'Se cruza con otro bloque' : ''}><input type="time" required value={bloque.hora_inicio} onChange={set('hora_inicio')} /></Campo>
          <Campo etiqueta="Fin" ayuda={largo > 0 && `Bloque de ${largo} min`} regla={reglaFin}><input type="time" required value={bloque.hora_fin} onChange={set('hora_fin')} /></Campo>
          <button className="btn" disabled={ocupado}><Icono de="mas" /> Agregar bloque</button>
        </form>
      )}
      {borrar && (
        <Confirmar titulo="¿Eliminar este bloque?" boton="Eliminar bloque" onCerrar={() => setBorrar(null)}
                   onSi={async () => { await ejecutar(() => api.eliminarCompensacion(borrar.id_compensacion), 'Bloque eliminado'); setBorrar(null) }}>
          {fechaCorta(borrar.fecha_compensacion)}, {borrar.hora_inicio} a {borrar.hora_fin}. Esto no se puede deshacer.
        </Confirmar>
      )}
    </Modal>
  )
}
