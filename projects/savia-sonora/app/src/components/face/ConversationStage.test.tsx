import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { ConversationStage } from "./ConversationStage";

function stage(style: "buhita" | "circulo" | "none") {
  return render(
    <ConversationStage faceStyle={style} faceMode="speaking" reducedMotion={false}>
      <p>Hoy hay tres PR abiertas.</p>
      <span role="status">Trabajando: revisando la PR 1670</span>
    </ConversationStage>,
  );
}

describe("«sin cara» no cambia la conversación", () => {
  it("mismo texto y mismo indicador con cara y sin cara", () => {
    for (const style of ["buhita", "circulo"] as const) {
      const withFace = stage(style);
      expect(withFace.container.querySelector("[data-face-style]")).not.toBeNull();
      const conversationWith = withFace.container.querySelector("[data-conversation]")!.innerHTML;
      const statusWith = screen.getByRole("status").textContent;
      withFace.unmount();

      const without = stage("none");
      const conversationWithout = without.container.querySelector("[data-conversation]")!.innerHTML;
      expect(conversationWithout).toBe(conversationWith);
      expect(screen.getByRole("status").textContent).toBe(statusWith);
      expect(without.container.querySelector("[data-face-style]")).toBeNull();
      expect(screen.getByText("Hoy hay tres PR abiertas.")).toBeInTheDocument();
      without.unmount();
    }
  });

  it("la cara no añade texto visible a la vista", () => {
    const withFace = stage("buhita");
    const textWith = withFace.container.textContent;
    withFace.unmount();
    const without = stage("none");
    expect(without.container.textContent).toBe(textWith);
  });
});
