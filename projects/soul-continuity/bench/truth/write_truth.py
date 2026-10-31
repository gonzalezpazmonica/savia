"""Verdad del banco SE-490, escrita a mano antes de ejecutar ninguna implementación.

Cada lista es literal y se razonó contra world/*.json y CONTRATO.md. Este script
solo la serializa en truth/scenarios.json (no calcula nada a partir del mundo).
"""
import json
from pathlib import Path

def aw(conv, msg, a="m365-mail"): return f"{a}:awaiting_reply:{conv}@{msg}"
def gaw(th, msg): return aw(th, msg, "google-workspace")
def mt(e, a="m365-calendar"): return f"{a}:meeting:{e}"
def gmt(e): return mt(e, "google-workspace")
def jira(k): return f"jira:task_assigned:{k}"
def gh(kind, repo, n): return f"github:{kind}:{repo}#{n}"
def ado(n): return f"azure-devops:task_assigned:{n}"
def adopr(r, n): return f"azure-devops:review_request:{r}!{n}"
def web(kind, site, item): return f"web:{kind}:{site}~{item}"

# --- PM -------------------------------------------------------------------
PM_AW_T1 = [aw("pm-th01","pm-m01"), aw("pm-th03","pm-m06"), aw("pm-th06","pm-m10"), aw("pm-th07","pm-m14"),
            aw("pm-th10","pm-m18"), aw("pm-th12","pm-m22"), aw("pm-th13","pm-m23"), aw("pm-th14","pm-m24"),
            aw("pm-th15","pm-m25"), aw("pm-th16","pm-m26"), aw("pm-th17","pm-m27"), aw("pm-th19","pm-m29")]
PM_AW_T0 = [aw("pm-th01","pm-m01"), aw("pm-th03","pm-m06"), aw("pm-th06","pm-m10"), aw("pm-th07","pm-m14"),
            aw("pm-th11","pm-m19"), aw("pm-th12","pm-m21"), aw("pm-th13","pm-m23"), aw("pm-th14","pm-m24"),
            aw("pm-th15","pm-m25"), aw("pm-th16","pm-m26"), aw("pm-th17","pm-m27"), aw("pm-th19","pm-m29")]
PM_JIRA_T1 = [jira(k) for k in ["PMX-1","PMX-4","PMX-5","PMX-6","PMX-7","PMX-8","PMX-9"]]
PM_JIRA_T0 = [jira(k) for k in ["PMX-1","PMX-4","PMX-5","PMX-7","PMX-8","PMX-9"]]
PM_TASKS_T1 = PM_JIRA_T1 + [gh("task_assigned","pm-portal",14)]
PM_TASKS_T0 = PM_JIRA_T0 + [gh("task_assigned","pm-portal",14)]
PM_Q1_T1 = ([mt("pm-e02"), mt("pm-e03"), mt("pm-e08")] + PM_TASKS_T1 + [gh("review_request","pm-portal",12)]
            + PM_AW_T1 + ["m365-files:document_comments:pm-f01", "m365-files:document_comments:pm-f03"])
PM_Q1_T0 = ([mt("pm-e01"), mt("pm-e02"), mt("pm-e05"), mt("pm-e08")] + PM_TASKS_T0
            + [gh("review_request","pm-portal",12), gh("review_request","pm-portal",16)]
            + PM_AW_T0 + ["m365-files:document_comments:pm-f01", "m365-files:document_comments:pm-f03",
                          "m365-files:document_comments:pm-f04"])
PM_MENTIONS_T1 = ["m365-teams:mention:pm-cm01", "m365-teams:mention:pm-cm05", gh("mention","pm-portal",15)]
PM_Q2_T1 = PM_AW_T1 + PM_MENTIONS_T1 + PM_TASKS_T1 + [gh("review_request","pm-portal",12)]
PM_Q4_T1 = [jira("PMX-1"), jira("PMX-5"), jira("PMX-8"), "m365-mail:dated_commitment:pm-m27",
            mt("pm-e02"), mt("pm-e03"), mt("pm-e06"), mt("pm-e08")]
PM_Q3 = [aw("pm-th10","pm-m18"), aw("pm-th12","pm-m22"), "m365-teams:mention:pm-cm05", jira("PMX-6"),
         aw("pm-th11","pm-m19"), aw("pm-th12","pm-m21"), mt("pm-e05"), "m365-files:document_comments:pm-f04",
         gh("review_request","pm-portal",16),
         mt("pm-e08"), jira("PMX-5")]

