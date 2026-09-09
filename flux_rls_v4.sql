-- =====================================================================
-- FLUX · RLS pack v4 — plantilla Neura definitiva
-- =====================================================================
-- Deny-by-default a nivel RLS + GRANT explícitos
-- auth.uid() como identidad
-- private.is_flux_admin() (namespacing por tenant, sin colisiones)
-- SECURITY DEFINER + search_path = '' + owner postgres
-- Policies separadas por operación con (SELECT ...) init-plan
-- Hijos públicos gateados por estado del padre (Y del target cuando aplica)
-- Default privileges futuros → cerrados
-- REVOKE EXECUTE en funciones del schema expuesto
-- password_hash eliminado (Supabase Auth lo maneja)
-- Storage idempotente
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Schema privado (NO expuesto a la Data API)
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL   ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT  USAGE ON SCHEMA private TO authenticated;

-- Objetos futuros en `private` nacen cerrados
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private
  REVOKE ALL     ON TABLES    FROM anon, authenticated;

-- ---------------------------------------------------------------------
-- 1. USAGE del schema flux (necesario para PostgREST) + defaults cerrados
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA flux TO anon, authenticated;

-- Objetos futuros en `flux` nacen sin acceso al anon/authenticated —
-- hay que habilitarlos explícitamente si se agregan tablas nuevas
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA flux
  REVOKE ALL      ON TABLES    FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA flux
  REVOKE EXECUTE  ON FUNCTIONS FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA flux
  REVOKE USAGE, SELECT ON SEQUENCES FROM anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Migración admin_users → user_id + limpieza legacy
-- ---------------------------------------------------------------------
ALTER TABLE flux.admin_users
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_admin_users_user_id
  ON flux.admin_users (user_id) WHERE user_id IS NOT NULL;

-- Vincula filas existentes al auth.users correspondiente (por email)
UPDATE flux.admin_users au
   SET user_id = u.id
  FROM auth.users u
 WHERE au.user_id IS NULL
   AND lower(au.email) = lower(u.email);

-- Password_hash ya no lo usamos → se elimina (Supabase Auth maneja las passwords)
ALTER TABLE flux.admin_users DROP COLUMN IF EXISTS password_hash;

-- ---------------------------------------------------------------------
-- 3. Limpieza total de policies + función vieja (en el orden correcto)
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

-- Ahora sí, sin dependencias, se puede eliminar la función vieja
DROP FUNCTION IF EXISTS flux.is_admin();
DROP FUNCTION IF EXISTS private.is_admin();

-- ---------------------------------------------------------------------
-- 4. private.is_flux_admin() — namespacing por tenant
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_flux_admin()
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

ALTER FUNCTION private.is_flux_admin() OWNER TO postgres;

REVOKE ALL   ON FUNCTION private.is_flux_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_flux_admin() TO authenticated;

-- ---------------------------------------------------------------------
-- 5. RLS ON en todas las tablas expuestas
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
-- 6. GRANT/REVOKE explícitos sobre TABLAS existentes (deny by default)
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA flux FROM anon, authenticated;

-- Tablas públicas de la tienda: SELECT anon+authenticated; DML solo authenticated (RLS filtra al admin)
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
-- 7. Cerrar TODAS las funciones/RPC de flux al público — habilitar solo las necesarias
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA flux FROM PUBLIC, anon, authenticated;

-- Si en algún momento hay RPCs públicas o admin, se habilitan puntualmente:
--   GRANT EXECUTE ON FUNCTION flux.mi_rpc_publica(...) TO anon, authenticated;
--   GRANT EXECUTE ON FUNCTION flux.mi_rpc_admin(...)   TO authenticated;

-- ---------------------------------------------------------------------
-- 8. Public READ policies — solo activos, hijos gateados por el padre (y target)
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

CREATE POLICY "public read images of active products"
  ON flux.product_images FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM flux.products p
     WHERE p.id = product_images.product_id
       AND p.active IS TRUE
  ));

-- product_goals: activo el producto Y activo el goal
CREATE POLICY "public read goals of active products"
  ON flux.product_goals  FOR SELECT TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM flux.products p
       WHERE p.id = product_goals.product_id
         AND p.active IS TRUE
    )
    AND EXISTS (
      SELECT 1 FROM flux.goals g
       WHERE g.id = product_goals.goal_id
         AND g.active IS TRUE
    )
  );

CREATE POLICY "public read active ingredients"
  ON flux.ingredients    FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read active routines"
  ON flux.routines       FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

-- routine_items: activa la rutina Y activo el producto
CREATE POLICY "public read items of active routines"
  ON flux.routine_items  FOR SELECT TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM flux.routines r
       WHERE r.id = routine_items.routine_id
         AND r.active IS TRUE
    )
    AND EXISTS (
      SELECT 1 FROM flux.products p
       WHERE p.id = routine_items.product_id
         AND p.active IS TRUE
    )
  );

