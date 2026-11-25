import { createContext, useCallback, useContext, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { aMinutos, titulo } from './formato.js'

/* ============================== Datos ============================== */
// Carga datos y descarta respuestas viejas (por ejemplo, al escribir rápido en el buscador).
export function useCarga(fn, deps, espera = 0) {
  const [datos, setDatos] = useState(null)
  const [error, setError] = useState('')
  const [vez, setVez] = useState(0)
  useEffect(() => {
    let vigente = true
    const t = setTimeout(() => fn().then(
      (d) => { if (vigente) { setDatos(d); setError('') } },
      (e) => vigente && setError(e.message),
    ), espera)
    return () => { vigente = false; clearTimeout(t) }
  }, [...deps, vez]) // eslint-disable-line
  return [datos, useCallback(() => setVez((v) => v + 1), []), error]
}

// Ejecuta una acción del API y muestra el resultado o el mensaje de error
// que devuelve la base de datos (topes, validaciones de los disparadores, etc.).
// Con enFormulario, el error lo muestra el propio Formulario junto a sus botones.
export function useAccion(notificar, alCambiar) {
  return async (fn, ok, enFormulario) => {
    try {
      const r = await fn()
      notificar(ok)
      alCambiar?.()
      return r
    } catch (e) {
      if (enFormulario) throw e
      notificar(e.message, 'error')
      return undefined
    }
  }
}

/* ============================== Íconos ============================= */
const TRAZOS = {
  panel: 'M3 4h7v9H3zM14 4h7v5h-7zM14 13h7v7h-7zM3 17h7v3H3z',
  empleados: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM2.5 20c.5-3.6 3-5.5 6.5-5.500s6 1.9 6.5 5.500M16 4.500a3.3 3.3 0 0 1 0 6.200M18 14.800c2 .7 3.2 2.5 3.5 5.2',
  solicitudes: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3.5 2',
  reportes: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
  bitacora: 'M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01',
  mas: 'M12 5v14M5 12h14',
  buscar: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM16 16l5 5',
  cerrar: 'M6 6l12 12M18 6L6 18',
  ok: 'M5 12.500l4.5 4.500L19 7',
  alerta: 'M12 8v5M12 16.500v.01M12 3l9.5 17h-19z',
  descargar: 'M12 4v11M7 11l5 5 5-5M4 20h16',
  abajo: 'M6 9l6 6 6-6',
  izquierda: 'M15 5l-7 7 7 7',
  derecha: 'M9 5l7 7-7 7',
}
export const Icono = ({ de }) => (
  <svg className="icono" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d={TRAZOS[de]} />
  </svg>
)

// Esfera de una hora: pinta el tramo del permiso en su posición real del reloj
// (un permiso nunca pasa de 60 minutos, así que siempre cabe en una vuelta).
export function Reloj({ inicio, duracion, tamano = 34 }) {
  const punto = (min) => { const a = (min * 6 - 90) * Math.PI / 180; return `${(20 + 14 * Math.cos(a)).toFixed(2)} ${(20 + 14 * Math.sin(a)).toFixed(2)}` }
  const desde = aMinutos(inicio) % 60
  const min = Math.min(60, Math.max(0, Number(duracion) || 0))
  return (
    <svg className="reloj" width={tamano} height={tamano} viewBox="0 0 40 40" aria-hidden="true">
      <circle className="reloj-esfera" cx="20" cy="20" r="18.5" />
      {min === 60
        ? <circle className="reloj-tramo" cx="20" cy="20" r="14" />
        : <path className="reloj-tramo" d={`M20 20L${punto(desde)}A14 14 0 ${min > 30 ? 1 : 0} 1 ${punto(desde + min)}Z`} />}
      {[0, 15, 30, 45].map((m) => <path key={m} className="reloj-marca" d="M20 1.500v3" transform={`rotate(${m * 6} 20 20)`} />)}
    </svg>
  )
}

/* ============================= Ventanas ============================ */
const Ventana = createContext({}) // {intentarCerrar, setSucio} para el Formulario que está dentro
const pila = [] // ventanas abiertas: Esc solo cierra la de encima
export function Modal({ titulo: nombre, onCerrar, children, ancho = 560 }) {
  const caja = useRef(null)
  // Si hay datos escritos sin guardar, pregunta antes de cerrar.
  const [sucio, setSucio] = useState(false)
  const [descartar, setDescartar] = useState(false)
  const intentarCerrar = () => (sucio ? setDescartar(true) : onCerrar())
  const cerrar = useRef()
  cerrar.current = intentarCerrar
  useLayoutEffect(() => {
    const previo = document.activeElement
    const yo = {}
    const raiz = document.getElementById('root')
    pila.push(yo)
    raiz.inert = true // el fondo no recibe clics ni tabulador
    ;(caja.current.querySelector('form :is(input:not([type=radio]), select, textarea):enabled, [data-foco]') || caja.current.querySelector('button'))?.focus()
    const esc = (e) => e.key === 'Escape' && !e.defaultPrevented && pila.at(-1) === yo && cerrar.current()
    window.addEventListener('keydown', esc)
    return () => {
      window.removeEventListener('keydown', esc)
      pila.splice(pila.indexOf(yo), 1)
      raiz.inert = pila.length > 0
      previo?.focus?.()
    }
  }, [])
  return createPortal(
    <div className="fondo-modal">
      <div className="modal" role="dialog" aria-modal="true" aria-label={nombre} style={{ maxWidth: ancho }} ref={caja}>
        <header>
          <h2>{nombre}</h2>
          <button type="button" className="btn-icono" onClick={intentarCerrar} aria-label="Cerrar"><Icono de="cerrar" /></button>
        </header>
        <Ventana.Provider value={{ intentarCerrar, setSucio }}>{children}</Ventana.Provider>
      </div>
      {descartar && (
        <Confirmar titulo="¿Descartar los cambios?" boton="Descartar" onSi={onCerrar} onCerrar={() => setDescartar(false)} cancelar="Seguir editando">
          Lo que escribiste no se ha guardado.
        </Confirmar>
      )}
    </div>, document.body)
}

// Formulario con botones Cancelar y Guardar. Valida en español debajo de cada campo, muestra
// el rechazo de la base de datos junto a los botones y bloquea el envío doble.
export function Formulario({ onGuardar, boton = 'Guardar', cancelar = 'Cancelar', onCancelar, peligro, children }) {
  const { intentarCerrar, setSucio } = useContext(Ventana)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState('')
  const enviar = async (e) => {
    e.preventDefault()
    e.stopPropagation() // una ventana dentro de otra no debe enviar el formulario de afuera
    if (!validar(e.currentTarget)) return
    setGuardando(true)
    setError('')
    try { await onGuardar() } catch (err) { setError(err.message) } finally { setGuardando(false) }
  }
  return (
    <form className="formulario" noValidate onSubmit={enviar} onChange={() => { setSucio?.(true); setError('') }}>
      {children}
      {error && <p className="error-form" role="alert" ref={(p) => p?.scrollIntoView({ block: 'nearest' })}><Icono de="alerta" /> <span>{error}</span></p>}
      <div className="botones-form">
        <button type="button" className="btn secundario" onClick={onCancelar || intentarCerrar}>{cancelar}</button>
        <button className={`btn ${peligro ? 'peligro' : ''}`} disabled={guardando} data-foco>{guardando ? 'Guardando…' : boton}</button>
      </div>
    </form>
  )
}

// checkValidity dispara "invalid" en cada control con error: Campo lo muestra; aquí se enfoca el primero.
export function validar(form) {
  if (form.checkValidity()) return true
  form.querySelector(':is(input, select, textarea):invalid')?.focus()
  return false
}

export const Confirmar = ({ titulo: nombre, children, boton, cancelar, onSi, onCerrar }) => (
  <Modal titulo={nombre} onCerrar={onCerrar} ancho={440}>
    <Formulario onGuardar={onSi} onCancelar={onCerrar} boton={boton} cancelar={cancelar} peligro><p>{children}</p></Formulario>
  </Modal>
)

function mensaje(el) {
  const v = el.validity
  if (v.customError) return el.validationMessage
  if (v.valueMissing) return el.tagName === 'SELECT' ? 'Elige una opción' : 'Completa este campo'
  if (v.badInput) return el.type === 'number' ? 'Escribe un número' : 'Completa la fecha u hora'
  if (v.rangeUnderflow) return el.type === 'number' ? `El mínimo es ${el.min}` : 'Es anterior a lo permitido'
  if (v.rangeOverflow) return el.type === 'number' ? `El máximo es ${el.max}` : 'Es posterior a lo permitido'
  if (v.stepMismatch) return 'Escribe un número entero'
  return el.title || 'Revisa este dato'
}

// `regla` es un error calculado por el formulario (cruces entre campos); vacío si todo está bien.
export function Campo({ etiqueta, children, ayuda, regla = '', cuenta, opcional }) {
  const caja = useRef(null)
  const id = useId()
  const [error, setError] = useState('')
  const control = () => caja.current.querySelector('input, select, textarea')
  const revisar = () => setError(control().validity.valid ? '' : mensaje(control()))
  const [tocado, setTocado] = useState(false)
  useLayoutEffect(() => {
    const el = control()
    el.setCustomValidity(regla)
    if (tocado) revisar() // un cambio en otro campo puede resolver o crear el error de este
  })
  useLayoutEffect(() => {
    const el = control()
    el.setAttribute('aria-describedby', id)
    el.setAttribute('aria-invalid', String(!!error))
  })
  return (
    <div className={`campo ${error ? 'con-error' : ''}`} ref={caja}
         onInvalid={(e) => { e.preventDefault(); setTocado(true); revisar() }}
         onBlur={() => { if (control().value || error) { setTocado(true); revisar() } }}>
      <label><span>{etiqueta}</span>{opcional && <small> (opcional)</small>}{children}</label>
      <small id={id} className="bajo-campo">
        <span>{error || ayuda}</span>
        {cuenta && <span className="cuenta">{cuenta}</span>}
      </small>
    </div>
  )
}

// Lista con buscador. opciones: [{valor, texto, detalle}]
export function Selector({ opciones, valor, onCambio, ayuda, deshabilitado }) {
  const id = useId()
  const [abierto, setAbierto] = useState(false)
  const [texto, setTexto] = useState('')
  const [marcado, setMarcado] = useState(0)
  const sel = opciones.find((o) => o.valor === valor)
  const limpio = (t) => t.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
  const palabras = limpio(texto).split(/\s+/)
  const visibles = opciones.filter((o) => palabras.every((p) => limpio(`${o.texto} ${o.detalle} ${o.valor}`).includes(p)))
  const abrir = () => { if (!deshabilitado) { setTexto(''); setMarcado(0); setAbierto(true) } }
  const elegir = (o) => { if (o) onCambio(o.valor); setAbierto(false) }
  const tecla = (e) => {
    if (e.key === 'Escape' && abierto) { e.preventDefault(); setAbierto(false) }
    if (e.key === 'Enter' && abierto) { e.preventDefault(); elegir(visibles[marcado]) }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      if (!abierto) return abrir()
      setMarcado((m) => Math.max(0, Math.min(visibles.length - 1, m + (e.key === 'ArrowDown' ? 1 : -1))))
    }
  }
  return (
    <span className="selector">
      <input required role="combobox" aria-expanded={abierto} aria-controls={id} aria-autocomplete="list" autoComplete="off"
             aria-activedescendant={abierto && visibles[marcado] ? `${id}-${marcado}` : undefined}
             placeholder={sel && abierto ? sel.texto : ayuda} disabled={deshabilitado} value={abierto ? texto : sel?.texto || ''}
             onClick={abrir} onKeyDown={tecla} onBlur={() => setAbierto(false)}
             onChange={(e) => { setTexto(e.target.value); setMarcado(0); setAbierto(true) }} />
      <Icono de="abajo" />
      {abierto && (
        <ul id={id} role="listbox">
          {visibles.map((o, i) => (
            <li key={o.valor} id={`${id}-${i}`} role="option" aria-selected={i === marcado} ref={i === marcado ? (li) => li?.scrollIntoView({ block: 'nearest' }) : null}
                onMouseDown={(e) => { e.preventDefault(); elegir(o) }} onMouseMove={() => setMarcado(i)}>
              <strong>{o.texto}</strong><small>{o.detalle}</small>
            </li>
          ))}
          {!visibles.length && <li className="nada">Nadie coincide con “{texto}”</li>}
        </ul>
      )}
    </span>
  )
}

