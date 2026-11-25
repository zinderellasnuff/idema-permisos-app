import { useState } from 'react'
import { api } from '../api.js'
import { Buscador, Encabezado, Estado, Falla, Tabla, useCarga } from '../componentes.jsx'
import { fechaCorta } from '../formato.js'

const OPERACIONES = {
  INSERT: ['Alta', 'aprobado'], UPDATE: ['Cambio', 'info'], BAJA: ['Baja', 'rechazado'],
  REACTIVACION: ['Reactivación', 'info'], DELETE: ['Eliminación', 'rechazado'],
}
const TABLAS = { empleado: 'Empleado', solicitud_permiso: 'Solicitud', compensacion: 'Compensación', historial_permiso: 'Historial', firma_compensacion: 'Firma' }
const operacion = (o) => OPERACIONES[o] || [o, 'info']
const tabla = (t) => TABLAS[t] || t
export const movimiento = (m) => `${operacion(m.operacion)[0]} de ${tabla(m.tabla).toLowerCase()} ${m.id_registro}`

const COLUMNAS = [
  { id: 'fecha_hora', titulo: 'Fecha y hora', celda: (m) => <><strong>{fechaCorta(m.fecha_hora.slice(0, 10))}</strong><small>{m.fecha_hora.slice(11)}</small></> },
  { id: 'operacion', titulo: 'Operación', celda: (m) => <Estado tono={operacion(m.operacion)[1]}>{operacion(m.operacion)[0]}</Estado> },
  { id: 'tabla', titulo: 'Registro', celda: (m) => <><strong>{tabla(m.tabla)}</strong><small>{m.id_registro}</small></> },
  { id: 'detalle', titulo: 'Detalle' },
  { id: 'usuario_bd', titulo: 'Usuario' },
]

export default function Bitacora() {
  const [filas, recargar, error] = useCarga(api.bitacora, [])
  const [buscar, setBuscar] = useState('')
  const [op, setOp] = useState('')
  const texto = buscar.trim().toLowerCase()
  const visibles = filas?.filter((m) => (!op || m.operacion === op)
    && `${movimiento(m)} ${m.detalle} ${m.usuario_bd}`.toLowerCase().includes(texto))
  return (
    <>
      <Encabezado titulo="Bitácora" texto="Cada cambio queda registrado automáticamente. Se muestran los 300 movimientos más recientes." />
      <div className="filtros">
        <Buscador valor={buscar} onCambio={setBuscar} ayuda="Buscar por registro, detalle o usuario" etiqueta="Buscar en la bitácora" />
        <select value={op} onChange={(e) => setOp(e.target.value)} aria-label="Operación">
          <option value="">Todas las operaciones</option>
          {Object.entries(OPERACIONES).map(([id, [nombre]]) => <option key={id} value={id}>{nombre}</option>)}
        </select>
        {filas && <span className="tenue">{visibles.length} movimientos</span>}
      </div>
      {error && !filas ? <Falla error={error} reintentar={recargar} />
        : <Tabla filas={visibles} columnas={COLUMNAS} clave={texto + op} vacio="Ningún movimiento coincide con la búsqueda." />}
    </>
  )
}
