// Prueba de punta a punta del aplicativo (sin dependencias: Chrome DevTools
// Protocol con el WebSocket nativo de Node). Recorre los módulos, verifica
// las operaciones y guarda capturas para el manual de usuario.
// Uso: node e2e/prueba_e2e.mjs http://127.0.0.1:8091 ../docs/capturas
import { spawn } from 'node:child_process'
import { mkdirSync, writeFileSync, mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import assert from 'node:assert/strict'

const [URL_APP = 'http://127.0.0.1:8091', SALIDA = 'capturas'] = process.argv.slice(2)
mkdirSync(SALIDA, { recursive: true })
const chrome = spawn('google-chrome-stable', ['--headless=new', '--no-sandbox', '--disable-gpu', '--remote-debugging-port=9333',
  '--window-size=1366,820', `--user-data-dir=${mkdtempSync(join(tmpdir(), 'e2e-'))}`, `${URL_APP}/#panel`], { stdio: 'ignore' })
const espera = (ms) => new Promise((r) => setTimeout(r, ms))

let ws, n = 0
const pendientes = new Map()
async function conectar() {
  for (let i = 0; i < 50; i++) {
    try {
      const pags = await (await fetch('http://127.0.0.1:9333/json/list')).json()
      const pag = pags.find((p) => p.type === 'page')
      if (pag) { ws = new WebSocket(pag.webSocketDebuggerUrl); break }
    } catch { /* Chrome aún no está listo */ }
    await espera(200)
  }
  if (ws.readyState !== WebSocket.OPEN) await new Promise((r) => ws.addEventListener('open', r))
  ws.addEventListener('message', (e) => {
    const m = JSON.parse(e.data)
    if (pendientes.has(m.id)) { pendientes.get(m.id)(m); pendientes.delete(m.id) }
  })
}
const cdp = (method, params = {}) => new Promise((r) => { const id = ++n; pendientes.set(id, r); ws.send(JSON.stringify({ id, method, params })) })
async function js(expr) {
  const r = await cdp('Runtime.evaluate', { expression: `(async () => { ${expr} })()`, awaitPromise: true, returnByValue: true })
  if (r.result.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description || 'Error en la página')
  return r.result.result.value
}
async function captura(nombre) {
  await espera(500)
  const r = await cdp('Page.captureScreenshot', { format: 'png' })
  writeFileSync(join(SALIDA, `${nombre}.png`), Buffer.from(r.result.data, 'base64'))
  console.log('  captura', nombre)
}

// Utilidades que se inyectan en la página.
const AYUDA = `
window.$t = (sel, txt) => [...document.querySelectorAll(sel)].find((e) => e.textContent.trim().includes(txt));
window.$click = (sel, txt) => { const e = $t(sel, txt); if (!e) throw new Error('No encontrado: ' + sel + ' ' + txt); e.click(); };
window.$control = (etiqueta) => {
  const l = [...document.querySelectorAll('.modal .campo')].find((x) => x.querySelector('span').textContent.trim() === etiqueta);
  if (!l) throw new Error('Campo no encontrado: ' + etiqueta);
  return l.querySelector('input, select, textarea');
};
window.$error = (etiqueta) => $control(etiqueta).closest('.campo.con-error')?.querySelector('.bajo-campo').textContent || '';
window.$campo = (etiqueta, valor) => {
  const el = $control(etiqueta);
  const proto = { SELECT: HTMLSelectElement, TEXTAREA: HTMLTextAreaElement }[el.tagName]?.prototype || HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, valor);
  el.dispatchEvent(new Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
};
// Espera un aviso nuevo (distinto del último leído), porque el anterior puede seguir visible.
window.$aviso = async () => { for (let i = 0; i < 60; i++) { const a = document.querySelector('.aviso'); const v = a && a.className + '|' + a.textContent; if (v && v !== window.__ultimo) { window.__ultimo = v; return v; } await new Promise((r) => setTimeout(r, 100)); } return ''; };
window.$empleado = async (dni) => { $campo('Empleado', dni); await $espera(() => document.querySelectorAll('.selector [role=option]').length === 1); document.querySelector('.selector [role=option]').dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true })); };
window.$elige = (txt) => { const l = [...document.querySelectorAll('.modal .opcion')].find((x) => x.querySelector('strong').textContent === txt); if (!l) throw new Error('Opción no encontrada: ' + txt); l.click(); };
window.$busca = (v) => { const i = document.querySelector('input[type=search]'); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(i, v); i.dispatchEvent(new Event('input', { bubbles: true })); };
window.$fila = (txt) => [...document.querySelectorAll('tbody tr')].find((tr) => tr.textContent.includes(txt));
window.$espera = async (fn) => { for (let i = 0; i < 50; i++) { if (fn()) return true; await new Promise((r) => setTimeout(r, 100)); } throw new Error('Tiempo de espera agotado'); };
`
async function ir(vista) {
  // Recarga completa (no solo cambio de #) para limpiar avisos de la vista anterior.
  const r = Date.now()
  await cdp('Page.navigate', { url: `${URL_APP}/?r=${r}#${vista}` })
  for (let i = 0; i < 50; i++) {
    if (await js(`return location.search === '?r=${r}' && document.readyState === 'complete'`)) break
    await espera(100)
  }
  await espera(300)
  await js(AYUDA)
}

try {
  await conectar()
  await cdp('Page.enable')
  console.log('Panel'); await ir('panel')
  assert.ok(Number(await js(`await $espera(() => document.querySelector('.tarjeta .valor')); return document.querySelector('.tarjeta .valor').textContent`)) > 0)
  await captura('01_panel')

  console.log('Empleados: alta'); await ir('empleados')
  await js(`await $espera(() => document.querySelectorAll('tbody tr').length > 10)`)
  await captura('02_empleados')
  await js(`$click('button', 'Nuevo empleado')`); await espera(200)
  // Validación: campos vacíos, DNI repetido y nombre con números.
  await js(`$click('.modal button', 'Registrar empleado'); await $espera(() => $error('DNI') && $error('Nombres') && $error('Cargo'))`)
  await js(`$campo('DNI','72123249'); $campo('Nombres','Ana 3')`); await js(`$click('.modal button', 'Registrar empleado'); await $espera(() => /Ya es el DNI de/.test($error('DNI')) && /solo letras/.test($error('Nombres')))`)
  await captura('03a_errores')
  await js(`$campo('DNI','70112233'); $campo('Nombres','Andrea'); $campo('Apellidos','Prueba Manual'); $campo('Cargo','Docente'); $campo('Área','Sistemas')`)
  await captura('03_nuevo_empleado')
  await js(`$click('.modal button', 'Registrar empleado')`)
  assert.match(await js(`return await $aviso()`), /aviso-ok\|Empleado registrado/)
  await captura('04_empleado_registrado')

  console.log('Solicitudes: registro y tope'); await ir('solicitudes')
  await js(`await $espera(() => document.querySelectorAll('tbody tr').length > 10)`)
  await captura('05_solicitudes')
  await js(`$click('button', 'Nueva solicitud')`); await espera(300)
  await js(`await $empleado('70112233'); $elige('Urgente'); $campo('Fecha del permiso','2026-11-23'); $campo('Hora de registro','07:20'); $campo('Hora de inicio','08:00'); $campo('Minutos','30'); $t('.modal .check', 'Recuperará').querySelector('input').click(); await $espera(() => $t('.modal .campo', 'Minutos a compensar')); $campo('Minutos a compensar','30')`)
  await captura('06_nueva_solicitud')
  await js(`$click('.modal button', 'Registrar solicitud')`)
  assert.match(await js(`return await $aviso()`), /aviso-ok\|Solicitud registrada/)
  await espera(3800)
  await js(`$click('button', 'Nueva solicitud')`); await espera(300)
  await js(`await $empleado('70112233'); $elige('Urgente'); $campo('Fecha del permiso','2026-11-25'); $campo('Hora de registro','07:30'); $campo('Hora de inicio','08:00'); $campo('Minutos','20')`)
  await js(`$click('.modal button', 'Registrar solicitud')`)
  await js(`await $espera(() => document.querySelector('.resumen.con-error'))`)  // avisa del tope antes de guardar
  await espera(400); assert.ok(await js(`return !!document.querySelector('.modal .con-error') && document.querySelectorAll('.modal').length === 1`), 'el formulario no debe enviarse con el tope agotado')
  await captura('07_tope_rechazado')
  await js(`$click('.modal button', 'Cancelar'); await $espera(() => $t('.modal', '¿Descartar los cambios?'))`)
  await captura('07a_descartar')
  await js(`$click('.modal button', 'Descartar'); await $espera(() => !document.querySelector('.modal'))`)

  console.log('Solicitudes: aprobación y compensación')
  await js(`$busca('70112233')`)
  await js(`await $espera(() => document.querySelectorAll('tbody tr').length === 1)`)
  await js(`[...$fila('Andrea').querySelectorAll('button')].find((b) => b.textContent === 'Resolver').click()`); await espera(300)
  await js(`$elige('Aprobar'); $campo('Tipo de permiso','Tardanza justificada'); $campo('Motivo','Cita médica')`)
  await captura('08_resolver')
  await js(`$click('.modal button', 'Aprobar solicitud')`)
  assert.match(await js(`return await $aviso()`), /aviso-ok\|Solicitud aprobada/)
  await js(`await $espera(() => $fila('Andrea')?.textContent.includes('Aprobado'))`)
  await js(`[...$fila('Andrea').querySelectorAll('button')].find((b) => b.textContent === 'Compensación').click()`); await espera(500)
  await js(`$campo('Fecha','2026-11-24'); $campo('Inicio','17:00'); $campo('Fin','17:30')`)
  await js(`$click('.modal button', 'Agregar bloque')`)
  assert.match(await js(`return await $aviso()`), /aviso-ok\|Bloque registrado/)
  await js(`await $espera(() => document.querySelector('.modal tbody tr'))`)
  await js(`$click('.modal button', 'Firma colaborador')`); await espera(600)
  await captura('09_compensacion')
  await js(`document.querySelector('.modal [aria-label=Cerrar]').click()`)

  console.log('Empleados: baja lógica'); await ir('empleados')
  await js(`$busca('70112233'); await $espera(() => document.querySelectorAll('tbody tr').length === 1 && $fila('70112233'))`)
  await js(`[...$fila('70112233').querySelectorAll('button')].find((b) => b.textContent === 'Dar de baja').click()`); await espera(300)
  await captura('10a_confirmar_baja')
  await js(`$click('.modal .btn.peligro', 'Dar de baja')`)
  assert.match(await js(`return await $aviso()`), /aviso-ok\|Empleado dado de baja/)
  await js(`await $espera(() => $fila('70112233')?.textContent.includes('Baja'))`)
  await captura('10_baja_logica')

  console.log('Reportes'); await ir('reportes')
  await js(`await $espera(() => document.querySelectorAll('.lista-reportes li').length === 10)`)
  for (const [num, nombre] of [[1, 'Permisos por empleado'], [6, 'Saldo por compensar'], [10, 'Ranking de minutos']]) {
    await js(`$click('.lista-reportes button', ${JSON.stringify(nombre)})`); await espera(400)
    await js(`const b = $t('.caja button', 'Ejecutar'); if (b) b.click()`)
    await js(`await $espera(() => document.querySelector('.caja tbody tr'))`)
    await captura(`11_reporte_${String(num).padStart(2, '0')}`)
  }

  console.log('Bitácora'); await ir('bitacora')
  await js(`await $espera(() => $fila('Baja'))`)
  await captura('12_bitacora')
  console.log('\nPRUEBA E2E: OK')
} catch (e) {
  console.error('\nPRUEBA E2E FALLÓ:', e.message)
  process.exitCode = 1
} finally {
  ws?.close(); chrome.kill()
}
