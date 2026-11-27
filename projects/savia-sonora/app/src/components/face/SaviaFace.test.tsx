import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";
import { render } from "@testing-library/react";
import { SaviaFace, type FaceMode } from "./SaviaFace";
import buhita from "@/lib/face/styles/buhita.json";

const MODES: FaceMode[] = ["idle", "listening", "thinking", "speaking", "offline"];

function mouthTransform(container: HTMLElement): string | null {
  const mouth = container.querySelector('[data-face-part="mouth"]');
  return mouth ? mouth.getAttribute("transform") : null;
}

describe("SaviaFace", () => {
  it("pinta cada estado en los dos estilos", () => {
    for (const style of ["buhita", "circulo"] as const) {
      for (const mode of MODES) {
        const { container, unmount } = render(
          <SaviaFace styleId={style} mode={mode} reducedMotion={false} />,
        );
        const root = container.querySelector("[data-face-style]");
        expect(root?.getAttribute("data-face-style")).toBe(style);
        expect(root?.getAttribute("data-face-mode")).toBe(mode);
        unmount();
      }
    }
  });

  it("solo muestra las ondas al escuchar y las burbujas al pensar", () => {
    const { container, rerender } = render(
      <SaviaFace styleId="buhita" mode="listening" reducedMotion={false} />,
    );
    expect(container.querySelector('[data-face-part="listen"]')).not.toBeNull();
    expect(container.querySelector('[data-face-part="think"]')).toBeNull();
    rerender(<SaviaFace styleId="buhita" mode="thinking" reducedMotion={false} />);
    expect(container.querySelector('[data-face-part="listen"]')).toBeNull();
    expect(container.querySelector('[data-face-part="think"]')).not.toBeNull();
    rerender(<SaviaFace styleId="buhita" mode="offline" reducedMotion={false} />);
    expect(container.querySelector('[data-face-part="offline"]')).not.toBeNull();
  });

  it("la boca se mueve con el nivel solo mientras habla", () => {
    const { container, rerender } = render(
      <SaviaFace styleId="circulo" mode="speaking" level={0} reducedMotion={false} />,
    );
    const closed = mouthTransform(container);
    rerender(<SaviaFace styleId="circulo" mode="speaking" level={0.8} reducedMotion={false} />);
    expect(mouthTransform(container)).not.toBe(closed);
    rerender(<SaviaFace styleId="circulo" mode="thinking" level={0.8} reducedMotion={false} />);
    expect(mouthTransform(container)).toBe(closed);
  });

  it("un nivel NaN deja la boca cerrada", () => {
    const { container, rerender } = render(
      <SaviaFace styleId="buhita" mode="speaking" level={0} reducedMotion={false} />,
    );
    const closed = mouthTransform(container);
    rerender(<SaviaFace styleId="buhita" mode="speaking" level={Number.NaN} reducedMotion={false} />);
    expect(mouthTransform(container)).toBe(closed);
  });

  it("los colores salen de los tokens del tema, sin literales", () => {
    const { container } = render(
      <SaviaFace styleId="buhita" mode="speaking" reducedMotion={false} />,
    );
    const painted = container.querySelectorAll("[fill],[stroke]");
    expect(painted.length).toBeGreaterThan(0);
    painted.forEach((el) => {
      for (const attr of ["fill", "stroke"]) {
        const v = el.getAttribute(attr);
        if (v && v !== "none") expect(v).toMatch(/^var\(--[a-z0-9-]+\)$/);
      }
    });
  });

  it("estilo «sin cara» no pinta nada", () => {
    const { container } = render(<SaviaFace styleId="none" mode="speaking" />);
    expect(container.innerHTML).toBe("");
  });
});

describe("movimiento reducido", () => {
  it("sin animación CSS ni cambio de la boca con el nivel", () => {
    const { container, rerender } = render(
      <SaviaFace styleId="buhita" mode="speaking" level={0.1} reducedMotion />,
    );
    const first = mouthTransform(container);
    rerender(<SaviaFace styleId="buhita" mode="speaking" level={0.9} reducedMotion />);
    expect(mouthTransform(container)).toBe(first);
    container.querySelectorAll("*").forEach((el) => {
      const cls = el.getAttribute("class") ?? "";
      expect(cls).not.toMatch(/animate|transition/);
      const style = el.getAttribute("style") ?? "";
      expect(style).not.toMatch(/animation|transition/);
      expect(el.tagName.toLowerCase()).not.toMatch(/^(animate|animatetransform|animatemotion|set)$/);
    });
  });

  it("habla se distingue de reposo con un cambio estático", () => {
    const { container, rerender } = render(
      <SaviaFace styleId="circulo" mode="idle" reducedMotion />,
    );
    const idle = mouthTransform(container);
    rerender(<SaviaFace styleId="circulo" mode="speaking" reducedMotion />);
    expect(mouthTransform(container)).not.toBe(idle);
  });

  it("lee prefers-reduced-motion del sistema si no se indica", () => {
    const original = window.matchMedia;
    window.matchMedia = vi.fn().mockImplementation((q: string) => ({
      matches: q.includes("reduce"),
      media: q,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      addListener: vi.fn(),
      removeListener: vi.fn(),
      onchange: null,
      dispatchEvent: vi.fn(),
    })) as unknown as typeof window.matchMedia;
    try {
      const { container } = render(<SaviaFace styleId="buhita" mode="speaking" />);
      expect(
        container.querySelector("[data-face-style]")?.getAttribute("data-reduced-motion"),
      ).toBe("true");
    } finally {
      window.matchMedia = original;
    }
  });
});

describe("sin red al montar", () => {
  const fetchSpy = vi.fn(() => {
    throw new Error("fetch bloqueado");
  });
  const xhrOpen = vi.fn(() => {
    throw new Error("XHR bloqueado");
  });
  let originalFetch: typeof globalThis.fetch;
  let originalOpen: typeof XMLHttpRequest.prototype.open;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
    originalOpen = XMLHttpRequest.prototype.open;
    globalThis.fetch = fetchSpy as unknown as typeof globalThis.fetch;
    XMLHttpRequest.prototype.open = xhrOpen as unknown as typeof XMLHttpRequest.prototype.open;
  });
  afterEach(() => {
    globalThis.fetch = originalFetch;
    XMLHttpRequest.prototype.open = originalOpen;
    fetchSpy.mockClear();
    xhrOpen.mockClear();
  });

  it("ningún estilo ni estado pide nada a la red", () => {
    for (const style of ["buhita", "circulo", "none"] as const) {
      for (const mode of MODES) {
        const { container, unmount } = render(
          <SaviaFace styleId={style} mode={mode} level={0.5} reducedMotion={false} />,
        );
        expect(container.querySelector("image, use, foreignObject, [href], [xlink\\:href]")).toBeNull();
        expect(container.innerHTML).not.toMatch(/https?:|url\(/);
        unmount();
      }
    }
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(xhrOpen).not.toHaveBeenCalled();
  });
});

describe("estilo con URL externa", () => {
  it("se rechaza y la cara cae al estilo por defecto", () => {
    const bad = JSON.parse(JSON.stringify(buhita)) as Record<string, unknown>;
    bad.id = "maliciosa";
    (bad.shapes as Array<Record<string, unknown>>)[0].fill = "url(https://example.com/p)";
    const { container } = render(
      <SaviaFace styleDef={bad} mode="idle" reducedMotion={false} />,
    );
    expect(container.querySelector("[data-face-style]")?.getAttribute("data-face-style")).toBe(
      "buhita",
    );
    expect(container.innerHTML).not.toMatch(/example\.com/);
  });
});
