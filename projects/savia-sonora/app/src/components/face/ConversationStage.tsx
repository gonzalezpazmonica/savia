import type { ReactNode } from "react";
import { SaviaFace, type FaceMode, type FaceStyleId } from "./SaviaFace";

export interface ConversationStageProps {
  faceStyle: FaceStyleId;
  faceMode: FaceMode;
  level?: number;
  reducedMotion?: boolean;
  /** Subtítulos e indicador de trabajo (SE-537). No dependen de la cara. */
  children: ReactNode;
}

/**
 * Coloca la cara encima de la conversación. La cara va en su propio hueco y
 * la conversación se pinta igual con cara o sin ella (SE-538 escena 3).
 */
export function ConversationStage({
  faceStyle,
  faceMode,
  level,
  reducedMotion,
  children,
}: ConversationStageProps) {
  return (
    <div className="flex flex-col items-center gap-3">
      {faceStyle !== "none" && (
        <div data-face-region className="w-40 max-w-[60vw]">
          <SaviaFace styleId={faceStyle} mode={faceMode} level={level} reducedMotion={reducedMotion} />
        </div>
      )}
      <div data-conversation className="w-full">
        {children}
      </div>
    </div>
  );
}