# --- DIR ------------------------------------------------------------------
DIR_AW_T1 = [aw("dir-th01","dir-m01"), aw("dir-th03","dir-m04")]
DIR_WORK_T1 = [ado(101), ado(104), adopr("cartera-api",7), web("task_assigned","aprobaciones","ap-2")]
DIR_Q1_T1 = [mt("dir-e01"), mt("dir-e02")] + DIR_AW_T1 + DIR_WORK_T1
DIR_Q2_T1 = DIR_AW_T1 + DIR_WORK_T1
DIR_Q4_T1 = [mt("dir-e01"), mt("dir-e02"), mt("dir-e04"), ado(101), ado(104),
             web("dated_commitment","aprobaciones","ap-1")]
DIR_Q3 = [aw("dir-th03","dir-m04"), ado(104), adopr("cartera-api",9), web("web_page_change","intranet","inicio")]

# --- INV ------------------------------------------------------------------
INV_AW_T1 = [gaw("inv-t01","inv-g01"), gaw("inv-t04","inv-g07"), gaw("inv-t05","inv-g08"), gaw("inv-t06","inv-g09")]
INV_GH = [gh("review_request","inv-lab",3), gh("task_assigned","inv-lab",4), gh("task_assigned","inv-lab",5)]
INV_Q1_T1 = [gmt("inv-e01")] + INV_AW_T1 + ["google-workspace:document_comments:inv-d01"] + INV_GH
INV_Q2_T1 = INV_AW_T1 + INV_GH + [gh("mention","inv-lab",6)]
INV_Q4_T1 = [gmt("inv-e01"), gmt("inv-e03")]
INV_Q3 = [gaw("inv-t04","inv-g07"), web("web_page_change","revista","estado-envio")]

# --- DOC ------------------------------------------------------------------
DOC_AW_T1 = [gaw("doc-t01","doc-g01"), gaw("doc-t04","doc-g07"), gaw("doc-t05","doc-g08")]
DOC_WEB_TASKS = [web("task_assigned","campus","tarea-1"), web("task_assigned","campus","tarea-2")]
DOC_Q1_T1 = ([gmt("doc-e01"), gmt("doc-e02")] + DOC_AW_T1
             + ["google-workspace:document_comments:doc-d01", "google-workspace:document_comments:doc-d02"] + DOC_WEB_TASKS)
DOC_Q2_T1 = DOC_AW_T1 + DOC_WEB_TASKS
DOC_Q4_T1 = [gmt("doc-e01"), gmt("doc-e02"), gmt("doc-e03"), web("task_assigned","campus","tarea-1"),
             web("dated_commitment","campus","acta-1")]
DOC_Q3 = ["google-workspace:document_comments:doc-d02", web("task_assigned","campus","tarea-3")]

# --- MIN ------------------------------------------------------------------
MIN_Q1 = [gh("task_assigned","min-tools",1), gh("review_request","min-tools",2)]

S = []
def sc(id, title, tags, install, q, expect=None, at="t1", **kw):
    d = {"id": id, "title": title, "tags": tags, "install": install, "at": at, "ask": {"q": q}}
    for k in ("filter", "detail", "max_level", "since", "previous_install"):
        if k in kw: d["ask"][k] = kw.pop(k)
    if expect is not None: d["expect"] = sorted(expect)
    d.update(kw)
    S.append(d)

AW = {"types": ["awaiting_reply"]}
def awf(prefix): return {"types": ["awaiting_reply"], "ref_prefix": prefix}

