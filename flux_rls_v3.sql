-- =====================================================================
-- FLUX · RLS pack v3 — plantilla Neura definitiva
-- =====================================================================
-- Deny-by-default (RLS + GRANT explícitos)
-- auth.uid() como identidad (no email)
-- private schema para funciones de autorización
-- SECURITY DEFINER + search_path = '' + nombres calificados
-- Policies separadas por operación
-- Hijos públicos gateados por el estado del padre
-- Storage idempotente
-- Correlo en el SQL Editor de Supabase. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Schema privado (NO expuesto a la Data API)
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT  USAGE ON SCHEMA private TO authenticated;   -- indispensable para que RLS pueda llamar la función

-- ---------------------------------------------------------------------
-- 1. Migración de admin_users: agregar user_id → auth.users(id)
-- ---------------------------------------------------------------------
ALTER TABLE flux.admin_users
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_admin_users_user_id
  ON flux.admin_users (user_id) WHERE user_id IS NOT NULL;

-- Vincular filas existentes (por email) al auth.users correspondiente
UPDATE flux.admin_users au
   SET user_id = u.id
  FROM auth.users u
 WHERE au.user_id IS NULL
   AND lower(au.email) = lower(u.email);

-- Password_hash ya no lo usamos (Supabase Auth se encarga)
ALTER TABLE flux.admin_users ALTER COLUMN password_hash DROP NOT NULL;

-- ---------------------------------------------------------------------
-- 2. private.is_admin() — SECURITY DEFINER, search_path vacío
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM flux.admin_users AS au
    WHERE au.user_id = (SELECT auth.uid())
      AND au.active IS TRUE
  );
$$;

ALTER FUNCTION private.is_admin() OWNER TO postgres;

REVOKE ALL   ON FUNCTION private.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated;

-- Elimina el wrapper viejo si existía
DROP FUNCTION IF EXISTS flux.is_admin();

-- ---------------------------------------------------------------------
-- 3. RLS ON en todas las tablas expuestas
-- ---------------------------------------------------------------------
ALTER TABLE flux.admin_users    ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.brands         ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.categories     ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.goals          ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.products       ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.product_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.product_goals  ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.ingredients    ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.routines       ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.routine_items  ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.testimonials   ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.faq_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.faqs           ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.content_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE flux.audit_log      ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- 4. GRANT/REVOKE explícitos (deny-by-default a nivel de permisos PG)
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA flux FROM anon, authenticated;

-- Tablas públicas: SELECT anon+authenticated; DML solo authenticated (RLS filtra al admin)
GRANT SELECT ON
  flux.brands, flux.categories, flux.goals, flux.products,
  flux.product_images, flux.product_goals, flux.ingredients,
  flux.routines, flux.routine_items, flux.testimonials,
  flux.faq_categories, flux.faqs, flux.content_blocks
TO anon, authenticated;

GRANT INSERT, UPDATE, DELETE ON
  flux.brands, flux.categories, flux.goals, flux.products,
  flux.product_images, flux.product_goals, flux.ingredients,
  flux.routines, flux.routine_items, flux.testimonials,
  flux.faq_categories, flux.faqs, flux.content_blocks
TO authenticated;

-- Tablas 100% administrativas: nada al anon
GRANT SELECT, INSERT, UPDATE, DELETE ON flux.admin_users, flux.audit_log
TO authenticated;

-- ---------------------------------------------------------------------
-- 5. Limpieza total de policies previas (idempotencia)
-- ---------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT schemaname, tablename, policyname
             FROM pg_policies
            WHERE schemaname = 'flux'
  LOOP
    EXECUTE format('DROP POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 6. Public READ policies (TO anon, authenticated) — solo activos
-- ---------------------------------------------------------------------
CREATE POLICY "public read active brands"
  ON flux.brands         FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read active categories"
  ON flux.categories     FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read active goals"
  ON flux.goals          FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read active products"
  ON flux.products       FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

-- Hijos gateados por el estado del padre
CREATE POLICY "public read images of active products"
  ON flux.product_images FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM flux.products p
     WHERE p.id = product_images.product_id
       AND p.active IS TRUE
  ));

CREATE POLICY "public read goals of active products"
  ON flux.product_goals  FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM flux.products p
     WHERE p.id = product_goals.product_id
       AND p.active IS TRUE
  ));

