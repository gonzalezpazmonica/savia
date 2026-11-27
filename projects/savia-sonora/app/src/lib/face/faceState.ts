/**
 * Estado de la cara de Savia a partir de los eventos de la conversación
 * (SE-538 S1).
 *
 * La cara solo observa: no manda nada al backend y la conversación no
 * depende de ella. `turn-started`, `tool-running`, `turn-finished` y
 * `speech-interrupted` son los eventos de SE-537 D4. Los de escucha, voz y
 * red son los nombres que esta vista espera de SE-537; si el backend los
 * publica con otro nombre, se cambia solo aquí. El nivel de la boca
 * (`speech-level`) es S2 y no se lee en este slice.
 */
import { useReducer } from "react";
import { useBackendEvent } from "@/hooks/useBackendEvent";

export type FaceMode = "idle" | "listening" | "thinking" | "speaking" | "offline";

export interface FaceState {
  mode: FaceMode;
  /** La sesión tiene un turno en marcha (indicador de trabajo de SE-537). */
  working: boolean;
}

export type FaceEvent =
  | { type: "listen-start" }
  | { type: "listen-end" }
  | { type: "turn-started" }
  | { type: "tool-running" }
  | { type: "turn-finished" }
  | { type: "speech-started" }
  | { type: "speech-ended" }
  | { type: "speech-interrupted" }
  | { type: "session-offline" }
  | { type: "session-online" };

export const FACE_EVENTS = {
  listenStart: "listen-start",
  listenEnd: "listen-end",
  turnStarted: "turn-started",
  toolRunning: "tool-running",
  turnFinished: "turn-finished",
  speechStarted: "speech-started",
  speechEnded: "speech-ended",
  speechInterrupted: "speech-interrupted",
  sessionOffline: "session-offline",
  sessionOnline: "session-online",
} as const;

export const INITIAL_FACE_STATE: FaceState = { mode: "idle", working: false };

export function nextFaceState(s: FaceState, e: FaceEvent): FaceState {
  if (s.mode === "offline" && e.type !== "session-online") return s;
  switch (e.type) {
    case "session-offline":
      return { mode: "offline", working: false };
    case "session-online":
      return s.mode === "offline" ? INITIAL_FACE_STATE : s;
    case "listen-start":
      return { ...s, mode: "listening" };
    case "listen-end":
      // Al soltar el atajo, piensa hasta que llega la primera frase.
      return s.mode === "listening" ? { ...s, mode: "thinking" } : s;
    case "turn-started":
    case "tool-running":
      return {
        working: true,
        mode: s.mode === "speaking" || s.mode === "listening" ? s.mode : "thinking",
      };
    case "turn-finished":
      return { working: false, mode: s.mode === "thinking" ? "idle" : s.mode };
    case "speech-started":
      return { ...s, mode: "speaking" };
    case "speech-ended":
    case "speech-interrupted":
      // Callar no es cancelar: si el trabajo sigue, la cara sigue pensando.
      return s.mode === "speaking" ? { ...s, mode: s.working ? "thinking" : "idle" } : s;
  }
}

function reducer(s: FaceState, e: FaceEvent): FaceState {
  return nextFaceState(s, e);
}

export function useFaceState(): FaceState {
  const [state, dispatch] = useReducer(reducer, INITIAL_FACE_STATE);
  useBackendEvent(FACE_EVENTS.listenStart, () => dispatch({ type: "listen-start" }));
  useBackendEvent(FACE_EVENTS.listenEnd, () => dispatch({ type: "listen-end" }));
  useBackendEvent(FACE_EVENTS.turnStarted, () => dispatch({ type: "turn-started" }));
  useBackendEvent(FACE_EVENTS.toolRunning, () => dispatch({ type: "tool-running" }));
  useBackendEvent(FACE_EVENTS.turnFinished, () => dispatch({ type: "turn-finished" }));
  useBackendEvent(FACE_EVENTS.speechStarted, () => dispatch({ type: "speech-started" }));
  useBackendEvent(FACE_EVENTS.speechEnded, () => dispatch({ type: "speech-ended" }));
  useBackendEvent(FACE_EVENTS.speechInterrupted, () => dispatch({ type: "speech-interrupted" }));
  useBackendEvent(FACE_EVENTS.sessionOffline, () => dispatch({ type: "session-offline" }));
  useBackendEvent(FACE_EVENTS.sessionOnline, () => dispatch({ type: "session-online" }));
  return state;
}
