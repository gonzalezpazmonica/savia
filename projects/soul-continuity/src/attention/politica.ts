// Política de atención determinista. Entra un evento y sale una acción: registrar, agrupar,
// avisar, preguntar una vez, bloquear y elevar, o diferir. Solo usa lo que la persona declara
// (modo, ventanas, presupuesto, alertas). Ningún modelo ni contenido eleva la urgencia y el
// silencio nunca es una respuesta.

import { Bandeja, type Item } from './bandeja.ts';
import {
  type Accion, type Aplazamiento, type Decision, type Motivo,
  modoNoDisponible, motivo as m,
} from './decision.ts';
import { type Estado, estadoVacio } from './estado.ts';
import { type Clase, Ledger } from './ledger.ts';
import {
  type Config, type Control, type Evento, type Modo, type Origen, type ReglaAlerta,
  TOPE_ALERTAS_POR_DEFECTO,
} from './modelo.ts';
import { type MensajeResumen, type TipoResumen, resumenesDebidos } from './resumen.ts';
import { DIA, type Minuto, instanciaEn, siguienteInicioEn } from './tiempo.ts';

type Hueco = { ok: true; instancia: Minuto } | { ok: false; motivo: Motivo; hasta: Minuto | null };

/**
 * Mensaje único con las alertas que superaron el tope propio. Si la entrega falla, quien
 * llama lo devuelve con `reencolarAlertasAgrupadas` para que no se pierda.
 */
export interface MensajeAlertasAgrupadas {
  n: number;
  eventoIds: string[];
  /** `null` donde el contenido superaba el nivel del canal o no está en memoria. */
  textos: Array<string | null>;
  texto: string;
}

export type { MensajeResumen, TipoResumen };

const ENTERO_NO_NEGATIVO = (n: number): boolean => Number.isInteger(n) && n >= 0;
const NIVEL_VALIDO = (n: unknown): boolean => n === 1 || n === 2 || n === 3 || n === 4;

/** Solo viaja en claro un nivel válido que no supera el del canal; lo demás se redacta. */
const redactar = (nivel: unknown, canal: unknown): boolean =>
  !(NIVEL_VALIDO(nivel) && NIVEL_VALIDO(canal) && (nivel as number) <= (canal as number));

export class Politica {
  readonly config: Config;
  estado: Estado;
  readonly bandeja = new Bandeja();
  readonly ledger = new Ledger();

  constructor(config: Config, estado: Estado = estadoVacio()) {
    this.config = config;
    this.estado = estado;
  }

  /** Presupuesto de avisos por ventana. Un valor inválido falla cerrado: 0. */
  private get presupuesto(): number {
    return ENTERO_NO_NEGATIVO(this.config.presupuesto) ? this.config.presupuesto : 0;
  }

  /** Tope propio de alertas. Un valor inválido usa el defecto (las alertas no se pierden). */
  private get topeAlertas(): number {
    const t = this.config.topeAlertas;
    return t !== undefined && ENTERO_NO_NEGATIVO(t) ? t : TOPE_ALERTAS_POR_DEFECTO;
  }

  /**
   * Aplica una orden de control. Devuelve si se aceptó. Detener y vetar se aceptan de la
   * persona o de un agente autenticado (es lo seguro), nunca de un origen sin autenticar: un
   * veto calla los avisos y las alertas de su objetivo. Reanudar, levantar un veto, declarar el
   * modo y responder, solo desde el canal de la persona.
   */
  control(c: Control, origen: Origen, _ahora: Minuto): boolean {
    const persona = origen === 'PERSONA';
    const autenticado = persona || origen === 'AGENTE_AUTENTICADO';
    switch (c.k) {
      case 'PARA':
        if (!autenticado) return false;
        this.estado.parado = true;
        return true;
      case 'VETAR':
        if (!autenticado || c.objetivo === '') return false;
        this.estado.vetos.add(c.objetivo);
        return true;
      case 'REANUDAR':
        if (!persona) return false;
        this.estado.parado = false;
        return true;
      case 'LEVANTAR_VETO':
        return persona && this.estado.vetos.delete(c.objetivo);
      case 'DECLARAR_MODO':
        if (!persona) return false;
        this.estado.modoDeclarado = c.modo;
        return true;
      case 'RESPONDER':
        return persona && this.bandeja.resolver(c.decisionId);
    }
  }

