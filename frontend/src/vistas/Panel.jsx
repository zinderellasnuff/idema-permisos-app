import { api } from '../api.js'
import { Cargando, Encabezado, Falla, Reloj, Vacio, useCarga } from '../componentes.jsx'
import { fechaCorta, fechaLarga, fechaRelativa, hoy, tramo } from '../formato.js'
import { movimiento } from './Bitacora.jsx'

const VISIBLES = 5

export default function Panel({ irA, resumen: datos, errorResumen, alCambiar }) {
  const [pendientes, recargar, error] = useCarga(() => api.solicitudes({ estado: 'Pendiente' }), [])
  if (!datos || !pendientes) {
    const falla = errorResumen || error
    return falla ? <Falla error={falla} reintentar={() => { alCambiar(); recargar() }} /> : <Cargando />
  }
  const r = datos.resumen
  const cola = [...pendientes].reverse() // la más antigua primero
  const estados = [
    ['Aprobadas', r.aprobadas, 'Aprobado'],
    ['Rechazadas', r.rechazadas, 'Rechazado'],
    ['Pendientes', r.pendientes, 'Pendiente'],
  ]
  const maxArea = Math.max(...datos.pendientes_por_area.map((a) => a.pendientes), 1)
  return (
    <>
      <Encabezado titulo="Panel" texto={fechaLarga(hoy())} />
      <div className="panel">
        <div>
        <section className="caja">
          <h2>{r.pendientes === 1 ? '1 solicitud por resolver' : `${r.pendientes} solicitudes por resolver`}</h2>
          {!cola.length && <Vacio>Todo al día. Las solicitudes nuevas aparecerán aquí.</Vacio>}
          <ul className="cola">
            {cola.slice(0, VISIBLES).map((s) => (
              <li key={s.id_permiso}>
                <Reloj inicio={s.hora_de_inicio} duracion={s.duracion} tamano={44} />
                <div>
                  <strong>{s.empleado}</strong>
                  <span>{s.area}. {s.subtipo}, {s.duracion}{'\u00a0'}min</span>
                </div>
                <div className="cuando">
                  <span>{fechaCorta(s.fecha_solicitud)}, {tramo(s.hora_de_inicio, s.duracion)}</span>
                  <span className={s.fecha_solicitud < hoy() ? 'atrasada' : ''}>{fechaRelativa(s.fecha_solicitud)}</span>
                </div>
                <button className="btn secundario" onClick={() => irA('solicitudes', { resolver: s.id_permiso })}>Resolver</button>
              </li>
            ))}
          </ul>
          {cola.length > VISIBLES && <button className="btn-link" onClick={() => irA('solicitudes', { estado: 'Pendiente' })}>Ver las {cola.length} pendientes</button>}
        </section>
        <section className="caja">
          <h2>Últimos movimientos</h2>
          <ul className="movimientos">
            {datos.bitacora.map((m) => (
              <li key={m.id_bitacora}>
                <span>{movimiento(m)}</span>
                <small>{m.detalle}</small>
                <time>{fechaCorta(m.fecha_hora.slice(0, 10))}, {m.fecha_hora.slice(11, 16)}</time>
              </li>
            ))}
          </ul>
          <button className="btn-link" onClick={() => irA('bitacora')}>Ver la bitácora</button>
        </section>
        </div>
        <div>
        <section className="caja">
          <h2>{r.solicitudes} solicitudes registradas</h2>
          <div className="proporcion" aria-hidden="true">
            {estados.map(([t, v, e]) => v > 0 && <i key={t} className={`tono-${e.toLowerCase()}`} style={{ flexGrow: v }} />)}
          </div>
          <div className="tarjetas">
            {estados.map(([t, v, e]) => (
              <button key={t} className="tarjeta" onClick={() => irA('solicitudes', { estado: e })}>
                <i className={`tono-${e.toLowerCase()}`} aria-hidden="true" /><span>{t}</span><span className="valor">{v}</span>
              </button>
            ))}
            <button className="tarjeta separada" onClick={() => irA('empleados', { activos: true })}><span>Empleados activos</span><span className="valor">{r.empleados_activos}</span></button>
            <button className="tarjeta" onClick={() => irA('reportes', { id: 5 })}><span>Compensaciones sin firma del administrador</span><span className="valor">{r.compensaciones_sin_firma}</span></button>
          </div>
        </section>
        <section className="caja">
          <h2>Pendientes por área</h2>
          {!datos.pendientes_por_area.length && <Vacio>Ningún área tiene solicitudes pendientes.</Vacio>}
          <ul className="barras">
            {datos.pendientes_por_area.map((a) => (
              <li key={a.area}>
                <span>{a.area}</span><b>{a.pendientes}</b>
                <i><b style={{ width: `${a.pendientes / maxArea * 100}%` }} /></i>
                <small>La más antigua: {fechaCorta(a.mas_antigua)}</small>
              </li>
            ))}
          </ul>
        </section>
        </div>
      </div>
    </>
  )
}
