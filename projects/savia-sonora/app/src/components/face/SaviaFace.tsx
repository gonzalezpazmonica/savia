import { useEffect, useState } from "react";
import {
  paintVar,
  resolveFaceStyle,
  type FacePart,
  type FaceShape,
  type FaceStyle,
} from "@/lib/face/faceStyle";
import type { FaceMode } from "@/lib/face/faceState";

export type { FaceMode };
export type FaceStyleId = "buhita" | "circulo" | "none";

const MODE_LABEL: Record<FaceMode, string> = {
  idle: "en reposo",
  listening: "escuchando",
  thinking: "pensando",
  speaking: "hablando",
  offline: "sin conexión",
};

const REDUCED_QUERY = "(prefers-reduced-motion: reduce)";

function systemPrefersReduced(): boolean {
  return typeof window !== "undefined" && typeof window.matchMedia === "function"
    ? window.matchMedia(REDUCED_QUERY).matches
    : false;
}

/** Sigue `prefers-reduced-motion`, salvo que el llamador lo fije. */
function useReducedMotion(forced: boolean | undefined): boolean {
  const [system, setSystem] = useState(systemPrefersReduced);
  useEffect(() => {
    if (forced !== undefined || typeof window.matchMedia !== "function") return;
    const mq = window.matchMedia(REDUCED_QUERY);
    const onChange = () => setSystem(mq.matches);
    mq.addEventListener?.("change", onChange);
    return () => mq.removeEventListener?.("change", onChange);
  }, [forced]);
  return forced ?? system;
}

function clampLevel(level: number | undefined): number {
  if (level === undefined || !Number.isFinite(level)) return 0;
  return Math.min(1, Math.max(0, level));
}

function mouthTransform(style: FaceStyle, level: number): string | undefined {
  const m = style.mouth;
  if (m.kind === "translateY") return `translate(0 ${(level * m.max).toFixed(2)})`;
  const s = (1 + level * (m.max - 1)).toFixed(3);
  return `translate(${m.originX} ${m.originY}) scale(1 ${s}) translate(${-m.originX} ${-m.originY})`;
}

const PART_VISIBLE: Record<FacePart, (mode: FaceMode) => boolean> = {
  base: () => true,
  mouth: () => true,
  listen: (mode) => mode === "listening",
  think: (mode) => mode === "thinking",
  offline: (mode) => mode === "offline",
};

function Shape({ shape }: { shape: FaceShape }) {
  const common = {
    fill: paintVar(shape.fill),
    stroke: paintVar(shape.stroke),
    strokeWidth: shape.strokeWidth,
    opacity: shape.opacity,
    strokeLinecap: shape.strokeLinecap,
  };
  switch (shape.el) {
    case "path":
      return <path {...common} d={shape.d} />;
    case "circle":
      return <circle {...common} cx={shape.cx} cy={shape.cy} r={shape.r} />;
    case "ellipse":
      return <ellipse {...common} cx={shape.cx} cy={shape.cy} rx={shape.rx} ry={shape.ry} />;
    case "rect":
      return (
        <rect {...common} x={shape.x} y={shape.y} width={shape.width} height={shape.height} rx={shape.rx} />
      );
  }
}

export interface SaviaFaceProps {
  /** Estilo incluido o «sin cara». Por defecto, la buhita. */
  styleId?: FaceStyleId;
  /** JSON de estilo propio; se valida y, si no pasa, se usa el de defecto. */
  styleDef?: unknown;
  mode: FaceMode;
  /** Nivel 0..1 de la voz que suena. Solo mueve la boca en «habla». */
  level?: number;
  /** Fuerza el movimiento reducido; si falta, se lee del sistema. */
  reducedMotion?: boolean;
  className?: string;
}

/**
 * Cara 2D de Savia (SE-538 S1). SVG local, sin recursos de red y con
 * colores de los tokens del tema. No pinta texto de la conversación: con
 * «sin cara» devuelve null y el resto de la vista no cambia.
 */
export function SaviaFace({
  styleId = "buhita",
  styleDef,
  mode,
  level,
  reducedMotion,
  className,
}: SaviaFaceProps) {
  const reduced = useReducedMotion(reducedMotion);
  if (styleId === "none" && styleDef === undefined) return null;

  const style = resolveFaceStyle(styleDef ?? styleId);
  const speaking = mode === "speaking";
  // Con movimiento reducido la boca no sigue la voz: queda en una posición
  // fija que distingue «habla» de los demás estados.
  const mouthLevel = speaking ? (reduced ? style.mouth.staticLevel : clampLevel(level)) : 0;
  const animated = !reduced;

  return (
    <svg
      viewBox={style.viewBox}
      role="img"
      aria-label={`Cara de Savia, ${MODE_LABEL[mode]}`}
      data-face-style={style.id}
      data-face-mode={mode}
      data-reduced-motion={reduced ? "true" : "false"}
      className={className}
    >
      <g opacity={mode === "offline" ? 0.55 : undefined}>
        {style.shapes.map((shape, i) => {
          if (shape.part === "offline" || !PART_VISIBLE[shape.part](mode)) return null;
          if (shape.part === "mouth") {
            return (
              <g
                key={i}
                data-face-part="mouth"
                transform={mouthTransform(style, mouthLevel)}
                className={animated ? "transition-transform duration-75" : undefined}
              >
                <Shape shape={shape} />
              </g>
            );
          }
          return (
            <g
              key={i}
              data-face-part={shape.part === "base" ? undefined : shape.part}
              className={animated && shape.part === "think" ? "animate-pulse" : undefined}
            >
              <Shape shape={shape} />
            </g>
          );
        })}
      </g>
      {mode === "offline" &&
        style.shapes.map((shape, i) =>
          shape.part === "offline" ? (
            <g key={`off-${i}`} data-face-part="offline">
              <Shape shape={shape} />
            </g>
          ) : null,
        )}
    </svg>
  );
}