  private declaracionVigente(ahora: Minuto) {
    const md = this.estado.modoDeclarado;
    return md !== null && (md.hasta === null || md.hasta > ahora) ? md : null;
  }

  /**
   * Modo declarado vigente; si no hay, `DESCANSO` en franja de descanso declarada; si no, el
   * modo por defecto declarado. `null` = la persona no ha declarado nada.
   */
  modoEfectivo(ahora: Minuto): Modo | null {
    const md = this.declaracionVigente(ahora);
    if (md) return md.modo;
    if (instanciaEn(this.config.descansos, ahora) !== null) return 'DESCANSO';
    return this.config.modoPorDefecto;
  }

  /** ¿Se puede contactar ahora? La instancia de ventana o el motivo y hasta cuándo. */
  private hueco(ahora: Minuto): Hueco {
    const ventanas = this.config.ventanas;
    const modo = this.modoEfectivo(ahora);
    if (modo === null) return { ok: false, motivo: m('SIN_DECLARACION'), hasta: null };
    if (modo !== 'DISPONIBLE') {
      return { ok: false, motivo: modoNoDisponible(modo), hasta: this.oportunidadTrasModo(ahora) };
    }
    const inst = instanciaEn(ventanas, ahora);
    if (inst === null) return { ok: false, motivo: m('FUERA_DE_VENTANA'), hasta: siguienteInicioEn(ventanas, ahora) };
    if ((this.estado.usados.get(inst) ?? 0) >= this.presupuesto) {
      return { ok: false, motivo: m('PRESUPUESTO_AGOTADO'), hasta: siguienteInicioEn(ventanas, ahora) };
    }
    return { ok: true, instancia: inst };
  }

  /**
   * Cuándo se reconsidera algo aplazado por el modo. Sin fin declarado del modo, si el modo
   * viene de una franja de descanso, en la siguiente ventana; si es una declaración
   * indefinida o el modo por defecto, `null`: hasta que la persona cambie el modo.
   */
  private oportunidadTrasModo(ahora: Minuto): Minuto | null {
    const ventanas = this.config.ventanas;
    const md = this.declaracionVigente(ahora);
    if (md) {
      const h = md.hasta;
      if (h === null) return null;
      return instanciaEn(ventanas, h) !== null ? h : siguienteInicioEn(ventanas, h);
    }
    if (instanciaEn(this.config.descansos, ahora) !== null) return siguienteInicioEn(ventanas, ahora);
    return null;
  }

  /** Regla de alerta declarada con el código del evento, sin mirar el origen. */
  private reglaDe(ev: Evento): ReglaAlerta | null {
    if (ev.codigoAlerta === null) return null;
    return this.config.alertas.find((r) => r.codigo === ev.codigoAlerta) ?? null;
  }

  /** Cubo del tope de alertas: la instancia de ventana, o el día si cae fuera de toda ventana. */
  private cuboAlertas(ahora: Minuto): Minuto {
    return instanciaEn(this.config.ventanas, ahora) ?? -(Math.floor(ahora / DIA) + 1);
  }

  private anotarLedger(ev: Evento, clase: Clase, ahora: Minuto, d: Decision): void {
    const ventana = instanciaEn(this.config.ventanas, ahora);
    this.ledger.anotar({
      eventoId: ev.id, en: ahora, clase, accion: d.accion, motivo: d.motivo, hasta: d.hasta,
      ahora: d.contactarAhora, dentroDeVentana: ventana !== null, ventana,
    });
  }

  private aBandeja(ev: Evento, decisionId: string | null, individual: boolean, ap: Aplazamiento | null, redactado: boolean): void {
    const item: Item = {
      eventoId: ev.id, decisionId, objetivo: ev.objetivo, plazo: ev.plazo, coste: ev.costeRetraso,
      individual, texto: redactado ? null : ev.texto, historial: ap ? [ap] : [], pendiente: true,
    };
    this.bandeja.meter(item);
  }