# Base por operador e instante
sc("B01", "PM: qué tengo abierto (t1)", ["base"], "pm", "Q1", PM_Q1_T1)
sc("B02", "PM: qué tengo abierto (t0)", ["base", "dos-instantes"], "pm", "Q1", PM_Q1_T0, at="t0")
sc("B03", "PM: qué depende de mí", ["base"], "pm", "Q2", PM_Q2_T1)
sc("B04", "PM: qué cambió desde t0", ["base", "dos-instantes"], "pm", "Q3", PM_Q3, since="t0")
sc("B05", "PM: compromisos con fecha", ["base"], "pm", "Q4", PM_Q4_T1)
sc("B06", "Dirección: qué tengo abierto", ["base", "ruta-web"], "dir", "Q1", DIR_Q1_T1)
sc("B07", "Dirección: qué depende de mí", ["base", "ruta-web"], "dir", "Q2", DIR_Q2_T1)
sc("B08", "Dirección: qué cambió desde t0", ["base", "dos-instantes", "web"], "dir", "Q3", DIR_Q3, since="t0")
sc("B09", "Dirección: compromisos con fecha", ["base", "web"], "dir", "Q4", DIR_Q4_T1)
sc("B10", "Investigación: qué tengo abierto", ["base", "google"], "inv", "Q1", INV_Q1_T1)
sc("B11", "Investigación: qué depende de mí", ["base", "google"], "inv", "Q2", INV_Q2_T1)
sc("B12", "Investigación: qué cambió desde t0", ["base", "dos-instantes", "web"], "inv", "Q3", INV_Q3, since="t0")
sc("B13", "Investigación: compromisos con fecha", ["base", "google"], "inv", "Q4", INV_Q4_T1)
sc("B14", "Docencia: qué tengo abierto", ["base", "google", "web"], "doc", "Q1", DOC_Q1_T1)
sc("B15", "Docencia: qué depende de mí", ["base", "google", "web"], "doc", "Q2", DOC_Q2_T1)
sc("B16", "Docencia: qué cambió desde t0", ["base", "dos-instantes"], "doc", "Q3", DOC_Q3, since="t0")
sc("B17", "Docencia: compromisos con fecha", ["base", "web"], "doc", "Q4", DOC_Q4_T1)
sc("B18", "Mínima: qué tengo abierto", ["minima"], "min", "Q1", MIN_Q1)
sc("B19", "Mínima: qué depende de mí", ["minima"], "min", "Q2", MIN_Q1)
sc("B20", "Mínima: qué cambió (nada)", ["minima", "dos-instantes"], "min", "Q3", [], since="t0")
sc("B21", "Mínima: compromisos (ninguno con fecha)", ["minima"], "min", "Q4", [])
sc("B22", "Instalación sin fuentes: nada y lo dice", ["minima"], "min-vacia", "Q2", [],
   expect_adapters={"m365-mail": "not_configured", "github": "not_configured", "jira": "not_configured"})

# Esperando mi respuesta (≥ 8)
sc("W01", "Hilo dirigido a mí sin respuesta", ["esperando"], "pm", "Q2", [aw("pm-th01","pm-m01")], filter=awf("pm-th01@"))
sc("W02", "Respondido desde el móvil (enviados)", ["esperando", "otro-cliente"], "pm", "Q2", [], filter=awf("pm-th02@"))
sc("W03", "Respondí a todos y otra persona respondió a todos conmigo en Para", ["esperando", "responder-a-todos"], "pm", "Q2", [aw("pm-th03","pm-m06")], filter=awf("pm-th03@"))
sc("W04", "Solo en CC", ["esperando"], "pm", "Q2", [], filter=awf("pm-th04@"))
sc("W05", "Reenvío mío en la misma conversación", ["esperando", "reenvio"], "pm", "Q2", [], filter=awf("pm-th05@"))
sc("W06", "Reenvío mío en conversación nueva: el original sigue esperando", ["esperando", "reenvio"], "pm", "Q2", [aw("pm-th06","pm-m10")], filter=awf("pm-th06"))
sc("W07", "Mi respuesta es anterior al último mensaje entrante", ["esperando"], "pm", "Q2", [aw("pm-th07","pm-m14")], filter=awf("pm-th07@"))
sc("W08", "Mensaje a mí mismo", ["esperando"], "pm", "Q2", [], filter=awf("pm-th08@"))
sc("W09", "Dirigido a una lista, no a mí", ["esperando"], "pm", "Q2", [], filter=awf("pm-th09@"))
sc("W10", "Esperando en t0", ["esperando", "dos-instantes"], "pm", "Q2", [aw("pm-th11","pm-m19")], at="t0", filter=awf("pm-th11@"))
sc("W11", "Respondido desde otro cliente entre t0 y t1", ["esperando", "otro-cliente", "dos-instantes"], "pm", "Q2", [], filter=awf("pm-th11@"))
sc("W12", "Gmail: respondido desde el móvil", ["esperando", "otro-cliente", "google"], "inv", "Q2", [], filter=awf("inv-t02@"))
sc("W13", "Gmail: respondí a todos y luego me dejan en CC", ["esperando", "responder-a-todos", "google"], "inv", "Q2", [], filter=awf("inv-t03@"))
sc("W14", "Gmail: reenvío en el mismo hilo", ["esperando", "reenvio", "google"], "doc", "Q2", [], filter=awf("doc-t02@"))
sc("W15", "Gmail: nueva pregunta tras mi respuesta", ["esperando", "google"], "doc", "Q2", [gaw("doc-t04","doc-g07")], filter=awf("doc-t04@"))
sc("W16", "Ruta web: respondido desde Outlook de escritorio", ["esperando", "otro-cliente", "ruta-web"], "dir", "Q2", [], filter=awf("dir-th02@"))

