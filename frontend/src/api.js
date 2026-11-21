// Cliente HTTP del aplicativo: todas las llamadas van a la API del backend
// Python, que a su vez solo ejecuta procedimientos almacenados.
async function pedir(metodo, ruta, cuerpo) {
  const resp = await fetch(`/api${ruta}`, {
    method: metodo,
    headers: cuerpo ? { 'Content-Type': 'application/json' } : undefined,
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  })
  const datos = await resp.json().catch(() => ({ error: 'Respuesta no válida del servidor' }))
  if (!resp.ok) throw new Error(datos.error || `Error ${resp.status}`)
  return datos
}

const qs = (p) => {
  const s = new URLSearchParams(Object.entries(p).filter(([, v]) => v !== '' && v != null)).toString()
  return s ? `?${s}` : ''
}

export const api = {
  panel: () => pedir('GET', '/panel'),
  areas: () => pedir('GET', '/areas'),
  empleados: (f) => pedir('GET', `/empleados${qs(f)}`),
  crearEmpleado: (d) => pedir('POST', '/empleados', d),
  editarEmpleado: (dni, d) => pedir('PUT', `/empleados/${dni}`, d),
  bajaEmpleado: (dni) => pedir('POST', `/empleados/${dni}/baja`),
  reactivarEmpleado: (dni) => pedir('POST', `/empleados/${dni}/reactivar`),
  solicitudes: (f) => pedir('GET', `/solicitudes${qs(f)}`),
  crearSolicitud: (d) => pedir('POST', '/solicitudes', d),
  editarSolicitud: (id, d) => pedir('PUT', `/solicitudes/${id}`, d),
  resolverSolicitud: (id, d) => pedir('POST', `/solicitudes/${id}/resolver`, d),
  anularSolicitud: (id) => pedir('POST', `/solicitudes/${id}/anular`),
  compensaciones: (id) => pedir('GET', `/solicitudes/${id}/compensaciones`),
  crearCompensacion: (id, d) => pedir('POST', `/solicitudes/${id}/compensaciones`, d),
  eliminarCompensacion: (id) => pedir('DELETE', `/compensaciones/${id}`),
  firmar: (id, firmante) => pedir('POST', `/compensaciones/${id}/firmas`, { firmante }),
  quitarFirma: (id, firmante) => pedir('DELETE', `/compensaciones/${id}/firmas/${firmante}`),
  reportes: () => pedir('GET', '/reportes'),
  reporte: (n, p) => pedir('GET', `/reportes/${n}${qs(p)}`),
  bitacora: () => pedir('GET', '/bitacora?limite=300'),
}