  decidir(ev: Evento, ahora: Minuto): Decision {
    const urgenciaIgnorada = ev.urgenciaEnContenido !== 'NORMAL'
      || (ev.urgenciaSugeridaLlm !== null && ev.urgenciaSugeridaLlm !== 'NORMAL');
    const redactado = redactar(ev.nivel, this.config.canalNivelMax);
    let degradadaAAviso = false;
    const d = (accion: Accion, motivo: Motivo, contactarAhora: boolean, hasta: Minuto | null): Decision => ({
      accion, motivo, contactarAhora, hasta, redactado, urgenciaIgnorada, degradadaAAviso,
    });
    const sinDemanda = (accion: Accion, motivo: Motivo): Decision => {
      const dec = d(accion, motivo, false, null);
      this.ledger.descartar({ eventoId: ev.id, en: ahora, accion, motivo });
      return dec;
    };

    // 1. El silencio no es permiso: lo pendiente sigue pendiente y no se mide a la persona.
    if (ev.tipo.k === 'SILENCIO') {
      this.bandeja.anotar(ev.tipo.decisionId, { en: ahora, accion: 'REGISTRAR', motivo: m('SILENCIO_NO_ES_PERMISO'), hasta: null });
      return d('REGISTRAR', m('SILENCIO_NO_ES_PERMISO'), false, null);
    }

    // Solo la persona y un agente autenticado autentican. La web nunca (AC-4c), aunque el
    // llamador no use el puente y declare otro origen.
    const web = ev.ruta === 'WEB';
    let sinAutenticar = web || (ev.origen !== 'PERSONA' && ev.origen !== 'AGENTE_AUTENTICADO');

    // 2. Alerta declarada por la persona: no gasta presupuesto; tiene tope propio.
    const regla = this.reglaDe(ev);
    let tipo = ev.tipo;
    if (regla !== null) {
      if (web) {
        // Por la web una regla nunca es alerta, solo aviso, sea o no de remitente. Es lo único
        // de la web que puede avisar, porque lo pide una regla de la persona; un remitente que
        // se sabe suplantado (`NO_AUTENTICADO`) ni eso.
        degradadaAAviso = true;
        sinAutenticar = ev.origen === 'NO_AUTENTICADO';
        tipo = { k: 'NOTIFICACION' };
      } else if (!sinAutenticar) {
        return this.decidirAlerta(ev, regla, ahora, d);
      }
    }

    // 3. Avisos informativos: nunca interrumpen.
    if (tipo.k === 'AVISO') {
      const rutinario = tipo.rutinario;
      let motivo: Motivo;
      if (this.estado.parado) motivo = m('PARADO');
      else if (ev.objetivo !== null && this.estado.vetos.has(ev.objetivo)) motivo = m('VETADO');
      else if (sinAutenticar) motivo = m('ORIGEN_NO_AUTENTICADO');
      else if (ev.caduca !== null && ev.caduca <= ahora) motivo = m('CONTEXTO_VENCIDO');
      else if (rutinario) motivo = m('AVISO_RUTINARIO');
      else {
        const dec = d('AGRUPAR', m('AVISO_AGRUPADO'), false, null);
        this.aBandeja(ev, null, false, null, redactado);
        this.anotarLedger(ev, 'AVISO', ahora, dec);
        return dec;
      }
      return sinDemanda('REGISTRAR', motivo);
    }

    // 4. Aviso a notificar: gasta presupuesto dentro de ventana; lo que excede va al resumen.
    if (tipo.k === 'NOTIFICACION') {
      let motivo: Motivo | null = null;
      if (this.estado.parado) motivo = m('PARADO');
      else if (ev.objetivo !== null && this.estado.vetos.has(ev.objetivo)) motivo = m('VETADO');
      else if (sinAutenticar) motivo = m('ORIGEN_NO_AUTENTICADO');
      else if (ev.caduca !== null && ev.caduca <= ahora) motivo = m('CONTEXTO_VENCIDO');
      else if (this.estado.preguntadas.has(ev.id)) motivo = m('YA_PREGUNTADA');
      if (motivo !== null) return sinDemanda('REGISTRAR', motivo);
      const h = this.hueco(ahora);
      let dec: Decision;
      let ap: Aplazamiento | null = null;
      if (h.ok) {
        this.estado.usados.set(h.instancia, (this.estado.usados.get(h.instancia) ?? 0) + 1);
        dec = d('AVISAR', m('DISPONIBLE'), true, null);
      } else {
        dec = d('AGRUPAR', h.motivo, false, h.hasta);
        ap = { en: ahora, accion: dec.accion, motivo: dec.motivo, hasta: h.hasta };
      }
      this.estado.preguntadas.add(ev.id);
      this.aBandeja(ev, null, false, ap, redactado);
      this.anotarLedger(ev, 'AVISO', ahora, dec);
      return dec;
    }

    // 5. Lo que pide una decisión o un efecto.
    let clave: string;
    let clase: Clase;
    let individual: boolean;
    let motivoPropio: Motivo;
    switch (tipo.k) {
      case 'DECISION':
        [clave, clase, individual, motivoPropio] = [tipo.decisionId, 'PREGUNTA', false, m('DISPONIBLE')];
        break;
      case 'APROBACION_SEGURIDAD':
        [clave, clase, individual, motivoPropio] = [tipo.decisionId, 'APROBACION', true, m('APROBACION_SEGURIDAD')];
        break;
      case 'PETICION_PERMISO':
        [clave, clase, individual, motivoPropio] = [ev.id, 'APROBACION', true, m('APROBACION_SEGURIDAD')];
        break;
      case 'REINTENTO':
        [clave, clase, individual, motivoPropio] = [ev.id, 'APROBACION', true, m('EFECTO_AMBIGUO')];
        break;
      default:
        // Ya han salido antes; si se llegara aquí, no se pide nada a nadie.
        return sinDemanda('REGISTRAR', m('AVISO_RUTINARIO'));
    }

    let bloqueo: Motivo | null = null;
    if (tipo.k === 'PETICION_PERMISO' && (!tipo.dentroDeContrato || sinAutenticar)) {
      bloqueo = m('PERMISO_ILEGITIMO');
    } else if (sinAutenticar) {
      return sinDemanda('REGISTRAR', m('ORIGEN_NO_AUTENTICADO'));
    } else if (this.estado.parado) {
      bloqueo = m('PARADO');
    } else if (ev.objetivo !== null && this.estado.vetos.has(ev.objetivo)) {
      bloqueo = m('VETADO');
    } else if (ev.caduca !== null && ev.caduca <= ahora) {
      bloqueo = m('CONTEXTO_VENCIDO');
    }
    if (bloqueo !== null) {
      const dec = d('BLOQUEAR_Y_ELEVAR', bloqueo, false, null);
      this.aBandeja(ev, clave, true, { en: ahora, accion: dec.accion, motivo: bloqueo, hasta: null }, redactado);
      this.anotarLedger(ev, clase, ahora, dec);
      return dec;
    }

    if (tipo.k === 'REINTENTO' && tipo.efectoPrevio === 'NO_OCURRIO') {
      return sinDemanda('REGISTRAR', m('REINTENTO_SIN_EFECTO'));
    }
    if (this.estado.preguntadas.has(clave) || this.bandeja.porDecision(clave) !== undefined) {
      return sinDemanda('REGISTRAR', m('YA_PREGUNTADA'));
    }

    const accionContacto: Accion = clase === 'PREGUNTA' ? 'PREGUNTAR_UNA_VEZ' : 'BLOQUEAR_Y_ELEVAR';
    let dec: Decision;
    if (clase === 'PREGUNTA' && ev.costeRetraso === 'BAJO') {
      const h = this.hueco(ahora);
      const hasta = h.ok ? siguienteInicioEn(this.config.ventanas, ahora) : h.hasta;
      dec = d('DIFERIR', m('PUEDE_ESPERAR'), false, hasta);
    } else {
      const h = this.hueco(ahora);
      if (h.ok) {
        this.estado.usados.set(h.instancia, (this.estado.usados.get(h.instancia) ?? 0) + 1);
        this.estado.preguntadas.add(clave);
        dec = d(accionContacto, motivoPropio, true, null);
      } else {
        dec = d(individual ? 'BLOQUEAR_Y_ELEVAR' : 'AGRUPAR', h.motivo, false, h.hasta);
      }
    }
    const ap = dec.contactarAhora ? null : { en: ahora, accion: dec.accion, motivo: dec.motivo, hasta: dec.hasta };
    this.aBandeja(ev, clave, individual, ap, redactado);
    this.anotarLedger(ev, clase, ahora, dec);
    return dec;
  }

