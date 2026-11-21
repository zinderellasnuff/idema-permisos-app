import { useEffect } from 'react'

export function Modal({ titulo, onCerrar, children, ancho = 560 }) {
  useEffect(() => {
    const esc = (e) => e.key === 'Escape' && onCerrar()
    window.addEventListener('keydown', esc)
    return () => window.removeEventListener('keydown', esc)
  }, [onCerrar])
  return (
    <div className="fondo-modal" onMouseDown={(e) => e.target === e.currentTarget && onCerrar()}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={titulo} style={{ maxWidth: ancho }}>
        <header>
          <h2>{titulo}</h2>
          <button className="btn-icono" onClick={onCerrar} aria-label="Cerrar">✕</button>
        </header>
        {children}
      </div>
    </div>
  )
}

// Tabla genérica: las columnas se toman de las claves de la primera fila.
export function Tabla({ filas, acciones, vacio = 'Sin registros', resaltar }) {
  if (!filas?.length) return <p className="vacio">{vacio}</p>
  const columnas = Object.keys(filas[0])
  return (
    <div className="tabla-scroll">
      <table>
        <thead>
          <tr>
            {columnas.map((c) => <th key={c}>{c.replaceAll('_', ' ')}</th>)}
            {acciones && <th>acciones</th>}
          </tr>
        </thead>
        <tbody>
          {filas.map((f, i) => (
            <tr key={i} className={resaltar?.(f) || ''}>
              {columnas.map((c) => <td key={c}>{celda(c, f[c])}</td>)}
              {acciones && <td className="acciones">{acciones(f)}</td>}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function celda(col, valor) {
  if (valor == null) return <span className="tenue">—</span>
  if (col === 'estado') return <span className={`chip chip-${String(valor).toLowerCase()}`}>{valor}</span>
  if (col === 'activo') return valor ? <span className="chip chip-aprobado">Activo</span> : <span className="chip chip-rechazado">Baja</span>
  if (col === 'validacion' || col === 'estado_formato')
    return <span className={`chip ${/alcanzado|Falta/.test(valor) ? 'chip-rechazado' : 'chip-aprobado'}`}>{valor}</span>
  return String(valor)
}

export function Campo({ etiqueta, children, ayuda }) {
  return (
    <label className="campo">
      <span>{etiqueta}</span>
      {children}
      {ayuda && <small>{ayuda}</small>}
    </label>
  )
}

export function Aviso({ aviso, onCerrar }) {
  useEffect(() => {
    if (!aviso) return
    const t = setTimeout(onCerrar, aviso.tipo === 'error' ? 7000 : 3500)
    return () => clearTimeout(t)
  }, [aviso, onCerrar])
  if (!aviso) return null
  return (
    <div className={`aviso aviso-${aviso.tipo}`} role={aviso.tipo === 'error' ? 'alert' : 'status'}>
      {aviso.texto}
    </div>
  )
}

export function aCSV(filas, nombre) {
  if (!filas?.length) return
  const cols = Object.keys(filas[0])
  const esc = (v) => `"${String(v ?? '').replaceAll('"', '""')}"`
  const csv = [cols.join(','), ...filas.map((f) => cols.map((c) => esc(f[c])).join(','))].join('\n')
  const url = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }))
  const a = Object.assign(document.createElement('a'), { href: url, download: `${nombre}.csv` })
  a.click()
  URL.revokeObjectURL(url)
}