CREATE POLICY "public read active ingredients"
  ON flux.ingredients    FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read active routines"
  ON flux.routines       FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read items of active routines"
  ON flux.routine_items  FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM flux.routines r
     WHERE r.id = routine_items.routine_id
       AND r.active IS TRUE
  ));

CREATE POLICY "public read approved testimonials"
  ON flux.testimonials   FOR SELECT TO anon, authenticated
  USING (approved IS TRUE);

CREATE POLICY "public read active faq categories"
  ON flux.faq_categories FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read active faqs"
  ON flux.faqs           FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read active content blocks"
  ON flux.content_blocks FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

-- ---------------------------------------------------------------------
-- 7. Admin CRUD — 4 policies por tabla (SELECT/INSERT/UPDATE/DELETE)
-- ---------------------------------------------------------------------
-- Helper para no reescribir 13×4 policies a mano — se generan en un bloque
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[
    'brands','categories','goals','products',
    'product_images','product_goals','ingredients',
    'routines','routine_items','testimonials',
    'faq_categories','faqs','content_blocks'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format($f$
      CREATE POLICY "admin select %1$s" ON flux.%1$I
        FOR SELECT TO authenticated
        USING ((SELECT private.is_admin()));
      CREATE POLICY "admin insert %1$s" ON flux.%1$I
        FOR INSERT TO authenticated
        WITH CHECK ((SELECT private.is_admin()));
      CREATE POLICY "admin update %1$s" ON flux.%1$I
        FOR UPDATE TO authenticated
        USING ((SELECT private.is_admin()))
        WITH CHECK ((SELECT private.is_admin()));
      CREATE POLICY "admin delete %1$s" ON flux.%1$I
        FOR DELETE TO authenticated
        USING ((SELECT private.is_admin()));
    $f$, t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 8. Tablas 100% administrativas — sin lectura pública
-- ---------------------------------------------------------------------
CREATE POLICY "admin select admin_users"
  ON flux.admin_users FOR SELECT TO authenticated
  USING ((SELECT private.is_admin()));

CREATE POLICY "admin insert admin_users"
  ON flux.admin_users FOR INSERT TO authenticated
  WITH CHECK ((SELECT private.is_admin()));

CREATE POLICY "admin update admin_users"
  ON flux.admin_users FOR UPDATE TO authenticated
  USING ((SELECT private.is_admin()))
  WITH CHECK ((SELECT private.is_admin()));

CREATE POLICY "admin delete admin_users"
  ON flux.admin_users FOR DELETE TO authenticated
  USING ((SELECT private.is_admin()));

CREATE POLICY "admin select audit"
  ON flux.audit_log FOR SELECT TO authenticated
  USING ((SELECT private.is_admin()));

CREATE POLICY "admin insert audit"
  ON flux.audit_log FOR INSERT TO authenticated
  WITH CHECK ((SELECT private.is_admin()));

-- ---------------------------------------------------------------------
-- 9. Storage — bucket product-images · idempotente de verdad
-- ---------------------------------------------------------------------
-- Drops de nombres viejos y nuevos (por si se re-corre)
DROP POLICY IF EXISTS "public read product images"    ON storage.objects;
DROP POLICY IF EXISTS "admins upload product images"  ON storage.objects;
DROP POLICY IF EXISTS "admins update product images"  ON storage.objects;
DROP POLICY IF EXISTS "admins delete product images"  ON storage.objects;
DROP POLICY IF EXISTS "anon read product images"      ON storage.objects;
DROP POLICY IF EXISTS "admin upload product images"   ON storage.objects;
DROP POLICY IF EXISTS "admin update product images"   ON storage.objects;
DROP POLICY IF EXISTS "admin delete product images"   ON storage.objects;

CREATE POLICY "anon read product images"
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id = 'product-images');

CREATE POLICY "admin upload product images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'product-images'
    AND (SELECT private.is_admin())
  );

CREATE POLICY "admin update product images"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'product-images'
    AND (SELECT private.is_admin())
  )
  WITH CHECK (
    bucket_id = 'product-images'
    AND (SELECT private.is_admin())
  );

CREATE POLICY "admin delete product images"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'product-images'
    AND (SELECT private.is_admin())
  );

-- =====================================================================
-- LISTO.
-- Verificación rápida:
--   SELECT policyname, cmd, roles FROM pg_policies WHERE schemaname='flux' ORDER BY tablename, cmd;
--   SELECT relname, relrowsecurity FROM pg_class WHERE relnamespace = 'flux'::regnamespace;
-- =====================================================================