  /**
   * Alerta de una fuente autenticada con regla declarada. No se pierde: llega aunque esté
   * PARA; solo la callan un veto de su objetivo o un contexto vencido.
   */
  private decidirAlerta(
    ev: Evento,
    regla: ReglaAlerta,
    ahora: Minuto,
    d: (a: Accion, mo: Motivo, c: boolean, h: Minuto | null) => Decision,
  ): Decision {
    if (this.estado.preguntadas.has(ev.id)) {
      const dec = d('REGISTRAR', m('YA_PREGUNTADA'), false, null);
      this.ledger.descartar({ eventoId: ev.id, en: ahora, accion: dec.accion, motivo: dec.motivo });
      return dec;
    }
    // Un veto es una orden de la persona y un contexto vencido ya no pide nada: se registra
    // sin marcarla como tratada, para que llegue si se levanta el veto o vuelve con contexto.
    let descarte: Motivo | null = null;
    if (ev.objetivo !== null && this.estado.vetos.has(ev.objetivo)) descarte = m('VETADO');
    else if (ev.caduca !== null && ev.caduca <= ahora) descarte = m('CONTEXTO_VENCIDO');
    if (descarte !== null) {
      const dec = d('REGISTRAR', descarte, false, null);
      this.ledger.descartar({ eventoId: ev.id, en: ahora, accion: dec.accion, motivo: dec.motivo });
      return dec;
    }
    this.estado.preguntadas.add(ev.id);
    const modo = this.modoEfectivo(ahora);
    // En DISPONIBLE una alerta declarada pasa; en el resto, solo si está marcada para ese modo.
    const marcada = modo === 'DISPONIBLE' || (modo !== null && regla.modos.includes(modo));
    let dec: Decision;
    let ap: Aplazamiento | null = null;
    if (!marcada) {
      // Se difiere como cualquier aviso y queda en el resumen.
      const motivo = modo === null ? m('SIN_DECLARACION') : modoNoDisponible(modo);
      dec = d('DIFERIR', motivo, false, modo === null ? null : this.oportunidadTrasModo(ahora));
      ap = { en: ahora, accion: dec.accion, motivo, hasta: dec.hasta };
    } else {
      const cubo = this.cuboAlertas(ahora);
      const usadas = this.estado.alertasUsadas.get(cubo) ?? 0;
      if (usadas < this.topeAlertas) {
        this.estado.alertasUsadas.set(cubo, usadas + 1);
        dec = d('BLOQUEAR_Y_ELEVAR', m('ALERTA'), true, null);
      } else {
        this.estado.excedidas.push(ev.id);
        dec = d('AGRUPAR', m('TOPE_ALERTAS'), false, null);
        ap = { en: ahora, accion: dec.accion, motivo: dec.motivo, hasta: null };
      }
    }
    this.aBandeja(ev, null, true, ap, dec.redactado);
    this.anotarLedger(ev, 'ALERTA', ahora, dec);
    return dec;
  }

  /** Resúmenes de inicio y de cierre cuya hora fijada ya llegó y aún no salieron. */
  resumenesDebidos(ahora: Minuto): MensajeResumen[] {
    return resumenesDebidos(this, ahora);
  }

  /**
   * Un único mensaje «hay N alertas más» con la lista de las que superaron el tope.
   * Vacía la cola: lo que no se pueda emitir ahora se emite en la siguiente llamada.
   */
  drenarAlertasAgrupadas(): MensajeAlertasAgrupadas | null {
    const ids = this.estado.excedidas;
    if (ids.length === 0) return null;
    this.estado.excedidas = [];
    const textos = ids.map((id) => this.bandeja.porEvento(id)?.texto ?? null);
    return { n: ids.length, eventoIds: [...ids], textos, texto: `hay ${ids.length} alertas más` };
  }

  /** Devuelve a la cola, delante y sin duplicar, las alertas de un mensaje que no se entregó. */
  reencolarAlertasAgrupadas(msg: MensajeAlertasAgrupadas): void {
    const pendientes = this.estado.excedidas.filter((id) => !msg.eventoIds.includes(id));
    this.estado.excedidas = [...msg.eventoIds, ...pendientes];
  }
}
