import { useCallback, useEffect, useState } from 'react'
import { api } from './api.js'
import { Aviso, Icono, Reloj, useCarga } from './componentes.jsx'
import Panel from './vistas/Panel.jsx'
import Empleados from './vistas/Empleados.jsx'
import Solicitudes from './vistas/Solicitudes.jsx'
import Reportes from './vistas/Reportes.jsx'
import Bitacora from './vistas/Bitacora.jsx'

const VISTAS = {
  panel: ['Panel', Panel],
  empleados: ['Empleados', Empleados],
  solicitudes: ['Solicitudes', Solicitudes],
  reportes: ['Reportes', Reportes],
  bitacora: ['Bitácora', Bitacora],
}
const deLaURL = () => (Object.hasOwn(VISTAS, location.hash.slice(1)) ? location.hash.slice(1) : 'panel')

export default function App() {
  // La vista activa se guarda en la URL (#solicitudes, #reportes…) para poder enlazarla.
  const [{ vista, opciones }, setLugar] = useState(() => ({ vista: deLaURL() }))
  const irA = useCallback((v, op) => { setLugar({ vista: v, opciones: op }); history.pushState(null, '', `#${v}`); window.scrollTo(0, 0) }, [])
  useEffect(() => {
    const alCambiar = () => setLugar({ vista: deLaURL() })
    window.addEventListener('popstate', alCambiar) // también cubre los cambios de #
    return () => window.removeEventListener('popstate', alCambiar)
  }, [])
  const [aviso, setAviso] = useState(null)
  const notificar = useCallback((texto, tipo = 'ok') => setAviso({ texto, tipo, id: Date.now() }), [])
  const cerrarAviso = useCallback(() => setAviso(null), [])
  // El resumen vive aquí porque el menú muestra cuántas solicitudes faltan resolver.
  const [resumen, recargarResumen, errorResumen] = useCarga(api.panel, [vista])
  const pendientes = resumen?.resumen.pendientes
  const Vista = VISTAS[vista][1]
  return (
    <div className="app">
      <aside className="lateral">
        <div className="marca">
          <Reloj inicio="08:00" duracion={25} tamano={40} />
          <div><strong>Sistema</strong><span>Permisos por hora</span></div>
        </div>
        <nav aria-label="Módulos">
          {Object.entries(VISTAS).map(([id, [nombre]]) => (
            <button key={id} className={vista === id ? 'activo' : ''} onClick={() => irA(id)} aria-current={vista === id ? 'page' : undefined}>
              <Icono de={id} /><span>{nombre}</span>
              {id === 'solicitudes' && pendientes > 0 && <b className="contador" title={`${pendientes} pendientes`}>{pendientes}</b>}
            </button>
          ))}
        </nav>
      </aside>
      <main className="contenido">
        <Vista key={vista} notificar={notificar} irA={irA} opciones={opciones}
               resumen={resumen} errorResumen={errorResumen} alCambiar={recargarResumen} />
      </main>
      <Aviso aviso={aviso} onCerrar={cerrarAviso} />
    </div>
  )
}