// Lista de valores existentes con salida para escribir uno nuevo (evita duplicados como "sistemas" y "Sistemas").
export function ListaOtro({ etiqueta, lista, valor, onCambio, max, otro }) {
  const [libre, setLibre] = useState(false)
  if (!lista) return <Campo etiqueta={etiqueta}><select disabled><option>Cargando…</option></select></Campo>
  const opciones = valor && !libre && !lista.includes(valor) ? [...lista, valor] : lista
  return (
    <div className="lista-otro">
      <Campo etiqueta={etiqueta}>
        <select required value={libre ? '\0' : valor} onChange={(e) => { const n = e.target.value === '\0'; setLibre(n); onCambio(n ? '' : e.target.value) }}>
          <option value="">Elige de la lista</option>
          {opciones.map((o) => <option key={o}>{o}</option>)}
          <option value={'\0'}>{otro}</option>
        </select>
      </Campo>
      {libre && (
        <Campo etiqueta={`Nombre: ${etiqueta.toLowerCase()}`} cuenta={`${valor.length} de ${max}`}
               regla={lista.some((o) => o.toLowerCase() === valor.trim().toLowerCase()) ? 'Ya está en la lista: elígelo ahí' : ''}>
          <input required pattern=".*\S.*" title="Completa este campo" maxLength={max} value={valor} onChange={(e) => onCambio(e.target.value)} autoFocus />
        </Campo>
      )}
    </div>
  )
}

