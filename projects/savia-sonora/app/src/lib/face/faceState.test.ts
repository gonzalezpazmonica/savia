import { describe, it, expect } from "vitest";
import { act, renderHook } from "@testing-library/react";
import { INITIAL_FACE_STATE, nextFaceState, useFaceState, FACE_EVENTS } from "./faceState";

function fire(name: string, detail?: unknown) {
  document.dispatchEvent(new CustomEvent(name, { detail }));
}

describe("nextFaceState", () => {
  it("escucha → piensa → habla → reposo", () => {
    let s = INITIAL_FACE_STATE;
    expect(s.mode).toBe("idle");
    s = nextFaceState(s, { type: "listen-start" });
    expect(s.mode).toBe("listening");
    s = nextFaceState(s, { type: "listen-end" });
    expect(s.mode).toBe("thinking");
    s = nextFaceState(s, { type: "speech-started" });
    expect(s.mode).toBe("speaking");
    s = nextFaceState(s, { type: "speech-ended" });
    s = nextFaceState(s, { type: "turn-finished" });
    expect(s.mode).toBe("idle");
  });

  it("voz callada con el trabajo en marcha: deja de hablar y sigue pensando", () => {
    let s = nextFaceState(INITIAL_FACE_STATE, { type: "turn-started" });
    s = nextFaceState(s, { type: "speech-started" });
    expect(s.mode).toBe("speaking");
    s = nextFaceState(s, { type: "speech-interrupted" });
    expect(s.mode).toBe("thinking");
    expect(s.working).toBe(true);
  });

  it("voz callada sin trabajo en marcha vuelve a reposo", () => {
    let s = nextFaceState(INITIAL_FACE_STATE, { type: "speech-started" });
    s = nextFaceState(s, { type: "speech-interrupted" });
    expect(s.mode).toBe("idle");
  });

  it("sin red gana a todo hasta que vuelve la red", () => {
    let s = nextFaceState(INITIAL_FACE_STATE, { type: "session-offline" });
    expect(s.mode).toBe("offline");
    s = nextFaceState(s, { type: "speech-started" });
    expect(s.mode).toBe("offline");
    s = nextFaceState(s, { type: "session-online" });
    expect(s.mode).toBe("idle");
  });
});

describe("useFaceState", () => {
  it("sigue los eventos simulados del backend", () => {
    const { result } = renderHook(() => useFaceState());
    act(() => fire(FACE_EVENTS.turnStarted));
    expect(result.current.mode).toBe("thinking");
    act(() => fire(FACE_EVENTS.speechStarted));
    expect(result.current.mode).toBe("speaking");
    act(() => fire(FACE_EVENTS.speechInterrupted));
    expect(result.current.mode).toBe("thinking");
    act(() => fire(FACE_EVENTS.turnFinished));
    expect(result.current.mode).toBe("idle");
  });
});
