"""TTS Synthesizer v2.4 — Kokoro native + edge-tts fallback."""

import os
import queue
import shutil
import subprocess
import tempfile
import threading
import wave
from pathlib import Path

import numpy as np
import sounddevice as sd

VENV_BIN = str(Path.home() / ".savia/whisper-env/bin")
KOKORO_RATE = 24000


class TTSSynthesizer:
    """Queue-based TTS with Kokoro (local) + pre-cache for instant first audio."""

    def __init__(self, engine="kokoro", voice="ef_dora",
                 lead_in_silence=1.0):
        self.engine = engine
        self.voice = voice
        self.lead_in = lead_in_silence
        self._queue = queue.Queue()
        self._cancel = threading.Event()
        self._playing = threading.Event()
        self._kokoro = None
        self._cache = None
        self._worker = threading.Thread(
            target=self._playback_loop, daemon=True
        )
        self._worker.start()

    def load_kokoro(self):
        if self._kokoro is not None:
            return self._kokoro
        from pathlib import Path
        from tts_cache import TTSCache
        self._cache = TTSCache()
        # Try loading pre-generated audio from disk first (instant)
        cache_dir = Path(__file__).parent / "cache" / "es"
        if self._cache.warm_from_files(str(cache_dir)):
            print("[init] Cache cargada de disco (sin Kokoro).")
        # Always load Kokoro for non-cached phrases
        print("[init] Cargando Kokoro TTS...")
        from kokoro import KPipeline
        self._kokoro = KPipeline(
            lang_code="e", repo_id="hexgrad/Kokoro-82M"
        )
        print("[init] Kokoro listo.")
        # Generate any missing cache entries
        if not cache_dir.exists() or len(list(cache_dir.glob("*.wav"))) < 10:
            self._cache.warm(self._kokoro, self.voice)
        return self._kokoro

    def _playback_loop(self):
        while True:
            try:
                item = self._queue.get(timeout=1)
            except queue.Empty:
                continue
            if item is None:
                break
            if self._cancel.is_set():
                self._queue.task_done()
                continue
            data, rate = item
            self._playing.set()
            sd.play(data, rate)
            sd.wait()
            self._playing.clear()
            self._queue.task_done()

    def speak(self, text):
        """Blocking speak — for greetings and feedback."""
        if not text:
            return
        audio = self._synthesize(text, add_lead_in=True)
        if audio:
            sd.play(*audio)
            sd.wait()

    def queue_sentence(self, text, first=False):
        if not text:
            return
        audio = self._synthesize(text, add_lead_in=first)
        if audio and not self._cancel.is_set():
            self._queue.put(audio)

    def wait_done(self):
        self._queue.join()

    def cancel(self):
        self._cancel.set()
        sd.stop()
        while not self._queue.empty():
            try:
                self._queue.get_nowait()
                self._queue.task_done()
            except queue.Empty:
                break
        self._cancel.clear()

    @property
    def is_playing(self):
        return self._playing.is_set() or not self._queue.empty()

    def _synthesize(self, text, add_lead_in=False):
        """Route to Kokoro or edge-tts based on engine config."""
        if self.engine == "kokoro":
            return self._synth_kokoro(text, add_lead_in)
        return self._synth_edge(text, add_lead_in)

    def _synth_kokoro(self, text, add_lead_in=False):
        try:
            # Check cache first — instant playback for common phrases
            if self._cache:
                cached = self._cache.get(text)
                if cached:
                    data, rate = cached
                    if add_lead_in and self.lead_in > 0:
                        silence = np.zeros(
                            int(rate * self.lead_in), dtype=np.int16
                        )
                        data = np.concatenate([silence, data])
                    return (data, rate)
            pipe = self.load_kokoro()
            segments = list(pipe(text, voice=self.voice))
            if not segments:
                return None
            audio = np.concatenate([s[2] for s in segments])
            # Kokoro outputs float32 at 24kHz — convert to int16
            data = (audio * 32767).astype(np.int16)
            if add_lead_in and self.lead_in > 0:
                silence = np.zeros(
                    int(KOKORO_RATE * self.lead_in), dtype=np.int16
                )
                data = np.concatenate([silence, data])
            return (data, KOKORO_RATE)
        except Exception as e:
            print(f"[tts] Kokoro error: {e}, fallback edge-tts")
            return self._synth_edge(text, add_lead_in)

    def _synth_edge(self, text, add_lead_in=False):
        edge_voice = "es-ES-ElviraNeural"
        # Private 0700 dir: no predictable shared-/tmp name to pre-plant
        tmp_dir = tempfile.mkdtemp(prefix="savia-tts-")
        tmp_mp3 = os.path.join(tmp_dir, "edge.mp3")
        tmp_wav = os.path.join(tmp_dir, "edge.wav")
        try:
            r = subprocess.run(
                # "--text=" binds the value: text starting with "-" is not an option
                [f"{VENV_BIN}/edge-tts", "--voice", edge_voice,
                 f"--text={text}", "--write-media", tmp_mp3],
                capture_output=True, timeout=15
            )
            if r.returncode != 0:
                return None
            r = subprocess.run(
                ["ffmpeg", "-y", "-loglevel", "error",
                 "-i", tmp_mp3, "-ar", "16000",
                 "-ac", "1", "-f", "wav", tmp_wav],
                capture_output=True, timeout=10
            )
            if r.returncode != 0:
                return None
            with wave.open(tmp_wav, "rb") as wf:
                data = np.frombuffer(
                    wf.readframes(wf.getnframes()), dtype=np.int16
                )
                rate = wf.getframerate()
            if add_lead_in and self.lead_in > 0:
                silence = np.zeros(
                    int(rate * self.lead_in), dtype=np.int16
                )
                data = np.concatenate([silence, data])
            return (data, rate)
        except Exception as e:
            print(f"[tts] edge-tts error: {e}")
            return None
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)