export const Seccion = ({ titulo: nombre, children }) => <fieldset className="seccion"><legend>{nombre}</legend>{children}</fieldset>

// Elección entre pocas opciones visibles: [valor, título, explicación, tono]
export function Opciones({ etiqueta, nombre, opciones, valor, onCambio, regla = '' }) {
  const caja = useRef(null)
  useLayoutEffect(() => caja.current.querySelectorAll('input').forEach((i) => i.setCustomValidity(i.checked ? regla : '')))
  return (
    <fieldset className={`opciones ${regla ? 'con-error' : ''}`} ref={caja} onInvalid={(e) => e.preventDefault()}>
      <legend>{etiqueta}</legend>
      {opciones.map(([v, t, ayuda, tono = '']) => (
        <label key={v} className={`opcion ${tono}`}>
          <input type="radio" name={nombre} checked={valor === v} onChange={() => onCambio(v)} />
          <span><strong>{t}</strong>{ayuda && <small>{ayuda}</small>}</span>
        </label>
      ))}
    </fieldset>
  )
}

export const Buscador = ({ valor, onCambio, ayuda, etiqueta }) => (
  <div className="buscador">
    <Icono de="buscar" />
    <input type="search" placeholder={ayuda} value={valor} onChange={(e) => onCambio(e.target.value)} aria-label={etiqueta} />
  </div>
)