# Revocación y libro
T0SNAP = {"do": "snapshot", "at": "t0"}
def corr(key, action="revoke", **kw): return dict({"do": "correct", "key": key, "action": action, "at": "t0"}, **kw)
sc("R01", "Revocado no vuelve aunque la fuente lo repita", ["revocacion"], "pm", "Q2", [],
   filter=awf("pm-th01@"), steps=[T0SNAP, corr(aw("pm-th01","pm-m01"))])
sc("R02", "«No aplica» sobre una tarea de Jira", ["revocacion"], "pm", "Q1",
   [jira(k) for k in ["PMX-1","PMX-5","PMX-6","PMX-7","PMX-8","PMX-9"]],
   filter={"types": ["task_assigned"], "adapters": ["jira"]}, steps=[T0SNAP, corr(jira("PMX-4"))])
sc("R03", "Hilo resuelto que recibe un mensaje nuevo: hecho nuevo, clave nueva", ["revocacion", "esperando"], "pm", "Q2",
   [aw("pm-th12","pm-m22")], filter=awf("pm-th12@"), steps=[T0SNAP, corr(aw("pm-th12","pm-m21"))])
sc("R04", "Sustituido no vuelve", ["revocacion"], "pm", "Q2",
   [jira(k) for k in ["PMX-4","PMX-5","PMX-6","PMX-7","PMX-8","PMX-9"]],
   filter={"types": ["task_assigned"], "adapters": ["jira"]},
   steps=[T0SNAP, corr(jira("PMX-1"), "supersede", superseded_by=jira("PMX-6"))])
sc("R05", "Revocar y restaurar", ["revocacion"], "pm", "Q2", [aw("pm-th07","pm-m14")], filter=awf("pm-th07@"),
   steps=[T0SNAP, corr(aw("pm-th07","pm-m14")), corr(aw("pm-th07","pm-m14"), "restore")])
sc("R06", "Revocado después de t0 no sale como «desaparecido» en Q3", ["revocacion", "dos-instantes"], "pm", "Q3",
   PM_Q3, since="t0", steps=[corr(aw("pm-th01","pm-m01"))])

# Cambio de perfil
sc("P01", "Cambio de perfil PM → dirección en la misma instalación", ["perfil"], "dir", "Q2", DIR_Q2_T1,
   steps=[dict(T0SNAP, install="pm"), dict(corr(jira("PMX-4")), install="pm")])
sc("P02", "Vuelta a PM: su libro sigue y el de dirección no le afecta", ["perfil", "revocacion"], "pm", "Q2",
   [jira(k) for k in ["PMX-1","PMX-5","PMX-6","PMX-7","PMX-8","PMX-9"]],
   filter={"types": ["task_assigned"], "adapters": ["jira"]},
   steps=[T0SNAP, corr(jira("PMX-4")), dict(T0SNAP, install="dir"), dict(corr(jira("PMX-1")), install="dir")])
sc("P03", "Q3 contra la instantánea de otro operador se rechaza", ["perfil", "dos-instantes"], "dir", "Q3",
   since="t0", previous_install="pm", expect_error=True)

# Terceros
sc("T01", "Calendario delegado de otra persona: no se lee", ["terceros"], "pm", "Q1",
   [mt("pm-e02"), mt("pm-e03"), mt("pm-e08")], filter={"types": ["meeting"]})
