import { useState } from 'react'
import { api } from '../api.js'
import { Buscador, Campo, Confirmar, Encabezado, Estado, Falla, Formulario, Icono, ListaOtro, Modal, Seccion, Tabla, useAccion, useCarga } from '../componentes.jsx'

const VACIO = { dni: '', nombres: '', apellidos: '', cargo: '', area: '' }
const COLUMNAS = [
  { id: 'apellidos', titulo: 'Empleado', celda: (f) => (
    <span className="persona">
      <i aria-hidden="true">{f.nombres[0]}{f.apellidos[0]}</i>
      <span><strong>{f.nombres} {f.apellidos}</strong><small>DNI {f.dni}</small></span>
    </span>) },
  { id: 'area', titulo: 'Área', celda: (f) => <>{f.area}<small>{f.cargo}</small></> },
  { id: 'solicitudes', titulo: 'Solicitudes', num: true },
  { id: 'activo', titulo: 'Estado', celda: (f) => <Estado tono={f.activo ? 'aprobado' : 'baja'}>{f.activo ? 'Activo' : 'Baja'}</Estado> },
]

export default function Empleados({ notificar, alCambiar, opciones }) {
  const [buscar, setBuscar] = useState('')
  const [soloActivos, setSoloActivos] = useState(!!opciones?.activos)
  const [form, setForm] = useState(null) // {datos, nuevo}
  const [baja, setBaja] = useState(null)
  const [filas, recargar, error] = useCarga(() => api.empleados({ buscar, solo_activos: soloActivos ? 1 : 0 }), [buscar, soloActivos], buscar ? 250 : 0)
  const accion = useAccion(notificar, alCambiar)

  const guardar = async (datos) => {
    const { dni, ...resto } = datos
    await (form.nuevo
      ? accion(() => api.crearEmpleado(datos), 'Empleado registrado', true)
      : accion(() => api.editarEmpleado(dni, resto), 'Empleado actualizado', true))
    setForm(null)
    recargar()
  }
  const darBaja = async () => {
    await accion(() => api.bajaEmpleado(baja.dni), 'Empleado dado de baja', true)
    setBaja(null)
    recargar()
  }
  const reactivar = async (f) => { if (await accion(() => api.reactivarEmpleado(f.dni), 'Empleado reactivado')) recargar() }

  return (
    <>
      <Encabezado titulo="Empleados" texto="Personal que puede solicitar permisos. Quien se da de baja conserva su historial.">
        <button className="btn" onClick={() => setForm({ datos: VACIO, nuevo: true })}><Icono de="mas" /> Nuevo empleado</button>
      </Encabezado>
      <div className="filtros">
        <Buscador valor={buscar} onCambio={setBuscar} ayuda="Buscar por DNI, nombre o área" etiqueta="Buscar empleados" />
        <label className="check"><input type="checkbox" checked={soloActivos} onChange={(e) => setSoloActivos(e.target.checked)} /> Solo activos</label>
        {filas && <span className="tenue">{filas.length} {filas.length === 1 ? 'empleado' : 'empleados'}</span>}
      </div>
      {error && !filas ? <Falla error={error} reintentar={recargar} /> : (
        <Tabla
          filas={filas} columnas={COLUMNAS} clave={buscar + soloActivos}
          vacio={<>Ningún empleado coincide con la búsqueda. <button className="btn-link" onClick={() => { setBuscar(''); setSoloActivos(false) }}>Limpiar filtros</button></>}
          resaltar={(f) => (f.activo ? '' : 'fila-baja')}
          acciones={(f) => (
            <>
              <button className="btn-link" onClick={() => setForm({ datos: { dni: f.dni, nombres: f.nombres, apellidos: f.apellidos, cargo: f.cargo, area: f.area }, nuevo: false })}>Editar</button>
              {f.activo
                ? <button className="btn-link peligro" onClick={() => setBaja(f)}>Dar de baja</button>
                : <button className="btn-link" onClick={() => reactivar(f)}>Reactivar</button>}
            </>
          )}
        />
      )}
      {form && <FormEmpleado {...form} guardar={guardar} onCerrar={() => setForm(null)} />}
      {baja && (
        <Confirmar titulo={`¿Dar de baja a ${baja.nombres} ${baja.apellidos}?`} boton="Dar de baja" onSi={darBaja} onCerrar={() => setBaja(null)}>
          Ya no podrá registrar solicitudes. Su historial se conserva y puedes reactivarlo cuando quieras.
        </Confirmar>
      )}
    </>
  )
}

const NOMBRE = "[\\p{L}]+([ '.\\-]+[\\p{L}]+)*\\.?"
const NOMBRE_AYUDA = 'Usa solo letras, espacios, guion o apóstrofo'
const ordenado = (t) => t.trim().replace(/\s+/g, ' ')

function FormEmpleado({ datos, nuevo, guardar, onCerrar }) {
  const [d, setD] = useState(datos)
  const poner = (k, v) => setD((x) => ({ ...x, [k]: v }))
  const [areas] = useCarga(api.areas, [])
  const [todos] = useCarga(() => api.empleados({}), [])
  const cargos = todos && [...new Set(todos.map((e) => e.cargo))].sort((a, b) => a.localeCompare(b, 'es'))
  const repetido = nuevo && d.dni.length === 8 && todos?.find((e) => e.dni === d.dni)
  const reglaDni = !repetido ? '' : `Ya es el DNI de ${repetido.nombres} ${repetido.apellidos}${repetido.activo ? '' : '. Está de baja: reactívalo desde la lista'}`
  return (
    <Modal titulo={nuevo ? 'Nuevo empleado' : 'Editar empleado'} onCerrar={onCerrar} ancho={620}>
      <Formulario boton={nuevo ? 'Registrar empleado' : 'Guardar cambios'}
                  onGuardar={() => guardar(Object.fromEntries(Object.entries(d).map(([k, v]) => [k, ordenado(v)])))}>
        <Seccion titulo="Datos personales">
          <Campo etiqueta="DNI" ayuda={nuevo ? 'No se puede cambiar después' : 'El DNI no se puede cambiar'} regla={reglaDni} cuenta={nuevo && `${d.dni.length} de 8`}>
            <input required pattern="\d{8}" title="El DNI tiene 8 dígitos" inputMode="numeric" autoComplete="off" maxLength={8} disabled={!nuevo}
                   value={d.dni} onChange={(e) => poner('dni', e.target.value.replace(/\D/g, ''))} />
          </Campo>
          <div className="fila-campos">
            <Campo etiqueta="Nombres"><input required pattern={NOMBRE} title={NOMBRE_AYUDA} autoComplete="off" maxLength={50} value={d.nombres} onChange={(e) => poner('nombres', e.target.value)} onBlur={() => poner('nombres', ordenado(d.nombres))} /></Campo>
            <Campo etiqueta="Apellidos"><input required pattern={NOMBRE} title={NOMBRE_AYUDA} autoComplete="off" maxLength={50} value={d.apellidos} onChange={(e) => poner('apellidos', e.target.value)} onBlur={() => poner('apellidos', ordenado(d.apellidos))} /></Campo>
          </div>
        </Seccion>
        <Seccion titulo="Puesto">
          <div className="fila-campos">
            <ListaOtro etiqueta="Cargo" lista={cargos} valor={d.cargo} max={30} otro="Otro cargo…" onCambio={(v) => poner('cargo', v)} />
            <ListaOtro etiqueta="Área" lista={areas} valor={d.area} max={30} otro="Otra área…" onCambio={(v) => poner('area', v)} />
          </div>
        </Seccion>
      </Formulario>
    </Modal>
  )
}
