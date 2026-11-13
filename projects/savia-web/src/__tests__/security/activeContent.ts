// Ayudas de test SE-528 S1: detectan HTML activo en un árbol DOM.
// happy-dom no carga imágenes ni ejecuta onerror, así que la prueba mira
// que no EXISTA ningún constructo ejecutable (elemento, atributo o URL).

export const EXEC_SCHEME = /^\s*(javascript|vbscript|data:text\/html)/i

export const PAYLOADS: Record<string, string> = {
  imgOnerror: '<img src=x onerror="window.__pwned=1">',
  script: '<script>window.__pwned=1</script>',
  svgOnload: '<svg onload="window.__pwned=1"></svg>',
  svgScript: '<svg><script>window.__pwned=1</script></svg>',
  iframe: '<iframe src="javascript:window.__pwned=1"></iframe>',
  object: '<object data="javascript:window.__pwned=1"></object>',
  mdLinkJs: '[clic](javascript:window.__pwned=1)',
  mdLinkJsEntity: '[clic](java&#115;cript:window.__pwned=1)',
  mdLinkJsTab: '[clic](java\tscript:window.__pwned=1)',
  mdImgJs: '![x](javascript:window.__pwned=1)',
  mdImgSvgData: '![x](data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoMSk+)',
  mdImgAttrBreak: '![x" onerror="window.__pwned=1](https://example.com/a.png)',
  mdLinkTitleBreak: '[a](https://example.com "t\\" onmouseover=\\"window.__pwned=1")',
  htmlAnchorJs: '<a href="javascript:window.__pwned=1">x</a>',
  htmlOnclick: '<div onclick="window.__pwned=1">x</div>',
  fenceLangBreak: '```js"><img src=x onerror=window.__pwned=1>\ncode\n```',
}

/** Devuelve la lista de motivos por los que el árbol contiene algo ejecutable. */
export function findActiveContent(root: ParentNode): string[] {
  const found: string[] = []
  const all = Array.from(root.querySelectorAll('*'))
  for (const el of all) {
    const tag = el.tagName.toLowerCase()
    if (['script', 'iframe', 'object', 'embed', 'frame', 'base', 'meta', 'form'].includes(tag)) {
      found.push(`<${tag}>`)
    }
    if (tag === 'svg' || el.closest('svg')) found.push(`<${tag}> dentro de svg`)
    for (const attr of Array.from(el.attributes)) {
      const name = attr.name.toLowerCase()
      if (name.startsWith('on')) found.push(`${tag}[${name}]`)
      if (['href', 'src', 'data', 'action', 'formaction', 'xlink:href', 'srcdoc'].includes(name)) {
        const v = attr.value.replace(/[\u0000- ]/g, '')
        if (EXEC_SCHEME.test(v) || /^data:image\/svg/i.test(v)) found.push(`${tag}[${name}]=${attr.value}`)
      }
    }
  }
  return found
}
