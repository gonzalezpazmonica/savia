"""SE-518 S1: contratos, lanzador, `pulse status` y canal de respaldo.

Stdlib pura (unittest). Cada comportamiento tiene su caso negativo; el reloj no
se inyecta: los casos «vencido» escriben fechas pasadas en los ficheros.
"""
import datetime as dt
import json
import os
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
sys.path.insert(0, PROJECT)

from pulse import backup, events, schema, status, store  # noqa: E402
from pulse.store import EntradaInvalida, PulseError  # noqa: E402

BIN = os.path.join(PROJECT, "bin", "pulse")
UTC = dt.timezone.utc


def leer(path, mode="r"):
    with open(path, mode, **({} if "b" in mode else {"encoding": "utf-8"})) as fh:
        return fh.read()


def ts(delta_s=0):
    return store.fmt(dt.datetime.now(UTC) + dt.timedelta(seconds=delta_s))


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = os.path.join(self._tmp.name, "pulse")
        store.ensure_dir(self.root)
        self.env = dict(os.environ, PULSE_DATA_DIR=self.root)
        self._old = os.environ.get("PULSE_DATA_DIR")
        os.environ["PULSE_DATA_DIR"] = self.root
        self.addCleanup(self._restore)

    def _restore(self):
        if self._old is None:
            os.environ.pop("PULSE_DATA_DIR", None)
        else:
            os.environ["PULSE_DATA_DIR"] = self._old

    def cli(self, *args, env=None, timeout=60):
        return subprocess.run([BIN] + list(args), env=env or self.env, capture_output=True,
                              text=True, timeout=timeout)

    def write(self, name, data, mode=0o600):
        path = os.path.join(self.root, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(data if isinstance(data, str) else json.dumps(data))
        os.chmod(path, mode)
        return path

    def presencia(self, at_delta=0, hasta_delta=120, mode=0o600):
        self.write("presencia.json", {"schema_version": "1", "at": ts(at_delta),
                                      "valid_until": ts(hasta_delta)}, mode)

    def ledger(self):
        est, evs, rej = events.read_ledger(self.root)
        self.assertEqual(est, store.OK)
        self.assertEqual(rej, [])
        return evs

    def peticion(self, pid, **kw):
        base = {"id": pid, "fuente": "AVISO_RUN", "nivel": "N4", "critica": False, "desde": ts(),
                "que": "Algo que mirar " + pid, "por_que_ahora": "x", "si_no_contestas": "y",
                "si_aplazas": "z", "caduca": ts(3600)}
        base.update(kw)
        return base

    def publica(self, *pets):
        self.write("peticiones.json", {"schema_version": "1", "at": ts(), "peticiones": list(pets)})


class Contratos(Base):
    EVENTO_OK = {"schema_version": "1", "id": "ev-0123456789abcdef", "tipo": "job_started",
                 "at": "2026-11-14T10:00:00Z", "clase": "ninguna", "entrega": "ninguna", "nivel": "N4",
                 "job_id": "w1", "intento": 1}

    def v(self, name, doc):
        return schema.validate(doc, schema.load_schema(name))

    def test_cada_contrato_acepta_su_ejemplo(self):
        self.assertEqual(self.v("evento", self.EVENTO_OK), [])
        self.assertEqual(self.v("latido", {"schema_version": "1", "at": ts(), "valid_until": ts(60),
                                           "pasada": 3, "fuentes_vencidas": ["forge"]}), [])
        self.assertEqual(self.v("presencia", {"schema_version": "1", "at": ts(), "valid_until": ts(60)}), [])
        self.assertEqual(self.v("acuse", {"schema_version": "1", "id": "aviso-run-w1-1", "canal": "movil", "at": ts()}), [])
        self.assertEqual(self.v("peticiones", {"schema_version": "1", "at": ts(), "peticiones": [self.peticion("p1")]}), [])

    def test_campo_ausente_se_rechaza_en_cada_contrato(self):
        casos = {
            "evento": dict(self.EVENTO_OK),
            "latido": {"schema_version": "1", "at": ts(), "valid_until": ts(60), "pasada": 1, "fuentes_vencidas": []},
            "presencia": {"schema_version": "1", "at": ts(), "valid_until": ts(60)},
            "acuse": {"schema_version": "1", "id": "a", "canal": "c", "at": ts()},
        }
        for name, doc in casos.items():
            for key in list(doc):
                mutado = {k: v for k, v in doc.items() if k != key}
                self.assertTrue(self.v(name, mutado), "%s sin %s debía fallar" % (name, key))
        pet = self.peticion("p1")
        for key in pet:
            mutada = {k: v for k, v in pet.items() if k != key}
            doc = {"schema_version": "1", "at": ts(), "peticiones": [mutada]}
            self.assertTrue(self.v("peticiones", doc), "petición sin %s debía fallar" % key)

    def test_nivel_ausente_o_fuera_de_conjunto_se_rechaza(self):
        for bad in (None, "N5", "n4", ""):
            doc = dict(self.EVENTO_OK)
            if bad is None:
                del doc["nivel"]
            else:
                doc["nivel"] = bad
            self.assertTrue(self.v("evento", doc), repr(bad))

    def test_version_mayor_distinta_rechazada_y_campos_nuevos_ignorados(self):
        self.assertTrue(self.v("evento", dict(self.EVENTO_OK, schema_version="2")))
        self.assertEqual(self.v("evento", dict(self.EVENTO_OK, schema_version="1.4", campo_futuro="x")), [])

    def test_salto_de_linea_final_no_cuela_en_patrones(self):
        self.assertTrue(self.v("evento", dict(self.EVENTO_OK, job_id="w1\n")))
        self.assertTrue(self.v("acuse", {"schema_version": "1", "id": "a\n", "canal": "c", "at": ts()}))

    def test_tipos_no_se_confunden(self):
        self.assertTrue(self.v("evento", dict(self.EVENTO_OK, intento=True)))
        self.assertTrue(self.v("evento", dict(self.EVENTO_OK, intento="1")))
        self.assertTrue(self.v("latido", {"schema_version": "1", "at": ts(), "valid_until": ts(1),
                                          "pasada": 1.5, "fuentes_vencidas": []}))

    def test_campos_por_tipo_de_evento(self):
        fin = dict(self.EVENTO_OK, tipo="job_finished", job_id="w1", intento=1, rc=0, resultado="ok",
                   peticion_id="aviso-run-w1-1")
        self.assertEqual(self.v("evento", fin), [])
        for key in ("rc", "resultado", "peticion_id"):
            self.assertTrue(self.v("evento", {k: v for k, v in fin.items() if k != key}), key)
        self.assertTrue(self.v("evento", dict(fin, rc=256)))
        self.assertTrue(self.v("evento", dict(fin, resultado="bien")))
        self.assertTrue(self.v("evento", dict(self.EVENTO_OK, tipo="job_beat")))  # sin seq ni fase
        self.assertTrue(self.v("evento", dict(self.EVENTO_OK, tipo="inventado")))
        self.assertTrue(self.v("evento", dict(self.EVENTO_OK, tipo="pr_merged")))  # sin propuesta

    def test_validador_rechaza_palabras_clave_que_no_soporta(self):
        with self.assertRaises(schema.SchemaNoSoportado):
            schema.validate({"a": 1}, {"type": "object", "additionalProperties": False})

    def test_todos_los_esquemas_usan_solo_palabras_soportadas(self):
        for name in ("evento", "peticiones", "latido", "presencia", "acuse"):
            schema.validate({}, schema.load_schema(name))  # no lanza

    def test_cli_validate(self):
        buena = self.write("e.jsonl", json.dumps(self.EVENTO_OK) + "\n")
        self.assertEqual(self.cli("validate", "evento", buena).returncode, 0)
        mala = self.write("m.jsonl", json.dumps(self.EVENTO_OK) + "\n" + json.dumps(dict(self.EVENTO_OK, nivel="X")) + "\n")
        r = self.cli("validate", "evento", mala)
        self.assertEqual(r.returncode, 1)
        self.assertIn("2:", r.stderr)
        vacio = self.write("v.jsonl", "")
        self.assertEqual(self.cli("validate", "evento", vacio).returncode, 1)


class Almacen(Base):
    def lat(self):
        return {"schema_version": "1", "at": ts(), "valid_until": ts(60), "pasada": 1, "fuentes_vencidas": []}

    def test_ausente_corrupto_y_vacio(self):
        p = os.path.join(self.root, "latido.json")
        self.assertEqual(store.read_json(p, "latido")[0], store.SIN_CONECTAR)
        self.write("latido.json", "{no json")
        self.assertEqual(store.read_json(p, "latido")[0], store.FALLIDA)
        self.write("latido.json", "")
        self.assertEqual(store.read_json(p, "latido")[0], store.FALLIDA)  # nunca «vacío»
        self.write("latido.json", "{}")
        self.assertEqual(store.read_json(p, "latido")[0], store.FALLIDA)
        self.write("latido.json", self.lat())
        self.assertEqual(store.read_json(p, "latido")[0], store.OK)

    def test_escribible_por_grupo_u_otros_es_fallida(self):
        for mode in (0o620, 0o602, 0o666):
            self.write("latido.json", self.lat(), mode)
            est, motivo = store.read_json(os.path.join(self.root, "latido.json"), "latido")
            self.assertEqual(est, store.FALLIDA, oct(mode))
        self.write("latido.json", self.lat(), 0o644)  # legible por otros no es escribible
        self.assertEqual(store.read_json(os.path.join(self.root, "latido.json"), "latido")[0], store.OK)

    def test_enlace_simbolico_es_fallida(self):
        real = self.write("real.json", self.lat())
        os.symlink(real, os.path.join(self.root, "latido.json"))
        self.assertEqual(store.read_json(os.path.join(self.root, "latido.json"), "latido")[0], store.FALLIDA)

    def test_directorio_escribible_por_otros_es_fallida(self):
        self.write("latido.json", self.lat())
        os.chmod(self.root, 0o777)
        try:
            self.assertEqual(store.read_json(os.path.join(self.root, "latido.json"), "latido")[0], store.FALLIDA)
            with self.assertRaises(PulseError):
                store.ensure_dir(self.root)
        finally:
            os.chmod(self.root, 0o700)

    def test_fichero_demasiado_grande_es_fallida(self):
        self.write("latido.json", " " * (store.MAX_JSON_BYTES + 10))
        self.assertEqual(store.read_json(os.path.join(self.root, "latido.json"), "latido")[0], store.FALLIDA)

    def test_escritura_atomica_valida_y_con_permisos_privados(self):
        with self.assertRaises(PulseError):
            store.write_json_atomic(self.root, "latido.json", {"schema_version": "1"}, "latido")
        self.assertFalse(os.path.exists(os.path.join(self.root, "latido.json")))
        store.write_json_atomic(self.root, "latido.json", self.lat(), "latido")
        mode = stat.S_IMODE(os.stat(os.path.join(self.root, "latido.json")).st_mode)
        self.assertEqual(mode, 0o600)
        self.assertEqual([f for f in os.listdir(self.root) if f.startswith(".latido")], [])

    def test_lineas_ilegibles_se_cuentan_no_se_ocultan(self):
        buena = json.dumps(Contratos.EVENTO_OK)
        self.write("eventos.jsonl", buena + "\nbasura\n" + json.dumps(dict(Contratos.EVENTO_OK, nivel="X")) + "\n")
        est, recs, rej = events.read_ledger(self.root)
        self.assertEqual((est, len(recs), len(rej)), (store.OK, 1, 2))


class Lanzador(Base):
    def test_ciclo_inicio_latido_fin_con_peticion(self):
        events.job_start(self.root, "w1", heartbeat_ttl=60, propuesta="#12", modelo="m-1")
        b1 = events.job_beat(self.root, "w1", "tests")
        b2 = events.job_beat(self.root, "w1", "revision")
        self.assertEqual((b1["seq"], b2["seq"]), (1, 2))
        fin, nuevo = events.job_finish(self.root, "w1", 0)
        self.assertTrue(nuevo)
        self.assertEqual((fin["rc"], fin["clase"], fin["resultado"], fin["entrega"]), (0, "ninguna", "ok", "pendiente"))
        tipos = [e["tipo"] for e in self.ledger()]
        self.assertEqual(tipos, ["job_started", "job_beat", "job_beat", "job_finished"])
        est, snap = store.read_json(os.path.join(self.root, "peticiones.json"), "peticiones")
        self.assertEqual(est, store.OK)
        pet = snap["peticiones"][0]
        self.assertEqual((pet["id"], pet["fuente"], pet["critica"]), (fin["peticion_id"], "AVISO_RUN", False))
        self.assertGreater(store.parse_ts(pet["caduca"]), store.parse_ts(pet["desde"]))

    def test_beat_tras_fin_y_fin_sin_inicio_se_rechazan(self):
        with self.assertRaises(PulseError):
            events.job_finish(self.root, "nadie", 0)
        with self.assertRaises(PulseError):
            events.job_beat(self.root, "nadie", "x")
        events.job_start(self.root, "w1")
        events.job_finish(self.root, "w1", 0)
        antes = leer(os.path.join(self.root, "eventos.jsonl"), "rb")
        with self.assertRaises(PulseError):
            events.job_beat(self.root, "w1", "tarde")
        self.assertEqual(leer(os.path.join(self.root, "eventos.jsonl"), "rb"), antes)

    def test_primer_resultado_manda(self):
        events.job_start(self.root, "w1")
        events.job_finish(self.root, "w1", 1)
        _, nuevo = events.job_finish(self.root, "w1", 1)
        self.assertFalse(nuevo)
        with self.assertRaises(PulseError):
            events.job_finish(self.root, "w1", 0)
        self.assertEqual(len([e for e in self.ledger() if e["tipo"] == "job_finished"]), 1)

    def test_clases_por_codigo(self):
        self.assertEqual(events.classify(0), ("ninguna", "ok"))
        self.assertEqual(events.classify(143), ("entorno", "interrumpido"))
        self.assertEqual(events.classify(137), ("entorno", "interrumpido"))
        self.assertEqual(events.classify(1), ("desconocida", "fallo"))  # fail-closed
        self.assertEqual(events.classify(255), ("desconocida", "fallo"))
        self.assertEqual(events.classify(1, "cuota"), ("cuota", "fallo"))

    def test_clases_invalidas_se_rechazan(self):
        for rc, clase in ((0, "cuota"), (1, "ninguna"), (1, "inventada"), (256, None), (-1, None), (True, None), ("1", None)):
            with self.assertRaises(EntradaInvalida, msg=repr((rc, clase))):
                events.classify(rc, clase)

    def test_politica_es_critica_y_ok_no(self):
        events.job_start(self.root, "w1")
        events.job_finish(self.root, "w1", 1, "politica")
        events.job_start(self.root, "w2")
        events.job_finish(self.root, "w2", 0)
        _, snap = store.read_json(os.path.join(self.root, "peticiones.json"), "peticiones")
        crit = {p["id"]: p["critica"] for p in snap["peticiones"]}
        self.assertEqual(crit, {"aviso-run-w1-1": True, "aviso-run-w2-1": False})

    def test_reintento_exige_fin_previo_e_intento_mayor(self):
        events.job_start(self.root, "w1")
        with self.assertRaises(PulseError):
            events.job_start(self.root, "w1", intento=2)  # el anterior sigue en marcha
        events.job_finish(self.root, "w1", 143)
        with self.assertRaises(PulseError):
            events.job_start(self.root, "w1", intento=1)
        events.job_start(self.root, "w1", intento=2)
        events.job_beat(self.root, "w1", "otra vez")  # seq reinicia en el intento nuevo
        self.assertEqual(self.ledger()[-1]["seq"], 1)
        events.job_finish(self.root, "w1", 0)
        ids = {p["id"] for p in store.read_json(os.path.join(self.root, "peticiones.json"), "peticiones")[1]["peticiones"]}
        self.assertEqual(ids, {"aviso-run-w1-1", "aviso-run-w1-2"})

    def test_entradas_invalidas(self):
        for bad in ("", "a b", "a;b", "x" * 65, "w\n", "../x"):
            with self.assertRaises(EntradaInvalida, msg=repr(bad)):
                events.job_start(self.root, bad)
        events.job_start(self.root, "w1")
        for fase in ("", "x;y", "a\nb", "\"q\"", "x" * 201):
            with self.assertRaises(EntradaInvalida, msg=repr(fase)):
                events.job_beat(self.root, "w1", fase)
        events.job_beat(self.root, "w1", "a" * 80 + "b" * 100)
        self.assertEqual(len(self.ledger()[-1]["fase"]), 80)
        self.assertFalse(os.path.exists(os.path.join(self.root, "peticiones.json")))

    def test_ledger_inseguro_no_se_escribe(self):
        events.job_start(self.root, "w1")
        path = os.path.join(self.root, "eventos.jsonl")
        os.chmod(path, 0o666)
        antes = leer(path, "rb")
        with self.assertRaises(PulseError):
            events.job_finish(self.root, "w1", 0)
        with self.assertRaises(PulseError):
            events.job_start(self.root, "w2")
        self.assertEqual(leer(path, "rb"), antes)
        self.assertFalse(os.path.exists(os.path.join(self.root, "peticiones.json")))

    def test_peticiones_ilegible_no_se_sobrescribe(self):
        events.job_start(self.root, "w1")
        self.write("peticiones.json", "{roto")
        with self.assertRaises(PulseError):
            events.job_finish(self.root, "w1", 0)
        self.assertEqual(leer(os.path.join(self.root, "peticiones.json")), "{roto")

    def test_peticion_caducada_sale_de_la_instantanea(self):
        self.publica(self.peticion("vieja", caduca=ts(-10)), self.peticion("viva"))
        events.job_start(self.root, "w1")
        events.job_finish(self.root, "w1", 0)
        _, snap = store.read_json(os.path.join(self.root, "peticiones.json"), "peticiones")
        self.assertEqual(sorted(p["id"] for p in snap["peticiones"]), ["aviso-run-w1-1", "viva"])

    def test_beats_concurrentes_no_se_pisan(self):
        events.job_start(self.root, "w1")
        procs = [subprocess.Popen([BIN, "job-beat", "--job-id", "w1", "--fase", "f%d" % i], env=self.env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for i in range(10)]
        self.assertEqual([p.wait(timeout=60) for p in procs], [0] * 10)
        seqs = sorted(e["seq"] for e in self.ledger() if e["tipo"] == "job_beat")
        self.assertEqual(seqs, list(range(1, 11)))

    def test_pr_events(self):
        events.pr_event(self.root, "pr_created", "#7")
        events.pr_event(self.root, "pr_merged", "#7")
        self.assertEqual([e["tipo"] for e in self.ledger()], ["pr_created", "pr_merged"])
        with self.assertRaises(EntradaInvalida):
            events.pr_event(self.root, "pr_approved", "#7")


class LanzadorCLI(Base):
    def fin(self, job):
        return [e for e in self.ledger() if e["tipo"] == "job_finished" and e["job_id"] == job][0]

    def test_run_propaga_codigo_y_registra_inicio_y_fin(self):
        r = self.cli("run", "--job-id", "w1", "--", "sh", "-c", "exit 3")
        self.assertEqual(r.returncode, 3)
        fin = self.fin("w1")
        self.assertEqual((fin["rc"], fin["clase"], fin["resultado"]), (3, "desconocida", "fallo"))
        self.assertEqual(self.ledger()[0]["tipo"], "job_started")

    def test_run_ok(self):
        r = self.cli("run", "--job-id", "w1", "--ttl", "60", "--", "true")
        self.assertEqual(r.returncode, 0)
        self.assertEqual((self.fin("w1")["clase"], self.fin("w1")["resultado"]), ("ninguna", "ok"))

    def test_run_muerto_por_senal_es_entorno_y_no_fallo(self):
        r = self.cli("run", "--job-id", "w1", "--", "sh", "-c", "kill -TERM $$")
        self.assertEqual(r.returncode, 143)
        fin = self.fin("w1")
        self.assertEqual((fin["rc"], fin["clase"], fin["resultado"]), (143, "entorno", "interrumpido"))

    def test_sigterm_al_lanzador_se_reenvia_y_deja_fin(self):
        p = subprocess.Popen([BIN, "run", "--job-id", "w1", "--", "sleep", "60"], env=self.env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(200):
            if os.path.exists(os.path.join(self.root, "eventos.jsonl")):
                break
            time.sleep(0.05)
        time.sleep(0.5)
        p.send_signal(signal.SIGTERM)
        self.assertEqual(p.wait(timeout=30), 143)
        self.assertEqual(self.fin("w1")["clase"], "entorno")

    def test_orden_inexistente_deja_fin_127(self):
        r = self.cli("run", "--job-id", "w1", "--", "orden-que-no-existe-xyz")
        self.assertEqual(r.returncode, 127)
        self.assertEqual(self.fin("w1")["rc"], 127)

    def test_sin_inicio_registrado_no_se_lanza_la_orden(self):
        marca = os.path.join(self._tmp.name, "marca")
        os.chmod(self.root, 0o777)
        try:
            r = self.cli("run", "--job-id", "w1", "--", "touch", marca)
        finally:
            os.chmod(self.root, 0o700)
        self.assertEqual(r.returncode, 1)
        self.assertFalse(os.path.exists(marca))

    def test_run_sin_orden_o_con_id_invalido_es_entrada_invalida(self):
        self.assertEqual(self.cli("run", "--job-id", "w1").returncode, 2)
        self.assertEqual(self.cli("run", "--job-id", "a;b", "--", "true").returncode, 2)
        self.assertFalse(os.path.exists(os.path.join(self.root, "eventos.jsonl")))

    def test_subcomandos_y_codigos_de_salida(self):
        self.assertEqual(self.cli("job-start", "--job-id", "w1").returncode, 0)
        self.assertEqual(self.cli("job-beat", "--job-id", "w1", "--fase", "x;y").returncode, 2)
        self.assertEqual(self.cli("job-finish", "--job-id", "w1", "--rc", "0", "--clase", "cuota").returncode, 2)
        self.assertEqual(self.cli("job-finish", "--job-id", "w1", "--rc", "1", "--clase", "cuota").returncode, 0)
        self.assertEqual(self.cli("job-finish", "--job-id", "w1", "--rc", "0").returncode, 1)
        self.assertEqual(self.fin("w1")["clase"], "cuota")


class Estado(Base):
    def latido(self, at_delta=-30, hasta_delta=150, mode=0o600, pasada=7):
        self.write("latido.json", {"schema_version": "1", "at": ts(at_delta), "valid_until": ts(hasta_delta),
                                   "pasada": pasada, "duracion_s": 4, "fuentes_vencidas": []}, mode)

    def out(self):
        r = self.cli("status")
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def test_latido_vigente_dice_da_senales_con_edad(self):
        self.latido(at_delta=-40)
        out = self.out()
        self.assertIn("Pulse: da señales", out)
        self.assertIn("pasada 7", out)
        self.assertRegex(out, r"hace (3\d|4\d) segundos")

    def test_sin_latido_vencido_corrupto_o_inseguro_dice_sin_senales(self):
        casos = {
            "ausente": lambda: None,
            "vencido": lambda: self.latido(at_delta=-600, hasta_delta=-1),
            "justo_en_el_limite": lambda: self.latido(at_delta=-60, hasta_delta=0),
            "corrupto": lambda: self.write("latido.json", "{roto"),
            "vacio": lambda: self.write("latido.json", ""),
            "escribible_por_otros": lambda: self.latido(mode=0o666),
            "fechado_en_el_futuro": lambda: self.latido(at_delta=3600, hasta_delta=7200),
        }
        for nombre, prepara in casos.items():
            for f in os.listdir(self.root):
                if f == "latido.json":
                    os.unlink(os.path.join(self.root, f))
            prepara()
            out = self.out()
            self.assertIn("Pulse: sin señales", out, nombre)
            self.assertNotIn("da señales", out, nombre)
            self.assertNotRegex(out.lower(), r"todo (bien|en orden)", nombre)

    def test_trabajos_en_marcha_con_y_sin_senales(self):
        self.latido()
        events.job_start(self.root, "con-ttl", heartbeat_ttl=60)
        events.job_beat(self.root, "con-ttl", "tests")
        events.job_start(self.root, "sin-ttl")
        events.job_start(self.root, "mudo", heartbeat_ttl=10)
        # envejece el inicio de «mudo» reescribiendo el ledger con fechas pasadas
        path = os.path.join(self.root, "eventos.jsonl")
        lines = [json.loads(l) for l in leer(path).splitlines()]
        for ev in lines:
            if ev["job_id"] == "mudo":
                ev["at"] = ts(-300)
        with open(path, "w") as fh:
            fh.write("".join(json.dumps(e) + "\n" for e in lines))
        out = self.out()
        self.assertIn("Trabajos en marcha: 3.", out)
        self.assertRegex(out, r"con-ttl: .*dio señales hace .*\(fase: tests\)")
        self.assertRegex(out, r"sin-ttl: .*no declara latido, no sé si sigue vivo")
        self.assertRegex(out, r"mudo: .*SIN SEÑALES desde hace")

    def test_terminados_hoy_y_esperan_algo(self):
        self.latido()
        events.job_start(self.root, "a")
        events.job_finish(self.root, "a", 0)
        events.job_start(self.root, "b")
        events.job_finish(self.root, "b", 2)
        events.job_start(self.root, "c")
        events.job_finish(self.root, "c", 143)
        out = self.out()
        self.assertIn("Terminados hoy: 1 bien, 1 con fallo, 1 interrumpidos.", out)
        self.assertIn("Esperan algo de ti: 3.", out)
        self.assertIn("Freno: sin información", out)  # honesto: el freno es S4

    def test_ledger_ilegible_avisa_en_vez_de_callar(self):
        self.latido()
        events.job_start(self.root, "a")
        with open(os.path.join(self.root, "eventos.jsonl"), "a") as fh:
            fh.write("basura\n")
        self.assertIn("1 líneas del registro de eventos son ilegibles", self.out())
        os.chmod(os.path.join(self.root, "eventos.jsonl"), 0o666)
        out = self.out()
        self.assertIn("no puedo leer el registro de eventos", out)
        self.assertNotIn("Trabajos en marcha", out)

    def test_status_json_no_expone_rutas_ni_usuario(self):
        self.latido()
        events.job_start(self.root, "a")
        events.job_finish(self.root, "a", 0)
        r = self.cli("status", "--json")
        self.assertEqual(r.returncode, 0)
        json.loads(r.stdout)
        prohibidos = [self.root, self._tmp.name, os.path.expanduser("~")]
        user = os.environ.get("USER", "")
        if len(user) >= 4:  # un nombre corto («a») casaría con cualquier texto
            prohibidos.append(user)
        for prohibido in prohibidos:
            self.assertNotIn(prohibido, r.stdout)

    def test_sin_soul_pulse_funciona(self):
        # sin presencia.json: todo el ciclo y el estado funcionan
        self.assertEqual(self.cli("run", "--job-id", "w1", "--", "true").returncode, 0)
        self.assertEqual(self.cli("latido", "--pasada", "1").returncode, 0)
        self.assertIn("Soul: no ha dado nunca señales", self.out())

    def test_latido_ttl_fuera_de_rango(self):
        self.assertEqual(self.cli("latido", "--pasada", "1", "--ttl", "5").returncode, 2)
        self.assertFalse(os.path.exists(os.path.join(self.root, "latido.json")))
        # dato fuera de contrato = entrada inválida (2), como el resto de rangos (revisión #1576)
        self.assertEqual(self.cli("latido", "--pasada", "1", "--fuente-vencida", "a b").returncode, 2)


class Respaldo(Base):
    def setUp(self):
        super().setUp()
        self.avisos = []
        self.notif = lambda t, x: (self.avisos.append((t, x)) or True)

    def pendiente(self, pid="p1"):
        self.publica(self.peticion(pid))

    def respaldo_ev(self):
        return [e for e in self.ledger() if e["tipo"] == "aviso_respaldo"]

    def test_con_soul_presente_no_emite_nada(self):
        self.pendiente()
        self.presencia()
        r = backup.entregar(self.root, notificador=self.notif)
        self.assertTrue(r["soul"])
        self.assertEqual(self.avisos, [])
        self.assertFalse(os.path.exists(os.path.join(self.root, "eventos.jsonl")))

    def test_sin_soul_avisa_una_vez_marcado_y_no_repite(self):
        self.pendiente()
        for _ in range(3):
            backup.entregar(self.root, notificador=self.notif)
        self.assertEqual(len(self.avisos), 1)
        self.assertTrue(self.avisos[0][1].startswith("aviso por canal de respaldo"))
        ev = self.respaldo_ev()
        self.assertEqual(len(ev), 1)
        self.assertEqual((ev[0]["entrega"], ev[0]["ref"], ev[0]["canal_so"]), ("respaldo", "p1", "ok"))

    def test_presencia_vencida_activa_el_respaldo(self):
        self.pendiente()
        self.presencia(at_delta=-700, hasta_delta=-100)
        self.assertFalse(backup.entregar(self.root, notificador=self.notif)["soul"])
        self.assertEqual(len(self.avisos), 1)

    def test_presencia_justo_en_el_limite_cuenta_como_vencida(self):
        self.pendiente()
        self.presencia(at_delta=-60, hasta_delta=0)
        self.assertFalse(backup.presencia(self.root)[0])

    def test_presencia_con_vencimiento_lejano_cuenta_como_vencida(self):
        self.pendiente()
        self.presencia(at_delta=0, hasta_delta=3600)  # > 10 min
        self.assertFalse(backup.entregar(self.root, notificador=self.notif)["soul"])
        self.assertEqual(len(self.avisos), 1)
        self.assertTrue(backup.presencia(self.root, max_validez=7200)[0])  # el máximo es configurable

    def test_presencia_escribible_por_otros_o_corrupta_o_futura_cuenta_como_vencida(self):
        for prep in (lambda: self.presencia(mode=0o666), lambda: self.presencia(mode=0o620),
                     lambda: self.write("presencia.json", "{roto"),
                     lambda: self.presencia(at_delta=3600, hasta_delta=3660)):
            prep()
            self.assertFalse(backup.presencia(self.root)[0])
        self.presencia()
        self.assertTrue(backup.presencia(self.root)[0])

    def test_acuse_de_soul_evita_el_aviso(self):
        self.publica(self.peticion("p1"), self.peticion("p2"))
        self.write("acuses.jsonl", json.dumps({"schema_version": "1", "id": "p1", "canal": "movil", "at": ts()}) + "\n")
        backup.entregar(self.root, notificador=self.notif)
        self.assertEqual([r["ref"] for r in self.respaldo_ev()], ["p2"])

    def test_peticion_caducada_no_se_avisa(self):
        self.publica(self.peticion("vieja", caduca=ts(-5)))
        backup.entregar(self.root, notificador=self.notif)
        self.assertEqual(self.avisos, [])

    def test_tope_por_pasada(self):
        self.publica(*[self.peticion("p%d" % i) for i in range(7)])
        r1 = backup.entregar(self.root, maximo=5, notificador=self.notif)
        r2 = backup.entregar(self.root, maximo=5, notificador=self.notif)
        self.assertEqual((len(r1["avisados"]), len(r2["avisados"])), (5, 2))
        self.assertEqual(len({e["ref"] for e in self.respaldo_ev()}), 7)

    def test_sin_herramienta_de_notificacion_queda_constancia_y_el_inbox_lo_lista(self):
        self.pendiente()
        backup.entregar(self.root, notificador=lambda t, x: False)
        self.assertEqual(self.respaldo_ev()[0]["canal_so"], "no_disponible")
        self.assertIn("Algo que mirar p1", backup.inbox_text(self.root))

    def test_inbox_excluye_acusados_y_dice_la_verdad_si_no_puede_leer(self):
        self.assertIn("no ha publicado", backup.inbox_text(self.root))
        self.publica(self.peticion("p1"), self.peticion("p2"))
        self.write("acuses.jsonl", json.dumps({"schema_version": "1", "id": "p1", "canal": "movil", "at": ts()}) + "\n")
        txt = backup.inbox_text(self.root)
        self.assertIn("p2", txt)
        self.assertNotIn("p1", txt)
        for etiqueta in ("Por qué ahora", "Si no contestas", "Si aplazas", "Vale hasta"):
            self.assertIn(etiqueta, txt)
        self.write("peticiones.json", "{roto")
        self.assertIn("No asumas que no hay nada", backup.inbox_text(self.root))

    def test_acuses_ilegibles_no_silencian_el_respaldo(self):
        self.pendiente()
        self.write("acuses.jsonl", "basura\n", 0o666)
        backup.entregar(self.root, notificador=self.notif)
        self.assertEqual(len(self.avisos), 1)

    def test_cli_deliver_sanea_el_texto_y_no_usa_shell(self):
        fake = os.path.join(self._tmp.name, "bin")
        os.makedirs(fake)
        salida = os.path.join(self._tmp.name, "args.txt")
        script = os.path.join(fake, "notify-send")
        with open(script, "w") as fh:
            fh.write('#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a" >> "%s"; done\n' % salida)
        os.chmod(script, 0o755)
        self.publica(self.peticion("p1", que="uno\x07; touch /tmp/pwned-pulse $(id)\ndos"))
        env = dict(self.env, PATH=fake + os.pathsep + os.environ["PATH"])
        r = self.cli("deliver", env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        args = leer(salida).split("\n")
        self.assertEqual(args[0], "--")
        cuerpo = args[2]
        self.assertTrue(cuerpo.startswith("aviso por canal de respaldo"))
        self.assertNotIn("\x07", cuerpo)
        self.assertFalse(os.path.exists("/tmp/pwned-pulse"))

    def test_cli_deliver_con_soul_presente_no_llama_al_notificador(self):
        fake = os.path.join(self._tmp.name, "bin")
        os.makedirs(fake)
        marca = os.path.join(self._tmp.name, "llamado")
        script = os.path.join(fake, "notify-send")
        with open(script, "w") as fh:
            fh.write('#!/bin/sh\ntouch "%s"\n' % marca)
        os.chmod(script, 0o755)
        self.pendiente()
        self.presencia()
        r = self.cli("deliver", env=dict(self.env, PATH=fake + os.pathsep + os.environ["PATH"]))
        self.assertIn("Soul presente: no emito nada", r.stdout)
        self.assertFalse(os.path.exists(marca))


class Revision1576(Base):
    """Hallazgos de la revisión independiente de la PR #1576."""

    def fines(self, job="w1"):
        return [e for e in self.ledger() if e["tipo"] == "job_finished" and e["job_id"] == job]

    def ids_peticiones(self):
        est, snap = store.read_json(os.path.join(self.root, "peticiones.json"), "peticiones")
        self.assertEqual(est, store.OK)
        return {p["id"] for p in snap["peticiones"]}

    # P1-1: el respaldo no notifica con el cerrojo de escritor cogido
    def test_respaldo_no_tiene_el_cerrojo_de_escritor_mientras_notifica(self):
        self.publica(self.peticion("p1"))
        pudo = []

        def notif_lento(_t, _x):
            try:
                with store.lock(self.root, timeout=0.3):
                    pudo.append(True)
            except PulseError:
                pudo.append(False)
            return True
        backup.entregar(self.root, notificador=notif_lento)
        self.assertEqual(pudo, [True])

    def test_fin_de_trabajo_durante_la_notificacion_se_registra(self):
        events.job_start(self.root, "w1")
        self.publica(self.peticion("p1"))
        backup.entregar(self.root, notificador=lambda t, x: events.job_finish(self.root, "w1", 0) and True)
        self.assertEqual(len(self.fines()), 1)

    def test_dos_pasadas_a_la_vez_no_avisan_dos_veces(self):
        self.publica(self.peticion("p1"))
        avisos = []
        with store.lock(self.root, name=backup.DELIVER_LOCK):
            with self.assertRaises(PulseError):
                backup.entregar(self.root, notificador=lambda t, x: avisos.append(x) or True)
        self.assertEqual(avisos, [])
        self.assertEqual(self.cli("deliver").returncode, 0)  # libre otra vez

    def test_acusada_durante_la_pasada_no_se_avisa(self):
        self.publica(self.peticion("p1"), self.peticion("p2"))
        avisos = []

        def notif(_t, x):
            avisos.append(x)
            self.write("acuses.jsonl", json.dumps({"schema_version": "1", "id": "p2", "canal": "soul",
                                                   "at": ts()}) + "\n")
            return True
        backup.entregar(self.root, notificador=notif)
        self.assertEqual(len(avisos), 1)
        self.assertEqual([e["ref"] for e in self.ledger() if e["tipo"] == "aviso_respaldo"], ["p1"])

    # P1-2: fin y petición juntos
    def test_peticiones_ilegible_no_deja_fin_huerfano_y_el_reintento_completa(self):
        events.job_start(self.root, "w1")
        self.write("peticiones.json", "{roto")
        with self.assertRaises(PulseError):
            events.job_finish(self.root, "w1", 0)
        self.assertEqual(self.fines(), [])  # nada anotado
        os.unlink(os.path.join(self.root, "peticiones.json"))
        _ev, nuevo = events.job_finish(self.root, "w1", 0)
        self.assertTrue(nuevo)
        self.assertEqual(self.ids_peticiones(), {"aviso-run-w1-1"})

    def test_fin_anotado_sin_peticion_se_repara_al_reintentar(self):
        events.job_start(self.root, "w1")
        events.job_finish(self.root, "w1", 3)
        os.unlink(os.path.join(self.root, "peticiones.json"))  # p. ej. el disco falló al escribirla
        ev, nuevo = events.job_finish(self.root, "w1", 3)
        self.assertFalse(nuevo)
        self.assertEqual(len(self.fines()), 1)
        self.assertEqual(self.ids_peticiones(), {"aviso-run-w1-1"})
        _, snap = store.read_json(os.path.join(self.root, "peticiones.json"), "peticiones")
        self.assertIn("código 3", snap["peticiones"][0]["por_que_ahora"])

    def test_cli_peticiones_ilegible_dice_la_verdad(self):
        self.write("peticiones.json", "{roto")
        r = self.cli("run", "--job-id", "w1", "--", "true")
        self.assertIn("no se registró el fin", r.stderr)
        self.assertEqual(self.fines(), [])

    # P2: fechas con forma válida pero imposibles, NaN, JSON muy anidado
    def test_fechas_imposibles_son_fallida_y_no_revientan(self):
        self.publica(self.peticion("p1", caduca="2026-02-30T00:00:00Z"))
        self.assertEqual(store.read_json(os.path.join(self.root, "peticiones.json"), "peticiones")[0], store.FALLIDA)
        for cmd in (("status",), ("status", "--json"), ("inbox",), ("deliver",)):
            r = self.cli(*cmd)
            self.assertEqual(r.returncode, 0, (cmd, r.stderr))
            self.assertNotIn("Traceback", r.stderr)
        self.assertIn("No puedo leer la lista de pendientes", self.cli("inbox").stdout)

    def test_evento_con_fecha_imposible_se_rechaza_y_se_cuenta(self):
        events.job_start(self.root, "w1")
        with open(os.path.join(self.root, "eventos.jsonl"), "a") as fh:
            fh.write(json.dumps({"schema_version": "1", "id": "ev-0123456789abcdef", "tipo": "job_started",
                                 "at": "2026-13-45T10:00:00Z", "clase": "ninguna", "entrega": "ninguna",
                                 "nivel": "N4", "job_id": "w2", "intento": 1}) + "\n")
        est, evs, rej = events.read_ledger(self.root)
        self.assertEqual((est, len(evs), len(rej)), (store.OK, 1, 1))
        self.assertIn("fecha imposible", rej[0])
        r = self.cli("status")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("1 líneas del registro de eventos son ilegibles", r.stdout)

    def test_formato_desconocido_falla_cerrado(self):
        with self.assertRaises(schema.SchemaNoSoportado):
            schema.validate("x", {"type": "string", "format": "email"})
        self.assertEqual(schema.validate("2026-02-28T23:59:59Z", {"type": "string", "format": "date-time"}), [])
        self.assertEqual(len(schema.validate("2026-02-29T00:00:00Z", {"type": "string", "format": "date-time"})), 1)

    def test_presencia_con_fecha_imposible_no_cuenta(self):
        self.write("presencia.json", {"schema_version": "1", "at": ts(), "valid_until": "2026-11-31T00:00:00Z"})
        self.assertFalse(backup.presencia(self.root)[0])

    def test_duracion_nan_o_infinita_es_entrada_invalida(self):
        for val in ("nan", "inf", "-inf"):
            r = self.cli("latido", "--pasada", "1", "--duracion", val)
            self.assertEqual(r.returncode, 2, val)
        self.assertFalse(os.path.exists(os.path.join(self.root, "latido.json")))
        self.assertEqual(self.cli("latido", "--pasada", "1", "--duracion", "1.5").returncode, 0)

    def test_latido_con_nan_en_disco_es_sin_senales(self):
        self.write("latido.json", '{"schema_version": "1", "at": "%s", "valid_until": "%s", "pasada": 1, '
                                  '"duracion_s": NaN, "fuentes_vencidas": []}' % (ts(-5), ts(100)))
        r = self.cli("status")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Pulse: sin señales", r.stdout)

    def test_json_muy_anidado_es_fallida(self):
        self.write("peticiones.json", "[" * 200000)
        self.assertEqual(store.read_json(os.path.join(self.root, "peticiones.json"), "peticiones")[0], store.FALLIDA)
        self.write("acuses.jsonl", "[" * 60000 + "\n")
        est, recs, rej = store.read_jsonl(os.path.join(self.root, "acuses.jsonl"), "acuse")
        self.assertEqual((est, recs, len(rej)), (store.OK, [], 1))

    # P2: códigos de salida coherentes con el 2 documentado
    def test_rangos_fuera_de_contrato_salen_con_2(self):
        for args in (("job-start", "--job-id", "w1", "--intento", "0"),
                     ("job-start", "--job-id", "w1", "--ttl", "5"),
                     ("latido", "--pasada", "-1")):
            self.assertEqual(self.cli(*args).returncode, 2, args)
        self.assertFalse(os.path.exists(os.path.join(self.root, "eventos.jsonl")))
        self.assertFalse(os.path.exists(os.path.join(self.root, "latido.json")))

    # P2: una señal antes de lanzar no mata a Pulse sin fin y no lanza la orden
    def test_senal_antes_de_lanzar_deja_fin_y_no_lanza(self):
        from pulse import cli
        marca = os.path.join(self._tmp.name, "marca")
        real = events.job_start

        def start_y_senal(*a, **k):
            ev = real(*a, **k)
            os.kill(os.getpid(), signal.SIGTERM)
            return ev
        ns = cli._p().parse_args(["run", "--job-id", "w1", "--", "touch", marca])
        events.job_start = start_y_senal
        try:
            rc = cli._run(self.root, ns)
        finally:
            events.job_start = real
        self.assertEqual(rc, 143)
        self.assertFalse(os.path.exists(marca))
        self.assertEqual((self.fines()[0]["clase"], self.fines()[0]["resultado"]), ("entorno", "interrumpido"))
        self.assertIs(signal.getsignal(signal.SIGTERM), signal.SIG_DFL)  # manejadores restaurados


class Revision1576b(Base):
    """Segunda revisión independiente de la PR #1576 (cabeza 4c0c224)."""

    def setUp(self):
        super().setUp()
        self.avisos = []
        self.notif = lambda t, x: (self.avisos.append(x) or True)

    def aviso_evs(self):
        return [e for e in self.ledger() if e["tipo"] == "aviso_respaldo"]

    def fake_notify(self, rc=0):
        fake = os.path.join(self._tmp.name, "bin")
        os.makedirs(fake, exist_ok=True)
        self.marca = os.path.join(self._tmp.name, "notificado")
        with open(os.path.join(fake, "notify-send"), "w") as fh:
            fh.write('#!/bin/sh\necho x >> "%s"\nexit %d\n' % (self.marca, rc))
        os.chmod(os.path.join(fake, "notify-send"), 0o755)
        return dict(self.env, PATH=fake + os.pathsep + os.environ["PATH"])

    # P1-1: ledger ilegible => no se notifica (ni se repite en cada pasada) y sale con 1
    def test_ledger_ilegible_el_respaldo_no_avisa_y_sale_con_1(self):
        self.publica(self.peticion("p1"))
        events.job_start(self.root, "w0")
        os.chmod(os.path.join(self.root, "eventos.jsonl"), 0o666)
        for _ in range(3):
            with self.assertRaises(PulseError):
                backup.entregar(self.root, notificador=self.notif)
        self.assertEqual(self.avisos, [])
        r = self.cli("deliver", env=self.fake_notify())
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("ledger", r.stderr)
        self.assertFalse(os.path.exists(self.marca))

    def test_ledger_que_se_estropea_a_mitad_de_pasada_corta_los_avisos(self):
        self.publica(self.peticion("p1"), self.peticion("p2"))

        def notif(_t, x):
            self.avisos.append(x)
            return True
        real = store.append_jsonl

        def append_y_estropea(*a, **k):
            real(*a, **k)
            os.chmod(os.path.join(self.root, "eventos.jsonl"), 0o666)
        store.append_jsonl = append_y_estropea
        try:
            with self.assertRaises(PulseError):
                backup.entregar(self.root, notificador=notif)
        finally:
            store.append_jsonl = real
        self.assertEqual(len(self.avisos), 1)  # el primero se anotó; el segundo no se notifica

    # P2-1: la comprobación de palabras clave recorre todo el esquema
    def test_palabra_no_soportada_anidada_se_detecta(self):
        anidados = (
            {"allOf": [{"if": {"properties": {"t": {"const": 1}}},
                        "then": {"properties": {"x": {"additionalProperties": False}}}}]},
            {"properties": {"l": {"type": "array", "items": {"properties": {"y": {"oneOf": []}}}}}},
            {"properties": {"z": {"type": "null"}}},
            {"properties": {"f": {"type": "string", "format": "email"}}},
        )
        for sch in anidados:
            self.assertEqual(schema.validate({}, sch), [])  # validate({}) no visita la rama
            with self.assertRaises(schema.SchemaNoSoportado):
                schema.check_supported(sch)
        for name in ("evento", "peticiones", "latido", "presencia", "acuse"):
            schema.check_supported(schema.load_schema(name))

    # P2-2: si no se puede anotar el fin, el mensaje da la orden exacta de reparación
    def test_run_sin_poder_anotar_el_fin_da_la_orden_de_reparacion(self):
        self.write("peticiones.json", "{roto")
        r = self.cli("run", "--job-id", "w1", "--", "true")
        self.assertEqual(r.returncode, 0)
        self.assertIn("pulse job-finish --job-id w1 --rc 0", r.stderr)
        os.unlink(os.path.join(self.root, "peticiones.json"))
        self.assertEqual(self.cli("job-finish", "--job-id", "w1", "--rc", "0").returncode, 0)
        self.assertEqual(len([e for e in self.ledger() if e["tipo"] == "job_finished"]), 1)

    # P2-3: presencia que vence antes de su propia fecha
    def test_presencia_que_vence_antes_de_declararse_no_cuenta(self):
        self.presencia(at_delta=50, hasta_delta=20)
        self.assertEqual(backup.presencia(self.root), (False, "su presencia vence antes de declararse"))
        self.presencia(at_delta=0, hasta_delta=20)
        self.assertTrue(backup.presencia(self.root)[0])

    # P2-4: una pasada concurrente no es un fallo para el planificador
    def test_cli_deliver_con_otra_pasada_en_curso_sale_con_0_sin_avisar(self):
        self.publica(self.peticion("p1"))
        env = self.fake_notify()
        with store.lock(self.root, name=backup.DELIVER_LOCK):
            r = self.cli("deliver", env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("en curso", r.stdout)
        self.assertFalse(os.path.exists(self.marca))
        self.assertFalse(os.path.exists(os.path.join(self.root, "eventos.jsonl")))

    def test_cerrojo_de_escritor_cogido_no_es_pasada_en_curso(self):
        self.publica(self.peticion("p1"))
        real = store.lock
        store.lock = lambda root, timeout=10.0, **kw: real(root, min(timeout, 0.2), **kw)
        try:
            with real(self.root):
                with self.assertRaises(PulseError) as cm:
                    backup.entregar(self.root, notificador=self.notif)
        finally:
            store.lock = real
        self.assertNotIsInstance(cm.exception, backup.PasadaEnCurso)
        self.assertEqual(self.avisos, [])

    # P2-5: Ctrl-C en la terminal llega una sola vez al hijo; un SIGINT directo se reenvía
    def _contador_sigint(self):
        script = os.path.join(self._tmp.name, "cuenta.py")
        with open(script, "w") as fh:
            fh.write("import signal, sys, time\n"
                     "n = [0]\n"
                     "signal.signal(signal.SIGINT, lambda s, f: n.__setitem__(0, n[0] + 1))\n"
                     "open(sys.argv[1], 'w').close()\n"
                     "t = time.time()\n"
                     "while n[0] == 0 and time.time() - t < 20: time.sleep(0.05)\n"
                     "time.sleep(1.0)\n"
                     "open(sys.argv[2], 'w').write(str(n[0]))\n")
        return script, os.path.join(self._tmp.name, "listo"), os.path.join(self._tmp.name, "cuenta")

    def _espera(self, path):
        for _ in range(400):
            if os.path.exists(path):
                return
            time.sleep(0.05)
        self.fail("no apareció " + path)

    def test_ctrl_c_en_la_terminal_llega_una_sola_vez_al_hijo(self):
        import pty
        script, listo, cuenta = self._contador_sigint()
        pid, master = pty.fork()
        if pid == 0:  # hijo: sesión nueva con la pty como terminal de control
            try:
                os.execve(BIN, [BIN, "run", "--job-id", "w1", "--", sys.executable, script, listo, cuenta], self.env)
            finally:
                os._exit(127)
        try:
            self._espera(listo)
            time.sleep(0.3)
            os.write(master, b"\x03")
            self._espera(cuenta)
            time.sleep(0.2)
        finally:
            _, st = os.waitpid(pid, 0)
            os.close(master)
        self.assertEqual(leer(cuenta), "1")

    def test_sigint_directo_al_lanzador_sin_terminal_se_reenvia(self):
        script, listo, cuenta = self._contador_sigint()
        p = subprocess.Popen([BIN, "run", "--job-id", "w1", "--", sys.executable, script, listo, cuenta],
                             env=self.env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        self._espera(listo)
        time.sleep(0.3)
        p.send_signal(signal.SIGINT)
        self.assertEqual(p.wait(timeout=30), 0)
        self.assertEqual(leer(cuenta), "1")

    # P2-6 (y seguridad P2-2): validate con JSON muy anidado no revienta
    def test_validate_json_muy_anidado_no_da_traceback(self):
        f = self.write("anidado.json", "[" * 200000)
        r = self.cli("validate", "peticiones", f)
        self.assertEqual(r.returncode, 1)
        self.assertIn("no es JSON válido", r.stderr)
        self.assertNotIn("Traceback", r.stderr)

    # P2-7: sin notificación del sistema se dice que el único canal es el inbox
    def test_cli_deliver_sin_notificacion_del_sistema_lo_dice(self):
        self.publica(self.peticion("p1"))
        r = self.cli("deliver", env=self.fake_notify(rc=1))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("el único canal es «pulse inbox»", r.stdout)
        self.assertEqual(self.aviso_evs()[0]["canal_so"], "no_disponible")
        r = self.cli("deliver", env=self.fake_notify(rc=0))
        self.assertNotIn("único canal", r.stdout)

    # Seguridad P2-1: el inbox no pasa secuencias de control a la terminal
    def test_inbox_no_pasa_secuencias_de_control_a_la_terminal(self):
        self.publica(self.peticion("p1", que="titulo \x1b[2J\x1b]0;x\x07 fin", por_que_ahora="a\rb"))
        txt = backup.inbox_text(self.root)
        self.assertIn("titulo", txt)
        self.assertNotIn("\x1b", txt)
        self.assertNotIn("\x07", txt)
        self.assertNotIn("\r", txt)
        r = self.cli("inbox")
        self.assertNotIn("\x1b", r.stdout)


class Estaticas(unittest.TestCase):
    def test_el_codigo_no_tiene_red_ni_listener(self):
        # AC-16/AC-27 (parte S1): ningún módulo importa nada de red.
        prohibidos = ("socket", "http", "urllib", "ssl", "requests", "asyncio", "ftplib", "smtplib", "xmlrpc")
        for fname in os.listdir(os.path.join(PROJECT, "pulse")):
            if not fname.endswith(".py"):
                continue
            src = leer(os.path.join(PROJECT, "pulse", fname))
            for line in src.splitlines():
                s = line.strip()
                if s.startswith(("import ", "from ")):
                    mods = s.replace("import ", " ").replace("from ", " ").replace(",", " ").split()
                    for m in mods:
                        self.assertNotIn(m.split(".")[0], prohibidos, "%s importa %s" % (fname, m))

    def test_solo_biblioteca_estandar(self):
        # D2: Python estándar >= 3.9 sin dependencias.
        permitidos = {"argparse", "contextlib", "datetime", "fcntl", "json", "math", "os", "re", "secrets", "shutil",
                      "signal", "stat", "subprocess", "sys", "tempfile", "time"}
        for fname in os.listdir(os.path.join(PROJECT, "pulse")):
            if not fname.endswith(".py"):
                continue
            for line in leer(os.path.join(PROJECT, "pulse", fname)).splitlines():
                if line.startswith("import "):
                    for m in line[7:].split(","):
                        self.assertIn(m.split(" as ")[0].strip().split(".")[0], permitidos, fname)
                elif line.startswith("from ") and not line.startswith("from ."):
                    self.assertIn(line.split()[1].split(".")[0], permitidos, fname)

    def test_no_hay_acciones_prohibidas_en_el_nucleo(self):
        # S1 no fusiona, aprueba ni empuja: ningún módulo menciona esas órdenes.
        for fname in os.listdir(os.path.join(PROJECT, "pulse")):
            if not fname.endswith(".py"):
                continue
            src = leer(os.path.join(PROJECT, "pulse", fname))
            for palabra in ("gh pr", "git push", "--force", "pr merge", "pr ready"):
                self.assertNotIn(palabra, src, fname)


if __name__ == "__main__":
    unittest.main()