sc("T02", "Buzón compartido: no es mi bandeja", ["terceros", "esperando"], "pm", "Q2", PM_AW_T1, filter=AW)
sc("T03", "Tarea de una colega y revisión pedida a otra persona", ["terceros"], "pm", "Q2",
   PM_JIRA_T1 + [gh("review_request","pm-portal",12), gh("task_assigned","pm-portal",14), gh("mention","pm-portal",15)],
   filter={"adapters": ["jira", "github"]})

# Inyección
sc("I01", "Asunto con instrucciones, controles y HTML: dato inerte", ["inyeccion"], "pm", "Q2",
   [aw("pm-th19","pm-m29")], filter=awf("pm-th19@"))
sc("I02", "Mensaje de chat que pide revocar otro hecho: no revoca nada", ["inyeccion"], "pm", "Q2",
   PM_AW_T1 + ["m365-teams:mention:pm-cm01", "m365-teams:mention:pm-cm05"],
   filter={"types": ["awaiting_reply", "mention"], "adapters": ["m365-mail", "m365-teams"]})
sc("I03", "Comentario que pide resolver todo: el documento sigue abierto", ["inyeccion"], "pm", "Q1",
   ["m365-files:document_comments:pm-f01", "m365-files:document_comments:pm-f03"], filter={"types": ["document_comments"]})
sc("I04", "Resumen de Jira con HTML, enlace y bidi", ["inyeccion"], "pm", "Q1", [jira("PMX-9")],
   filter={"adapters": ["jira"], "ref_prefix": "PMX-9"})
sc("I05", "Gmail: asunto con instrucciones", ["inyeccion", "google"], "doc", "Q2", [gaw("doc-t05","doc-g08")], filter=awf("doc-t05@"))
sc("I06", "Comentario con HTML en Drive", ["inyeccion", "google"], "doc", "Q1",
   ["google-workspace:document_comments:doc-d01", "google-workspace:document_comments:doc-d02"], filter={"types": ["document_comments"]})
sc("I07", "Fila web con instrucciones y no asignada: no entra ni actúa", ["inyeccion", "web"], "dir", "Q2",
   [web("task_assigned","aprobaciones","ap-2")], filter={"adapters": ["web"]})

# Consentimiento de administración
sc("A01", "Inquilino que exige consentimiento de administración: Q1 sin correo y lo dice", ["consentimiento-admin"], "dir-graph", "Q1",
   [mt("dir-e01"), mt("dir-e02")] + DIR_WORK_T1,
   expect_adapters={"m365-mail": "admin_consent_required", "m365-teams": "admin_consent_required", "m365-calendar": "ok"},
   expect_fallback={"m365-mail": "web", "m365-teams": "web"})
sc("A02", "Consentimiento de administración: Q2 solo con lo que sí se puede leer", ["consentimiento-admin"], "dir-graph", "Q2",
   DIR_WORK_T1, expect_adapters={"m365-mail": "admin_consent_required", "m365-teams": "admin_consent_required"})
sc("A03", "Ruta web como alternativa legítima", ["consentimiento-admin", "ruta-web"], "dir", "Q2", DIR_AW_T1,
   filter={"adapters": ["m365-mail"]}, expect_adapters={"m365-mail": "ok"})

# Token caducado
sc("K01", "Token de Google caducado: se dice y no se inventa", ["token-caducado"], "inv-expired", "Q1", INV_GH,
   expect_adapters={"google-workspace": "token_expired", "github": "ok"})
sc("K02", "Token caducado en t1: lo de Google no sale como «desaparecido»", ["token-caducado", "dos-instantes"], "inv-expired", "Q3",
   [web("web_page_change","revista","estado-envio")], since="t0", expect_adapters={"google-workspace": "token_expired"})
sc("K03", "Sesión web caducada en el perfil dedicado", ["token-caducado", "web"], "doc-session", "Q1",
   [gmt("doc-e01"), gmt("doc-e02")] + DOC_AW_T1
   + ["google-workspace:document_comments:doc-d01", "google-workspace:document_comments:doc-d02"],
   expect_adapters={"web": "session_expired"})

# Niveles y detalle
sc("L01", "Vista N2: lo de oficina se retiene y solo se cuenta", ["niveles"], "pm", "Q1",
   [gh("task_assigned","pm-portal",14), gh("review_request","pm-portal",12)], max_level="N2", expect_withheld=24)
sc("L02", "Recuentos: solo cifras", ["niveles", "recuentos"], "pm", "Q1", detail="recuentos",
   expect_counts={"meeting": 3, "task_assigned": 8, "review_request": 1, "awaiting_reply": 12, "document_comments": 2})
