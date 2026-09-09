-- =====================================================================
-- FLUX · RLS pack v5 — estándar Neura (endurecido)
-- =====================================================================
-- Cambios sobre v4:
--   1) admin_users: admin SOLO puede SELECT (no puede crear/editar/borrar admins
--      desde el frontend — eso pasa por service_role/backend/superadmin).
--   2) audit_log: admin SOLO puede SELECT (los inserts vienen de triggers/backend).
--   3) No dropea private.is_admin() global — cada tenant limpia lo suyo.
--   4) Storage: se saca la policy SELECT anon (los downloads públicos funcionan
--      por bucket=Public de todos modos; el LIST queda solo para admins).
-- Idempotente end-to-end. Deny-by-default.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Schema privado (NO expuesto a la Data API)
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL   ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT  USAGE ON SCHEMA private TO authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private
  REVOKE ALL     ON TABLES    FROM anon, authenticated;

-- ---------------------------------------------------------------------
-- 1. USAGE del schema flux + defaults cerrados
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA flux TO anon, authenticated;

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

UPDATE flux.admin_users au
   SET user_id = u.id
  FROM auth.users u
 WHERE au.user_id IS NULL
   AND lower(au.email) = lower(u.email);

ALTER TABLE flux.admin_users DROP COLUMN IF EXISTS password_hash;

-- ---------------------------------------------------------------------
-- 3. Limpieza de policies + DROP local (NO tocar la función global)
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

-- Solo eliminamos el wrapper propio de FLUX. private.is_admin() (si existe)
-- podría estar en uso por otro tenant → NO se toca desde acá.
DROP FUNCTION IF EXISTS flux.is_admin();

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
-- 6. GRANT/REVOKE sobre TABLAS existentes
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

-- admin_users: SOLO SELECT desde el frontend. Escrituras van por backend/service_role.
GRANT SELECT ON flux.admin_users TO authenticated;

-- audit_log: SOLO SELECT. Los INSERTs vienen de triggers (SECURITY DEFINER) o backend.
GRANT SELECT ON flux.audit_log TO authenticated;

-- ---------------------------------------------------------------------
-- 7. Cerrar TODAS las funciones/RPC de flux
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA flux FROM PUBLIC, anon, authenticated;

-- Habilitar puntualmente si aparece alguna RPC pública:
--   GRANT EXECUTE ON FUNCTION flux.rpc_publica(...)  TO anon, authenticated;
--   GRANT EXECUTE ON FUNCTION flux.rpc_admin(...)    TO authenticated;

-- ---------------------------------------------------------------------
-- 8. Public READ policies — solo activos, hijos gateados por padre (y target)
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

CREATE POLICY "public read goals of active products"
  ON flux.product_goals  FOR SELECT TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM flux.products p
       WHERE p.id = product_goals.product_id AND p.active IS TRUE
    )
    AND EXISTS (
      SELECT 1 FROM flux.goals g
       WHERE g.id = product_goals.goal_id AND g.active IS TRUE
    )
  );

CREATE POLICY "public read active ingredients"
  ON flux.ingredients    FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read active routines"
  ON flux.routines       FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read items of active routines"
  ON flux.routine_items  FOR SELECT TO anon, authenticated
  USING (
    EXISTS (SELECT 1 FROM flux.routines r WHERE r.id = routine_items.routine_id AND r.active IS TRUE)
    AND EXISTS (SELECT 1 FROM flux.products p WHERE p.id = routine_items.product_id AND p.active IS TRUE)
  );

CREATE POLICY "public read approved testimonials"
  ON flux.testimonials   FOR SELECT TO anon, authenticated
  USING (approved IS TRUE);

CREATE POLICY "public read active faq categories"
  ON flux.faq_categories FOR SELECT TO anon, authenticated
  USING (active IS TRUE);

