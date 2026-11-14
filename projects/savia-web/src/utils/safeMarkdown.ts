// SE-528 S1: único punto por el que el markdown de origen externo
// (respuestas del asistente, ficheros) se convierte en HTML para v-html.
// Estrategia: renderizador que ESCAPA el HTML crudo y filtra los esquemas
// de URL. No hay HTML crudo en la salida: solo etiquetas que emite este fichero.
import { Marked, type Tokens } from 'marked'

export interface SafeMarkdownOptions {
  /** Saltos de línea como <br> (chat). */
  breaks?: boolean
  /**
   * Resaltado de código. Devuelve HTML YA escapado (p. ej. hljs.highlight().value)
   * o null para usar texto plano. Si se pasa, el bloque lleva cabecera con botón Copy
   * (sin handlers en línea: el componente delega el clic sobre `.code-copy-btn`).
   */
  highlight?: (code: string, lang: string) => string | null
}

const ESC: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }

export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, c => ESC[c])
}

// Como escapeHtml, pero respeta las entidades ya escritas (`&amp;`, `&#39;`) igual que
// el renderer `text` de marked: el texto se ve idéntico y no queda ningún `<` crudo.
const TEXT_ESC = /[<>"']|&(?!(#\d{1,7}|#[Xx][a-fA-F0-9]{1,6}|\w+);)/g
function escapeText(s: string): string {
  return s.replace(TEXT_ESC, c => ESC[c])
}

const SCHEME = /^[a-zA-Z][a-zA-Z0-9+.-]*:/
const SAFE_IMG_DATA = /^data:image\/(png|jpeg|gif|webp);base64,[a-zA-Z0-9+/=]+$/i

/** Devuelve la URL si es segura; si no, null. Quita controles y espacios que los navegadores ignoran. */
export function safeUrl(raw: string, kind: 'link' | 'image'): string | null {
  const url = (raw ?? '').replace(/[\u0000- \u007f-\u009f]/g, '')
  if (!url) return null
  if (SCHEME.test(url)) {
    if (/^https?:/i.test(url)) return url
    if (kind === 'link' && /^mailto:/i.test(url)) return url
    if (kind === 'image' && SAFE_IMG_DATA.test(url)) return url
    return null
  }
  return url // relativa; el navegador no la interpreta como esquema
}

function build(opts: SafeMarkdownOptions): Marked {
  const m = new Marked({ gfm: true, breaks: opts.breaks ?? false })
  m.use({
    renderer: {
      // HTML crudo (bloque o en línea): se muestra como texto.
      html({ text }: Tokens.HTML | Tokens.Tag) {
        return escapeHtml(text)
      },
      // Texto hoja: SIEMPRE escapado. Tras un tag en línea <pre>/<code>/<kbd>/<script>
      // el lexer de marked marca los tokens `text` siguientes como `escaped: true` y el
      // renderer por defecto los emite crudos (`x <pre> <img/src=x onerror=…>`). Aquí
      // se ignora `escaped`: el único HTML de la salida lo emite este fichero.
      text(this: { parser: { parseInline: (t: Tokens.Generic[]) => string } }, token: Tokens.Text | Tokens.Escape) {
        if ('tokens' in token && token.tokens) return this.parser.parseInline(token.tokens)
        return escapeText(token.text)
      },
      link(this: { parser: { parseInline: (t: Tokens.Generic[]) => string } }, { href, title, tokens }: Tokens.Link) {
        const inner = this.parser.parseInline(tokens)
        const url = safeUrl(href, 'link')
        if (url === null) return inner
        const t = title ? ` title="${escapeHtml(title)}"` : ''
        const ext = /^https?:/i.test(url) ? ' target="_blank" rel="noopener noreferrer"' : ''
        return `<a href="${escapeHtml(url)}"${t}${ext}>${inner}</a>`
      },
      image({ href, title, text }: Tokens.Image) {
        const url = safeUrl(href, 'image')
        if (url === null) return escapeHtml(text)
        const t = title ? ` title="${escapeHtml(title)}"` : ''
        return `<img src="${escapeHtml(url)}" alt="${escapeHtml(text)}"${t} loading="lazy">`
      },
      ...(opts.highlight
        ? {
            code({ text, lang }: Tokens.Code) {
              const l = (lang ?? '').trim().split(/\s+/)[0]
              const hl = l ? opts.highlight!(text, l) : null
              const body = hl ?? escapeHtml(text)
              const cls = /^[A-Za-z0-9_+-]+$/.test(l) && hl !== null ? l : 'plaintext'
              const n = text.split('\n').length
              const nums = n > 5
                ? `<span class="code-lines">${Array.from({ length: n }, (_, i) => i + 1).join('\n')}</span>`
                : ''
              return `<div class="code-block-wrap"><div class="code-block-header"><span class="code-lang">${escapeHtml(l)}</span><button type="button" class="code-copy-btn">Copy</button></div><pre><code class="hljs language-${cls}">${nums}${body}</code></pre></div>`
            },
          }
        : {}),
    },
  })
  return m
}

type Highlight = NonNullable<SafeMarkdownOptions['highlight']>
const NO_HIGHLIGHT = new Map<string, Marked>()
// Una instancia por función `highlight` (identidad, no solo presencia): dos llamadores
// con resaltadores distintos nunca comparten renderer. WeakMap: no retiene funciones.
const BY_HIGHLIGHT = new WeakMap<Highlight, Map<string, Marked>>()

/** Markdown → HTML seguro para v-html. Único punto de saneado de la web. */
export function renderSafeMarkdown(text: string, opts: SafeMarkdownOptions = {}): string {
  let bucket = NO_HIGHLIGHT
  if (opts.highlight) {
    bucket = BY_HIGHLIGHT.get(opts.highlight) ?? new Map<string, Marked>()
    BY_HIGHLIGHT.set(opts.highlight, bucket)
  }
  const key = opts.breaks ? 'b' : ''
  let m = bucket.get(key)
  if (!m) {
    m = build(opts)
    bucket.set(key, m)
  }
  return m.parse(text ?? '', { async: false }) as string
}