sc("L03", "Títulos: sin atributos", ["niveles"], "dir", "Q2", DIR_Q2_T1, detail="titulos")
sc("L04", "Recuentos en docencia", ["niveles", "recuentos"], "doc", "Q2", detail="recuentos",
   expect_counts={"awaiting_reply": 3, "task_assigned": 2})

# TTL, consentimiento revocado, configuración incoherente
sc("E01", "Instantánea caducada no se usa", ["ttl"], "pm", "Q1", at="t1", reuse_snapshot="t0", expect_error=True)
sc("C01", "Consentimiento de Teams revocado: sus menciones no salen", ["consentimiento"], "pm-teams-revoked", "Q2",
   [gh("mention","pm-portal",15)], filter={"types": ["mention"]}, expect_adapters={"m365-teams": "consent_revoked"})
sc("D01", "Adaptador duplicado o desconocido: fail-closed", ["configuracion"], "pm-dup", "Q2", [],
   filter={"adapters": ["jira"]}, expect_adapters={"jira": "duplicate_adapter", "slack": "unknown_adapter"})

# Remitente suplantado (AC-4c)
sc("S01", "Graph: CFO autenticado alerta; suplantado y de otro inquilino no; inyección URGENTE no", ["ac4c", "inyeccion"], "pm", "ALERT",
   expect_alerts=[aw("pm-th13","pm-m23"), aw("pm-th16","pm-m26")], expect_notices=[])
sc("S02", "Ruta web: el mismo remitente solo da aviso, nunca alerta", ["ac4c", "ruta-web"], "pm-web", "ALERT",
   expect_alerts=[], expect_notices=[aw("pm-th13","pm-m23"), aw("pm-th14","pm-m24"), aw("pm-th15","pm-m25"), aw("pm-th16","pm-m26")])
sc("S03", "Ruta web en dirección: regla de remitente degradada a aviso", ["ac4c", "ruta-web"], "dir", "ALERT",
   expect_alerts=[], expect_notices=[aw("dir-th03","dir-m04")])
sc("S04", "Google: DKIM/DMARC superados alerta; fallidos no", ["ac4c", "google"], "inv", "ALERT",
   expect_alerts=[gaw("inv-t06","inv-g09")], expect_notices=[])

# Fuentes concretas
sc("F01", "Correo marcado con fecha como compromiso", ["q4"], "pm", "Q4", ["m365-mail:dated_commitment:pm-m27"],
   filter={"types": ["dated_commitment"]})
sc("F02", "Reunión cancelada en t1 sale de Q1", ["dos-instantes"], "pm", "Q1", [], filter={"types": ["meeting"], "ref_prefix": "pm-e05"})
sc("F03", "Reunión movida: cambia la fecha", ["q4"], "pm", "Q4", [mt("pm-e08")], filter={"types": ["meeting"], "ref_prefix": "pm-e08"})
sc("F04", "Azure DevOps: revisión con voto emitido no cuenta", ["ado"], "dir", "Q2", [adopr("cartera-api",7)],
   filter={"types": ["review_request"]})
sc("F05", "GitHub: asignada y mencionada cuenta una vez, como tarea", ["github"], "inv", "Q2",
   [gh("task_assigned","inv-lab",4), gh("task_assigned","inv-lab",5), gh("mention","inv-lab",6)],
   filter={"types": ["task_assigned", "mention"], "adapters": ["github"]})
sc("F06", "Menciones de chat: antigua o ya contestada no cuentan", ["teams"], "pm", "Q2", ["m365-teams:mention:pm-cm01"],
   at="t0", filter={"types": ["mention"], "adapters": ["m365-teams"]})

ids = [s["id"] for s in S]
assert len(ids) == len(set(ids)), "ids duplicados"
out = {"_doc": __doc__.strip().splitlines()[0], "instants": {"t0": "2026-11-02T08:00:00Z", "t1": "2026-11-03T08:00:00Z"},
       "scenarios": S}
Path(__file__).with_name("scenarios.json").write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
qs = {}
for s in S: qs[s["ask"]["q"]] = qs.get(s["ask"]["q"], 0) + 1
print(len(S), "escenarios", qs, "esperando:", sum("esperando" in s["tags"] for s in S))
