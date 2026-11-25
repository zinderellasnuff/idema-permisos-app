// Fechas y horas en formato local (toISOString usa UTC y en Perú adelanta un día desde las 19:00).
export const hoy = () => new Date().toLocaleDateString('sv')
export const haceDias = (n) => { const d = new Date(); d.setDate(d.getDate() - n); return d.toLocaleDateString('sv') }
export const ahora = () => new Date().toTimeString().slice(0, 5)

const comoFecha = (iso) => new Date(`${iso}T00:00`)
const DIA = new Intl.DateTimeFormat('es', { weekday: 'short', day: 'numeric', month: 'short' })
const DIA_ANIO = new Intl.DateTimeFormat('es', { day: 'numeric', month: 'short', year: 'numeric' })
const LARGA = new Intl.DateTimeFormat('es', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
const RELATIVA = new Intl.RelativeTimeFormat('es', { numeric: 'auto' })

export const fechaCorta = (iso) => (iso.slice(0, 4) === hoy().slice(0, 4) ? DIA : DIA_ANIO).format(comoFecha(iso)).replace(',', '')
export const fechaLarga = (iso) => LARGA.format(comoFecha(iso))
export const fechaRelativa = (iso) => RELATIVA.format(Math.round((comoFecha(iso) - comoFecha(hoy())) / 864e5), 'day')

export const aMinutos = (hhmm) => { const [h, m] = (hhmm || '0:0').split(':').map(Number); return h * 60 + m }
export const aHora = (min) => `${String(Math.floor(min / 60) % 24).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`
export const tramo = (inicio, duracion) => `${inicio} a ${aHora(aMinutos(inicio) + Number(duracion || 0))}`

// Misma regla que sp_solicitud_listar: más de 20 minutos de anticipación va al líder de área.
export const destinoDe = (registro, inicio) => (aMinutos(inicio) - aMinutos(registro) > 20 ? 'Líder de área' : 'RRHH')

const TITULOS = {
  dni: 'DNI', id_permiso: 'N.º', id_comp: 'Bloque', area: 'Área', total: 'Solicitudes', min_aprobados: 'Minutos aprobados',
  validacion: 'Validación', mas_antigua: 'Más antigua', hrs_min: 'Duración', estado_formato: 'Formato', a_compensar: 'Por compensar',
  dias: 'Días', pct_aprobacion: 'Aprobación', al_lider: 'Al líder', a_rrhh: 'A RRHH', anticipacion_prom_min: 'Anticipación promedio (min)',
  sla_lider_min: 'Plazo del líder (min)', min_permiso: 'Minutos de permiso', min_a_compensar: 'Minutos por compensar',
  min_compensados: 'Minutos compensados', pct_compensado: 'Compensado', tipo_de_permiso: 'Tipo de permiso',
  solicitudes: 'Solicitudes', anio: 'Año', top: 'Cantidad',
}
export const titulo = (col) => TITULOS[col] || (col[0].toUpperCase() + col.slice(1)).replaceAll('_', ' ')