CREATE POLICY "public read active faqs"
  ON flux.faqs           FOR SELECT TO anon, authenticated
  USING (
    active IS TRUE
    AND (
      category_id IS NULL
      OR EXISTS (SELECT 1 FROM flux.faq_categories fc WHERE fc.id = faqs.category_id AND fc.active IS TRUE)
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
-- 10. Tablas 100% administrativas · SOLO SELECT desde el frontend
-- ---------------------------------------------------------------------
-- admin_users: leer sí, escribir NO desde el panel.
-- Alta/edición/baja de admins → service_role/backend/superadmin.
CREATE POLICY "admin select admin_users"
  ON flux.admin_users FOR SELECT TO authenticated
  USING ((SELECT private.is_flux_admin()));

-- audit_log: solo lectura. Los inserts los hacen triggers SECURITY DEFINER
-- o el backend con service_role — nunca desde el cliente.
CREATE POLICY "admin select audit"
  ON flux.audit_log FOR SELECT TO authenticated
  USING ((SELECT private.is_flux_admin()));

-- ---------------------------------------------------------------------
-- 11. Storage — bucket product-images (forzado a Public por script)
-- ---------------------------------------------------------------------
-- Asegura la existencia y estado Public del bucket (idempotente)
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

-- Cleanup total
DROP POLICY IF EXISTS "public read product images"    ON storage.objects;
DROP POLICY IF EXISTS "admins upload product images"  ON storage.objects;
DROP POLICY IF EXISTS "admins update product images"  ON storage.objects;
DROP POLICY IF EXISTS "admins delete product images"  ON storage.objects;
DROP POLICY IF EXISTS "anon read product images"      ON storage.objects;
DROP POLICY IF EXISTS "admin upload product images"   ON storage.objects;
DROP POLICY IF EXISTS "admin update product images"   ON storage.objects;
DROP POLICY IF EXISTS "admin delete product images"   ON storage.objects;
DROP POLICY IF EXISTS "admin list product images"     ON storage.objects;

-- Descarga por URL pública: el bucket=Public bypasea RLS → no hace falta
-- policy SELECT para anon. LIST queda restringido al admin autenticado.
CREATE POLICY "admin list product images"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'product-images'
    AND (SELECT private.is_flux_admin())
  );

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

-- ---------------------------------------------------------------------
-- 12. SEQUENCES — grants selectivos (solo si alguna tabla usa SERIAL/nextval)
-- ---------------------------------------------------------------------
-- El schema FLUX usa gen_random_uuid() en todas las PKs → no hace falta
-- otorgar USAGE en sequences para el flujo normal.
--
-- Si en el futuro se agrega una tabla con SERIAL/BIGSERIAL, habilitar puntualmente:
--   GRANT USAGE ON SEQUENCE flux.<tabla>_id_seq TO authenticated;
-- (No abrir USAGE global — mantener least-privilege.)

-- =====================================================================
-- Notas operativas:
--
-- CONFIGURACIÓN MANUAL EN DASHBOARD (una sola vez):
--   Data API → Exposed schemas: agregar `flux`; NO agregar `private`.
--
-- CREAR NUEVOS ADMINS: no se puede desde el panel. Opciones:
--   a) Dashboard → Authentication → Users → Add user (crea auth.users)
--      + INSERT manual en flux.admin_users vía SQL Editor con service_role.
--   b) Un backend/Edge Function con service_role que inserte por vos.
--   c) Un rol "superadmin" agregado más adelante con policies extra.
--
-- REGISTRAR EVENTOS EN audit_log:
--   Vía trigger SECURITY DEFINER en las tablas que quieras auditar,
--   o desde un backend con service_role.
-- =====================================================================


-- =====================================================================
-- SECURITY CHECKS — correr después del pack; verifican el hardening
-- =====================================================================

-- 1) Tablas del schema flux sin RLS (debe ser 0 filas)
SELECT schemaname, tablename
  FROM pg_tables
 WHERE schemaname = 'flux'
   AND rowsecurity IS FALSE;

-- 2) Grants de escritura al anon sobre flux (debe ser 0 filas)
SELECT table_schema, table_name, privilege_type
  FROM information_schema.role_table_grants
 WHERE table_schema = 'flux'
   AND grantee      = 'anon'
   AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE');

-- 3) authenticated NO puede administrar admin_users (esperado: false | false | false)
SELECT
  has_table_privilege('authenticated', 'flux.admin_users', 'INSERT') AS can_insert_admin,
  has_table_privilege('authenticated', 'flux.admin_users', 'UPDATE') AS can_update_admin,
  has_table_privilege('authenticated', 'flux.admin_users', 'DELETE') AS can_delete_admin;

-- 4) authenticated NO puede escribir audit_log (esperado: false | false | false)
SELECT
  has_table_privilege('authenticated', 'flux.audit_log', 'INSERT') AS can_insert_audit,
  has_table_privilege('authenticated', 'flux.audit_log', 'UPDATE') AS can_update_audit,
  has_table_privilege('authenticated', 'flux.audit_log', 'DELETE') AS can_delete_audit;

-- 5) Funciones ejecutables por anon en flux (debe ser 0 filas — todo cerrado)
SELECT n.nspname AS schema, p.proname AS function
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'flux'
   AND has_function_privilege('anon', p.oid, 'EXECUTE');

-- 6) Bucket product-images marcado como Public (esperado: t)
SELECT id, public FROM storage.buckets WHERE id = 'product-images';

-- 7) Recuento de policies por tabla en flux (sanity — debe haber ≥1 por tabla)
SELECT tablename, count(*) AS policies
  FROM pg_policies
 WHERE schemaname = 'flux'
 GROUP BY tablename
 ORDER BY tablename;
-- =====================================================================
