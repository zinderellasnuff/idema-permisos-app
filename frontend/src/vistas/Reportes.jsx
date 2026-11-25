import { useEffect, useState } from 'react'
import { api } from '../api.js'
import { Campo, Cargando, Encabezado, Falla, Icono, Tabla, aCSV, useCarga, validar } from '../componentes.jsx'
import { haceDias, hoy, titulo } from '../formato.js'

const inicial = () => ({ desde: haceDias(90), hasta: hoy(), fecha: hoy(), anio: new Date().getFullYear(), top: 10 })

export default function Reportes({ notificar, opciones }) {
  const [catalogo, recargar, error] = useCarga(api.reportes, [])
  const [id, setId] = useState(opciones?.id || 1)
  const [params, setParams] = useState(inicial)
  const [filas, setFilas] = useState(null)
  const sel = catalogo?.find((r) => r.id === id)

  // El reporte se ejecuta al elegirlo; "Ejecutar" lo repite con otros parámetros.
  const [pedido, setPedido] = useState(0)
  useEffect(() => {
    if (!sel) return
    let vigente = true
    setFilas(null)
    api.reporte(sel.id, Object.fromEntries(sel.params.map((p) => [p, params[p]])))
      .then((f) => vigente && setFilas(f), (e) => { if (vigente) { notificar(e.message, 'error'); setFilas([]) } })
    return () => { vigente = false }
  }, [sel, pedido]) // eslint-disable-line

  if (!catalogo) return error ? <Falla error={error} reintentar={recargar} /> : <Cargando />
  return (
    <>
      <Encabezado titulo="Reportes" texto="Elige una consulta. El resultado se puede ordenar por columna y abrir en Excel." />
      <div className="reportes">
        <ul className="lista-reportes">
          {catalogo.map((r) => (
            <li key={r.id}>
              <button className={id === r.id ? 'activo' : ''} aria-current={id === r.id ? 'true' : undefined} onClick={() => setId(r.id)}>
                <span className="num">{r.id}</span><span>{r.nombre}</span>
              </button>
            </li>
          ))}
        </ul>
        <section className="caja">
          <div className="titulo-reporte">
            <div>
              <h2>{sel.nombre}</h2>
              <p>{sel.descripcion}</p>
            </div>
            <button className="btn secundario" onClick={() => aCSV(filas, `reporte_${sel.id}`)} disabled={!filas?.length}><Icono de="descargar" /> Exportar CSV</button>
          </div>
          {sel.params.length > 0 && (
            <form className="parametros" noValidate onSubmit={(e) => { e.preventDefault(); if (validar(e.currentTarget)) setPedido(pedido + 1) }}>
              {sel.params.map((p) => (
                <Campo key={p} etiqueta={titulo(p)} regla={p === 'hasta' && params.desde > params.hasta ? 'Debe ser posterior a Desde' : ''}>
                  <input type={['desde', 'hasta', 'fecha'].includes(p) ? 'date' : 'number'} value={params[p] ?? ''} required
                         min={p === 'top' ? 1 : p === 'anio' ? 2000 : undefined} max={p === 'top' ? 100 : p === 'anio' ? 2100 : undefined}
                         onChange={(e) => setParams({ ...params, [p]: e.target.value })} />
                </Campo>
              ))}
              <button className="btn">Ejecutar</button>
            </form>
          )}
          <Tabla filas={filas} clave={`${sel.id}-${pedido}`} vacio="No hay datos para esos parámetros. Prueba con otro período." />
          {filas?.length > 0 && <p className="tenue pie-reporte">{filas.length} {filas.length === 1 ? 'fila' : 'filas'}. Consulta con {sel.tecnica}.</p>}
        </section>
      </div>
    </>
  )
}