export function Encabezado({ titulo: nombre, texto, children }) {
  return (
    <header className="encabezado">
      <div>
        <h1>{nombre}</h1>
        {texto && <p>{texto}</p>}
      </div>
      <div className="botones">{children}</div>
    </header>
  )
}

export const Vacio = ({ children }) => <div className="vacio">{children}</div>
export const Falla = ({ error, reintentar }) => (
  <Vacio><p className="texto-error"><Icono de="alerta" /> {error}</p><button className="btn secundario" onClick={reintentar}>Reintentar</button></Vacio>
)
export const Cargando = () => <div className="cargando" role="status" aria-label="Cargando">{[0, 1, 2, 3, 4].map((i) => <i key={i} />)}</div>

/* ============================== Tabla ============================== */
const deClaves = (filas) => Object.keys(filas[0]).map((id) => ({ id, num: filas.every((f) => f[id] == null || typeof f[id] === 'number') && !/^id_/.test(id) }))
const paraOrdenar = (v) => (/^\d\d\/\d\d\/\d{4}$/.test(v) ? v.split('/').reverse().join('') : v ?? '')
const comparar = (a, b) => (typeof a === 'number' && typeof b === 'number' ? a - b : String(a).localeCompare(String(b), 'es', { numeric: true }))

// Columnas: [{id, titulo, celda(fila), num}]. Si no se indican, salen de las claves de la primera fila.
// `clave` identifica el filtro activo: al cambiar se vuelve a la primera página.
export function Tabla({ filas, columnas, acciones, vacio = 'Sin registros', resaltar, clave = '', porPagina = 12 }) {
  const [orden, setOrden] = useState(null)
  const [pagina, setPagina] = useState(0)
  useEffect(() => { setPagina(0); if (!columnas) setOrden(null) }, [clave]) // eslint-disable-line
  const ordenadas = useMemo(() => {
    if (!orden || !filas) return filas
    return [...filas].sort((a, b) => orden.dir * comparar(paraOrdenar(a[orden.id]), paraOrdenar(b[orden.id])))
  }, [filas, orden])
  if (!filas) return <Cargando />
  if (!filas.length) return <Vacio>{vacio}</Vacio>
  const cols = columnas || deClaves(filas)
  const ultima = Math.ceil(filas.length / porPagina) - 1
  const actual = Math.min(pagina, ultima)
  const visibles = ordenadas.slice(actual * porPagina, (actual + 1) * porPagina)
  const ordenar = (id) => { setOrden((o) => ({ id, dir: o?.id === id ? -o.dir : 1 })); setPagina(0) }
  return (
    <div className="tabla">
      <div className="tabla-scroll" tabIndex={-1}>
        <table>
          <thead>
            <tr>
              {cols.map((c) => (
                <th key={c.id} className={c.num ? 'num' : ''} aria-sort={orden?.id === c.id ? (orden.dir > 0 ? 'ascending' : 'descending') : undefined}>
                  <button onClick={() => ordenar(c.id)}>{c.titulo || titulo(c.id)}<span aria-hidden="true">{orden?.id === c.id ? (orden.dir > 0 ? '▲' : '▼') : ''}</span></button>
                </th>
              ))}
              {acciones && <th><span className="solo-lector">Acciones</span></th>}
            </tr>
          </thead>
          <tbody>
            {visibles.map((f, i) => (
              <tr key={i} className={resaltar?.(f) || ''}>
                {cols.map((c) => <td key={c.id} className={c.num ? 'num' : ''} data-col={c.titulo || titulo(c.id)}><div>{c.celda ? c.celda(f) : celda(c.id, f[c.id])}</div></td>)}
                {acciones && <td className="acciones"><div>{acciones(f)}</div></td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {ultima > 0 && (
        <nav className="paginas" aria-label="Páginas">
          <span>{actual * porPagina + 1} a {Math.min(filas.length, (actual + 1) * porPagina)} de {filas.length}</span>
          <button className="btn-icono" disabled={!actual} onClick={() => setPagina(actual - 1)} aria-label="Página anterior"><Icono de="izquierda" /></button>
          <button className="btn-icono" disabled={actual === ultima} onClick={() => setPagina(actual + 1)} aria-label="Página siguiente"><Icono de="derecha" /></button>
        </nav>
      )}
    </div>
  )
}

export const Estado = ({ children, tono }) => <span className={`chip chip-${tono || String(children).toLowerCase()}`}>{children}</span>

function celda(col, valor) {
  if (valor == null || valor === '') return <span className="tenue">Sin dato</span>
  if (col === 'estado') return <Estado>{valor}</Estado>
  if (col === 'validacion' || col === 'estado_formato') return <Estado tono={/alcanzado|Falta/.test(valor) ? 'rechazado' : 'aprobado'}>{valor}</Estado>
  if (col.startsWith('pct_')) return <span className="medida"><i><b style={{ width: `${Math.min(100, valor)}%` }} /></i>{valor}%</span>
  return String(valor)
}

/* ============================== Avisos ============================= */
export function Aviso({ aviso, onCerrar }) {
  useEffect(() => {
    if (!aviso) return
    const t = setTimeout(onCerrar, aviso.tipo === 'error' ? 9000 : 4000)
    return () => clearTimeout(t)
  }, [aviso, onCerrar])
  // Fuera de #root para que se lea aunque haya una ventana abierta.
  return createPortal(
    <div className="zona-aviso" role="status" aria-live="polite">
      {aviso && (
        <div key={aviso.id} className={`aviso aviso-${aviso.tipo}`}>
          <Icono de={aviso.tipo === 'error' ? 'alerta' : 'ok'} /><span>{aviso.texto}</span>
          <button className="btn-icono" onClick={onCerrar} aria-label="Cerrar aviso"><Icono de="cerrar" /></button>
        </div>
      )}
    </div>, document.body)
}

export function aCSV(filas, nombre) {
  const cols = Object.keys(filas[0])
  const esc = (v) => `"${String(v ?? '').replaceAll('"', '""')}"`
  const csv = [cols.map((c) => esc(titulo(c))).join(','), ...filas.map((f) => cols.map((c) => esc(f[c])).join(','))].join('\n')
  const url = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }))
  const a = Object.assign(document.createElement('a'), { href: url, download: `${nombre}.csv` })
  a.click()
  URL.revokeObjectURL(url)
}
