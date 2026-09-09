-- =====================================================================
-- SCHEMA: flux
-- FLUX NUTRITION by FIVA — Panel Admin
-- PostgreSQL 14+
-- Última actualización: 2026-09-09
-- =====================================================================
-- Contenido:
--   • Marcas (multi-brand)
--   • Categorías y objetivos
--   • Productos + imágenes + destacados
--   • Ingredientes (sección "Fórmulas transparentes")
--   • Rutinas (sección "Tu rutina, a tu manera")
--   • Testimonios
--   • FAQs
--   • Content blocks (bloques editables de la home)
--   • Auditoría básica
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS flux;
SET search_path TO flux, public;

-- ---------------------------------------------------------------------
-- Extensiones
-- ---------------------------------------------------------------------
-- Nativo en PostgreSQL 13+ (gen_random_uuid). Si tu versión es 12 o menor descomentá:
-- CREATE EXTENSION IF NOT EXISTS "pgcrypto";
-- Usamos TEXT + citext_email helper (case-insensitive email via lower(email))

-- ---------------------------------------------------------------------
-- Trigger reutilizable para updated_at
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION flux.set_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- 1. USUARIOS ADMIN
-- =====================================================================
CREATE TABLE flux.admin_users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT UNIQUE NOT NULL,
  full_name     TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL DEFAULT 'editor' CHECK (role IN ('owner','admin','editor','viewer')),
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TRIGGER trg_admin_users_updated BEFORE UPDATE ON flux.admin_users
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- =====================================================================
-- 2. MARCAS (multi-brand)
-- =====================================================================
CREATE TABLE flux.brands (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          TEXT UNIQUE NOT NULL,       -- 'vitaminway', 'flux', 'nowfoods'
  name          TEXT NOT NULL,                -- 'Vitamin Way'
  country       TEXT,                         -- 'Argentina'
  tagline       TEXT,
  color         TEXT,                         -- '#C3D9AB' hex
  logo_url      TEXT,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_brands_active_order ON flux.brands (active, sort_order);
CREATE TRIGGER trg_brands_updated BEFORE UPDATE ON flux.brands
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- =====================================================================
-- 3. CATEGORÍAS / LÍNEAS
-- =====================================================================
CREATE TABLE flux.categories (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          TEXT UNIQUE NOT NULL,       -- 'vitaminas', 'colagenos', 'nutricosmetica'
  name          TEXT NOT NULL,                -- 'Vitaminas y minerales'
  color         TEXT,                         -- '#AFC8FF'
  tint_gradient TEXT,                         -- CSS linear-gradient(...)
  description   TEXT,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_categories_active_order ON flux.categories (active, sort_order);
CREATE TRIGGER trg_categories_updated BEFORE UPDATE ON flux.categories
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- =====================================================================
-- 4. OBJETIVOS (energía, foco, equilibrio, digestión, belleza, femenina, rendimiento, bienestar)
-- =====================================================================
CREATE TABLE flux.goals (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        TEXT UNIQUE NOT NULL,   -- 'energia', 'foco'
  name        TEXT NOT NULL,            -- 'Energía'
  color       TEXT,                     -- '#FF83A7'
  description TEXT,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_goals_active_order ON flux.goals (active, sort_order);
CREATE TRIGGER trg_goals_updated BEFORE UPDATE ON flux.goals
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- =====================================================================
-- 5. PRODUCTOS
-- =====================================================================
CREATE TABLE flux.products (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug              TEXT UNIQUE NOT NULL,       -- 'multivitaminico-diario'
  sku               TEXT UNIQUE,                  -- código interno para stock
  name              TEXT NOT NULL,                -- 'Multivitamínico Diario'
  brand_id          UUID NOT NULL REFERENCES flux.brands(id) ON DELETE RESTRICT,
  category_id       UUID NOT NULL REFERENCES flux.categories(id) ON DELETE RESTRICT,

  short_description TEXT,                         -- 1 línea, para cards
  description       TEXT,                         -- PDP descripción completa
  benefits          TEXT,
  ingredients       TEXT,
  how_to_use        TEXT,
  presentation      TEXT,                         -- '60 cápsulas · 30 días'

  price             INTEGER NOT NULL CHECK (price >= 0),  -- Gs enteros
  promo_price       INTEGER CHECK (promo_price IS NULL OR promo_price >= 0),
  currency          CHAR(3) NOT NULL DEFAULT 'PYG',

  stock             INTEGER NOT NULL DEFAULT 0,
  stock_min         INTEGER NOT NULL DEFAULT 5,   -- umbral alerta
  weight_grams      INTEGER,

  badge             TEXT,                         -- 'Más vendido', 'Nuevo', 'Promo'
  featured          BOOLEAN NOT NULL DEFAULT FALSE, -- ⭐ aparece en "Tus esenciales FLUX"
  featured_order    INTEGER,                      -- orden dentro de destacados
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order        INTEGER NOT NULL DEFAULT 0,

  meta_title        TEXT,                         -- SEO
  meta_description  TEXT,

  created_by        UUID REFERENCES flux.admin_users(id),
  updated_by        UUID REFERENCES flux.admin_users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_products_brand   ON flux.products (brand_id);
CREATE INDEX idx_products_cat     ON flux.products (category_id);
CREATE INDEX idx_products_active  ON flux.products (active, sort_order);
CREATE INDEX idx_products_featured ON flux.products (featured, featured_order)
  WHERE featured = TRUE;
CREATE INDEX idx_products_stock_low ON flux.products (stock)
  WHERE stock <= stock_min AND active = TRUE;
CREATE TRIGGER trg_products_updated BEFORE UPDATE ON flux.products
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- ---------- Imágenes de producto (múltiples por producto) ----------
CREATE TABLE flux.product_images (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES flux.products(id) ON DELETE CASCADE,
  url        TEXT NOT NULL,
  alt_text   TEXT,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_prodimg_product ON flux.product_images (product_id, sort_order);
-- solo una primary por producto
CREATE UNIQUE INDEX uq_prodimg_primary ON flux.product_images (product_id)
  WHERE is_primary = TRUE;

-- ---------- Junction: productos ↔ objetivos (N:N) ----------
CREATE TABLE flux.product_goals (
  product_id UUID NOT NULL REFERENCES flux.products(id) ON DELETE CASCADE,
  goal_id    UUID NOT NULL REFERENCES flux.goals(id)    ON DELETE CASCADE,
  PRIMARY KEY (product_id, goal_id)
);

-- =====================================================================
-- 6. INGREDIENTES  ("Fórmulas transparentes. Activos con nombre y apellido")
--    Sección de la home. Se muestran en el carrusel/marquee editorial.
-- =====================================================================
CREATE TABLE flux.ingredients (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        TEXT UNIQUE NOT NULL,       -- 'complejo-b'
  name        TEXT NOT NULL,                -- 'Vitaminas del complejo B'
  kind        TEXT,                         -- 'Complejo B' / 'Aminoácido' / 'Nootrópico'
  description TEXT NOT NULL,                -- 'Metabolismo energético y sistema nervioso.'
  color       TEXT,                         -- swatch pastel '#FF83A7'
  image_url   TEXT,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_ingredients_active_order ON flux.ingredients (active, sort_order);
CREATE TRIGGER trg_ingredients_updated BEFORE UPDATE ON flux.ingredients
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- =====================================================================
-- 7. RUTINAS ("Tu rutina, a tu manera")
--    Cada rutina agrupa varios productos y aparece como ScrollStack card.
-- =====================================================================
CREATE TABLE flux.routines (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        TEXT UNIQUE NOT NULL,       -- 'rutina-energia'
  name        TEXT NOT NULL,                -- 'Rutina Energía'
  time_label  TEXT NOT NULL,                -- 'Mañana' / 'Durante el día' / 'Noche'
  description TEXT,                         -- 'Para arrancar el día...'
  image_url   TEXT,                         -- foto lifestyle
  total_price INTEGER NOT NULL CHECK (total_price >= 0), -- precio combo
  savings     INTEGER NOT NULL DEFAULT 0,    -- Gs que ahorra vs suelto
  sort_order  INTEGER NOT NULL DEFAULT 0,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_routines_active_order ON flux.routines (active, sort_order);
CREATE TRIGGER trg_routines_updated BEFORE UPDATE ON flux.routines
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- ---------- Productos que integran cada rutina ----------
CREATE TABLE flux.routine_items (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id UUID NOT NULL REFERENCES flux.routines(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES flux.products(id) ON DELETE RESTRICT,
  quantity   INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  sort_order INTEGER NOT NULL DEFAULT 0,
  UNIQUE (routine_id, product_id)
);
CREATE INDEX idx_routine_items_routine ON flux.routine_items (routine_id, sort_order);

-- =====================================================================
-- 8. TESTIMONIOS
-- =====================================================================
CREATE TABLE flux.testimonials (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote        TEXT NOT NULL,                     -- la cita
  author_name  TEXT NOT NULL,                     -- 'Camila R.'
  author_meta  TEXT,                              -- 'Essential · 4 meses de uso'
  product_id   UUID REFERENCES flux.products(id) ON DELETE SET NULL, -- opcional
  avatar_url   TEXT,                              -- foto opcional
  rating       SMALLINT CHECK (rating BETWEEN 1 AND 5),
  approved     BOOLEAN NOT NULL DEFAULT FALSE,    -- moderación
  featured     BOOLEAN NOT NULL DEFAULT FALSE,    -- destacado
  sort_order   INTEGER NOT NULL DEFAULT 0,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_testimonials_approved ON flux.testimonials (approved, sort_order)
  WHERE approved = TRUE;
CREATE INDEX idx_testimonials_featured ON flux.testimonials (featured)
  WHERE featured = TRUE;
CREATE TRIGGER trg_testimonials_updated BEFORE UPDATE ON flux.testimonials
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- =====================================================================
-- 9. FAQs
-- =====================================================================
CREATE TABLE flux.faq_categories (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug       TEXT UNIQUE NOT NULL,
  name       TEXT NOT NULL,                     -- 'Envíos', 'Productos', 'Pagos'
  sort_order INTEGER NOT NULL DEFAULT 0,
  active     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE flux.faqs (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id  UUID REFERENCES flux.faq_categories(id) ON DELETE SET NULL,
  question     TEXT NOT NULL,
  answer       TEXT NOT NULL,
  sort_order   INTEGER NOT NULL DEFAULT 0,
  active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_faqs_active_order ON flux.faqs (active, sort_order);
CREATE TRIGGER trg_faqs_updated BEFORE UPDATE ON flux.faqs
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- =====================================================================
-- 10. CONTENT BLOCKS (secciones editables de la home)
--     Cada key identifica una sección — el admin edita título/subtítulo/CTA/imagen
--     sin tocar el layout de la web.
-- =====================================================================
CREATE TABLE flux.content_blocks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  block_key     TEXT UNIQUE NOT NULL,      -- 'home.hero', 'home.ingredientes', 'home.rutinas', 'home.testimonios'
  eyebrow       TEXT,                       -- 'Ingredientes'
  title         TEXT,                       -- 'Fórmulas transparentes. Activos con nombre y apellido.'
  subtitle      TEXT,                       -- párrafo secundario
  cta_label     TEXT,
  cta_url       TEXT,
  image_url     TEXT,
  video_url     TEXT,
  extra_json    JSONB DEFAULT '{}'::jsonb,  -- config libre (colores, layout, etc)
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  updated_by    UUID REFERENCES flux.admin_users(id),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TRIGGER trg_content_blocks_updated BEFORE UPDATE ON flux.content_blocks
FOR EACH ROW EXECUTE FUNCTION flux.set_updated_at();

-- =====================================================================
-- 11. AUDITORÍA
-- =====================================================================
CREATE TABLE flux.audit_log (
  id           BIGSERIAL PRIMARY KEY,
  actor_id     UUID REFERENCES flux.admin_users(id),
  action       TEXT NOT NULL,             -- 'create' | 'update' | 'delete' | 'publish'
  entity       TEXT NOT NULL,             -- 'product' | 'brand' | 'testimonial' ...
  entity_id    UUID,
  diff         JSONB,                     -- {before:{}, after:{}}
  ip           INET,
  user_agent   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_entity ON flux.audit_log (entity, entity_id, created_at DESC);
CREATE INDEX idx_audit_actor  ON flux.audit_log (actor_id, created_at DESC);

-- =====================================================================
-- 12. SEED MÍNIMO — datos iniciales para arrancar
-- =====================================================================

-- Marcas
INSERT INTO flux.brands (slug, name, country, tagline, color, active, sort_order) VALUES
  ('vitaminway', 'Vitamin Way',        'Argentina', 'Suplementos con respaldo científico.',    '#C3D9AB', TRUE, 1),
  ('nowfoods',   'Now Foods',          'Argentina', 'Referente global en nutrición natural.',   '#AFC8FF', TRUE, 2),
  ('universal',  'Universal Nutrition','Argentina', 'Deporte, fuerza y rendimiento.',           '#FF83A7', TRUE, 3),
  ('natier',     'Natier',             'Argentina', 'Fórmulas botánicas y adaptógenos.',        '#8FE9F4', TRUE, 4),
  ('flux',       'FLUX Nutrition',     'Paraguay',  'Nuestra línea propia, formulada en PY.',   '#C9A7FF', TRUE, 5);

-- Objetivos
INSERT INTO flux.goals (slug, name, color, sort_order) VALUES
  ('energia',     'Energía',         '#FF83A7', 1),
  ('foco',        'Foco',            '#AFC8FF', 2),
  ('equilibrio',  'Equilibrio',      '#C9A7FF', 3),
  ('digestion',   'Digestión',       '#8FE9F4', 4),
  ('belleza',     'Belleza',         '#B7C9FF', 5),
  ('femenina',    'Salud femenina',  '#E07AAE', 6),
  ('rendimiento', 'Rendimiento',     '#C9A7FF', 7),
  ('bienestar',   'Bienestar',       '#C3D9AB', 8);

-- Bloques editables iniciales
INSERT INTO flux.content_blocks (block_key, eyebrow, title, subtitle) VALUES
  ('home.hero',
   'FLUX Nutrition · Fórmulas diarias',
   'Más vida en tu día.',
   'Ciencia y nutrición para acompañar tu bienestar todos los días.'),
  ('home.ingredientes',
   'Ingredientes',
   'Fórmulas transparentes. Activos con nombre y apellido.',
   'Elegimos cada ingrediente por una razón concreta. Dosis útiles, formas biodisponibles, respaldo científico.'),
  ('home.rutinas',
   'Rutinas',
   'Tu rutina, a tu manera.',
   'Tres momentos, tres combinaciones pensadas para acompañar el día. Ahorrás comprándolas juntas.'),
  ('home.testimonios',
   'Testimonios',
   'Lo que dicen quienes lo prueban.',
   'Historias reales de quienes ya integraron FLUX a su rutina.'),
  ('home.faq',
   'Preguntas frecuentes',
   '¿Buscás respuestas?',
   'Todo lo que necesitás saber sobre FLUX Nutrition: envíos, uso, formulaciones, pagos y más.');

-- =====================================================================
-- 13. VISTAS ÚTILES PARA EL FRONT / API
-- =====================================================================

-- Productos destacados listos para "Tus esenciales FLUX"
CREATE OR REPLACE VIEW flux.v_featured_products AS
SELECT
  p.id, p.slug, p.name, p.short_description, p.price, p.promo_price,
  p.badge, p.stock, p.featured_order,
  b.name AS brand_name, b.color AS brand_color, b.slug AS brand_slug,
  c.name AS category_name, c.color AS category_color,
  (SELECT url FROM flux.product_images pi WHERE pi.product_id = p.id AND pi.is_primary LIMIT 1) AS primary_image
FROM flux.products p
JOIN flux.brands b     ON b.id = p.brand_id
JOIN flux.categories c ON c.id = p.category_id
WHERE p.active = TRUE
  AND p.featured = TRUE
  AND b.active = TRUE
ORDER BY p.featured_order NULLS LAST, p.sort_order, p.name;

-- Rutinas con items
CREATE OR REPLACE VIEW flux.v_routines AS
SELECT
  r.id, r.slug, r.name, r.time_label, r.description, r.image_url,
  r.total_price, r.savings, r.sort_order,
  COALESCE(json_agg(
    json_build_object(
      'product_id', p.id, 'name', p.name, 'price', p.price,
      'promo_price', p.promo_price, 'quantity', ri.quantity, 'image',
      (SELECT url FROM flux.product_images pi WHERE pi.product_id = p.id AND pi.is_primary LIMIT 1)
    ) ORDER BY ri.sort_order
  ) FILTER (WHERE p.id IS NOT NULL), '[]'::json) AS items
FROM flux.routines r
LEFT JOIN flux.routine_items ri ON ri.routine_id = r.id
LEFT JOIN flux.products p       ON p.id = ri.product_id AND p.active = TRUE
WHERE r.active = TRUE
GROUP BY r.id
ORDER BY r.sort_order;

-- FAQs agrupadas por categoría
CREATE OR REPLACE VIEW flux.v_faqs AS
SELECT
  fc.name AS category, fc.sort_order AS cat_order,
  f.id, f.question, f.answer, f.sort_order
FROM flux.faqs f
LEFT JOIN flux.faq_categories fc ON fc.id = f.category_id
WHERE f.active = TRUE
ORDER BY fc.sort_order NULLS LAST, f.sort_order;

-- Testimonios aprobados
CREATE OR REPLACE VIEW flux.v_testimonials AS
SELECT
  t.id, t.quote, t.author_name, t.author_meta, t.avatar_url, t.rating, t.featured,
  p.name AS product_name, p.slug AS product_slug
FROM flux.testimonials t
LEFT JOIN flux.products p ON p.id = t.product_id
WHERE t.approved = TRUE
ORDER BY t.featured DESC, t.sort_order, t.approved_at DESC NULLS LAST;

-- Ingredientes activos
CREATE OR REPLACE VIEW flux.v_ingredients AS
SELECT id, slug, name, kind, description, color, image_url, sort_order
FROM flux.ingredients
WHERE active = TRUE
ORDER BY sort_order, name;

-- =====================================================================
-- FIN
-- =====================================================================