CREATE POLICY "public read approved testimonials"
  ON flux.testimonials   FOR SELECT TO anon, authenticated
  USING (approved IS TRUE);

CREATE POLICY "public read active faq categories"
  ON flux.faq_categories FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

-- faqs: activa la FAQ Y activa la categoría (si tiene)
CREATE POLICY "public read active faqs"
  ON flux.faqs           FOR SELECT TO anon, authenticated
  USING (
    active IS TRUE
    AND (
      category_id IS NULL
      OR EXISTS (
        SELECT 1 FROM flux.faq_categories fc
         WHERE fc.id = faqs.category_id
           AND fc.active IS TRUE
      )
    )
  );

CREATE POLICY "public read active content blocks"
  ON flux.content_blocks FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

-- ---------------------------------------------------------------------
-- 9. Admin CRUD — 4 policies por tabla, generadas en loop
-- ---------------------------------------------------------------------
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
        USING ((SELECT private.is_flux_admin()));
      CREATE POLICY "admin insert %1$s" ON flux.%1$I
        FOR INSERT TO authenticated
        WITH CHECK ((SELECT private.is_flux_admin()));
      CREATE POLICY "admin update %1$s" ON flux.%1$I
        FOR UPDATE TO authenticated
        USING ((SELECT private.is_flux_admin()))
        WITH CHECK ((SELECT private.is_flux_admin()));
      CREATE POLICY "admin delete %1$s" ON flux.%1$I
        FOR DELETE TO authenticated
        USING ((SELECT private.is_flux_admin()));
    $f$, t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 10. Tablas 100% administrativas — sin lectura pública
-- ---------------------------------------------------------------------
CREATE POLICY "admin select admin_users"
  ON flux.admin_users FOR SELECT TO authenticated
  USING ((SELECT private.is_flux_admin()));

CREATE POLICY "admin insert admin_users"
  ON flux.admin_users FOR INSERT TO authenticated
  WITH CHECK ((SELECT private.is_flux_admin()));

CREATE POLICY "admin update admin_users"
  ON flux.admin_users FOR UPDATE TO authenticated
  USING ((SELECT private.is_flux_admin()))
  WITH CHECK ((SELECT private.is_flux_admin()));

CREATE POLICY "admin delete admin_users"
  ON flux.admin_users FOR DELETE TO authenticated
  USING ((SELECT private.is_flux_admin()));

CREATE POLICY "admin select audit"
  ON flux.audit_log FOR SELECT TO authenticated
  USING ((SELECT private.is_flux_admin()));

CREATE POLICY "admin insert audit"
  ON flux.audit_log FOR INSERT TO authenticated
  WITH CHECK ((SELECT private.is_flux_admin()));

-- ---------------------------------------------------------------------
-- 11. Storage — bucket product-images (público de lectura por diseño)
-- ---------------------------------------------------------------------
-- Cleanup total de nombres viejos y nuevos
DROP POLICY IF EXISTS "public read product images"    ON storage.objects;
DROP POLICY IF EXISTS "admins upload product images"  ON storage.objects;
DROP POLICY IF EXISTS "admins update product images"  ON storage.objects;
DROP POLICY IF EXISTS "admins delete product images"  ON storage.objects;
DROP POLICY IF EXISTS "anon read product images"      ON storage.objects;
DROP POLICY IF EXISTS "admin upload product images"   ON storage.objects;
DROP POLICY IF EXISTS "admin update product images"   ON storage.objects;
DROP POLICY IF EXISTS "admin delete product images"   ON storage.objects;

-- Lectura pública (bucket Public → downloads directos bypasean RLS igual).
-- Esto habilita también LIST metadata via Storage API.
CREATE POLICY "anon read product images"
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id = 'product-images');

CREATE POLICY "admin upload product images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'product-images'
    AND (SELECT private.is_flux_admin())
  );

CREATE POLICY "admin update product images"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'product-images'
    AND (SELECT private.is_flux_admin())
  )
  WITH CHECK (
    bucket_id = 'product-images'
    AND (SELECT private.is_flux_admin())
  );

CREATE POLICY "admin delete product images"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'product-images'
    AND (SELECT private.is_flux_admin())
  );

-- =====================================================================
-- Verificación:
--   SELECT policyname, cmd, roles FROM pg_policies WHERE schemaname='flux' ORDER BY tablename, cmd;
--   SELECT relname, relrowsecurity FROM pg_class WHERE relnamespace = 'flux'::regnamespace;
--   SELECT proname, pronamespace::regnamespace FROM pg_proc WHERE proname LIKE '%is_%admin%';
-- =====================================================================
