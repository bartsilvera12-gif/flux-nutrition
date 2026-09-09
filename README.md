# FLUX Nutrition · Ecommerce editorial

Tienda online multi-marca de suplementos y nutrición, con panel administrativo integrado.

## Estructura

- `FLUX Nutrition.dc.html` — Fuente. Archivo `.dc.html` (Claude Design canvas) con motor de plantillas `sc-if` / `sc-for` y variables `{{ }}`.
- `support.js` — Runtime del motor (interpreta las directivas, hace el data-binding).
- `assets/` — Imágenes de marca, líneas de producto, fotos lifestyle y catálogo completo por producto.
- `uploads/` — Fotos del hero, FAQ, manual de marca en PDF.
- `flux_schema.sql` — Schema PostgreSQL del panel admin (tablas de productos, marcas, rutinas, testimonios, FAQs, ingredientes, content blocks y auditoría).
- `FLUX Admin.dc.html` — Prototipo del admin (legacy, la versión funcional está integrada en el archivo principal).

## Correr localmente

Cualquier servidor estático sirve. Con Node:

```bash
npx serve -p 8765
```

Después ir a `http://localhost:8765` — el runtime `support.js` se encarga de resolver las plantillas.

## Diseño

- **Tipografía**: Montserrat (todo el sitio, respetando el manual de marca).
- **Paleta**: neutros `#1F2937` / `#6B7280` / `#F8FAFC` / `#FFFFFF` + verde marca `#C3D9AB` + pastels por línea (Esencial `#FF83A7`, Mental `#AFC8FF`, Activa `#C9A7FF`, Digestiva `#8FE9F4`, Women `#FFD6E8`, Glow `#B7C9FF`, Hormonal `#E07AAE`).
- Cada sección tiene un tinte suave de la paleta oficial para dar ritmo cromático editorial.

## Secciones de la home

1. Hero — Full-bleed lifestyle photo + editorial copy overlay
2. Trust bar
3. Featured products (Tus esenciales FLUX) — InfoCards con conic-gradient border, rotación automática
4. Shop by Goal — Grid asimétrico con las 6 líneas oficiales
5. Ingredients carousel — Split verde con chips + card stack estilo Apple
6. Bienestar real — Editorial dark 2-col split
7. Marcas — Grid de las marcas argentinas + FLUX propia
8. Manifesto masked heading — Texto con imagen dentro (parallax cursor + wipe reveal)
9. Rutinas ScrollStack — Cards pinadas con scale progresivo
10. Testimonios — 3 columnas scroll infinite en direcciones opuestas
11. Footer dark con newsletter integrado

## Otras páginas

- `/about` (Sobre FLUX) — Historia + pilares + valores + timeline
- `/faq` (FAQs) — Split editorial con acordeón
- `/privacy` — Política de privacidad
- `/admin` — Panel administrativo (gestión de marcas por ahora, resto en desarrollo)
- `/productos` — Catálogo con filtros por marca / categoría / objetivo / precio
- `/producto/:id` — Página de producto individual

## Panel admin

Rutas:
- `/#admin` — Dashboard con Marcas · Productos · Pedidos · Clientes · Contenido
- Marcas: CRUD completo con nombre, ID, país, tagline, color y toggle activo/pausada
- Los cambios se reflejan en vivo en la tienda pública (client-side; para persistencia real conectar backend usando `flux_schema.sql`)

## Marcas iniciales

- Vitamin Way (AR)
- Now Foods (AR)
- Universal Nutrition (AR)
- Natier (AR)
- FLUX Nutrition (PY, línea propia)

---

Desarrollado por [Neura](https://neura.com.py) · 2026
