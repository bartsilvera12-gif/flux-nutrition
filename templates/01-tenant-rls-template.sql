-- =====================================================================
-- NEURA · 01 · TENANT RLS TEMPLATE
-- =====================================================================
-- Plantilla por tenant. Buscar y reemplazar antes de correr:
--
--   {{TENANT}}          → slug del tenant (ej. `flux`) → nombre del schema
--   {{TENANT_ADMIN}}    → ej. `is_flux_admin` → función en `private`
--   {{BUCKET}}          → GLOBALMENTE ÚNICO, ej. `flux-product-images`
--
-- Grupos de tablas del tenant (completar los arrays al pie):
--
--   PUBLIC_TABLES        → anon SELECT filtrado + admin CRUD
--   ADMIN_CRUD_TABLES    → solo admin CRUD
--   ADMIN_READONLY_TABLES → solo admin SELECT (escrituras vía backend/service_role)
--
-- Precondición Storage:
--   El bucket {{BUCKET}} debe existir y estar marcado como Public.
--   Crearlo por Supabase Dashboard / Storage API / supabase/config.toml
--   ANTES de correr este pack (Supabase recomienda no manipular
--   storage.buckets directamente vía SQL).
--
-- ⚠️  RE-EJECUTAR este pack ELIMINA todas las policies del tenant y las
--     recrea desde esta plantilla. Cualquier policy especial creada
--     manualmente y no representada acá se pierde. Antes de re-correr,
--     asegurarse de que toda excepción esté volcada al pack.
--
-- Deny-by-default · Idempotente · Multi-tenant safe
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. USAGE del schema + default privileges del schema del tenant
--    service_role incluido: bypassa RLS pero necesita USAGE + grants
--    de tabla para operar (Supabase requiere GRANT explícito en custom
--    schemas para service_role).
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA {{TENANT}} TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA {{TENANT}}
  REVOKE ALL      ON TABLES    FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA {{TENANT}}
  REVOKE EXECUTE  ON FUNCTIONS FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA {{TENANT}}
  REVOKE USAGE, SELECT ON SEQUENCES FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- 1. Migración admin_users → user_id + limpieza legacy
-- ---------------------------------------------------------------------
ALTER TABLE {{TENANT}}.admin_users
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_{{TENANT}}_admin_users_user_id
  ON {{TENANT}}.admin_users (user_id) WHERE user_id IS NOT NULL;

UPDATE {{TENANT}}.admin_users au
   SET user_id = u.id
  FROM auth.users u
 WHERE au.user_id IS NULL
   AND lower(au.email) = lower(u.email);

ALTER TABLE {{TENANT}}.admin_users DROP COLUMN IF EXISTS password_hash;

-- ---------------------------------------------------------------------
-- 2. Limpieza de policies del tenant + wrapper local viejo
-- ---------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT schemaname, tablename, policyname
             FROM pg_policies
            WHERE schemaname = '{{TENANT}}'
  LOOP
    EXECUTE format('DROP POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
  END LOOP;
END $$;

DROP FUNCTION IF EXISTS {{TENANT}}.is_admin();

-- IMPORTANTE: NO hacer DROP de otras funciones de `private`.

-- ---------------------------------------------------------------------
-- 3. private.{{TENANT_ADMIN}}() — chequeo de admin por auth.uid()
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.{{TENANT_ADMIN}}()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM {{TENANT}}.admin_users AS au
    WHERE au.user_id = (SELECT auth.uid())
      AND au.active IS TRUE
  );
$$;

ALTER FUNCTION private.{{TENANT_ADMIN}}() OWNER TO postgres;

REVOKE ALL   ON FUNCTION private.{{TENANT_ADMIN}}() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.{{TENANT_ADMIN}}() TO authenticated;

-- ---------------------------------------------------------------------
-- 4. RLS ON en TODAS las tablas del tenant
-- ---------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = '{{TENANT}}'
  LOOP
    EXECUTE format('ALTER TABLE {{TENANT}}.%I ENABLE ROW LEVEL SECURITY', r.tablename);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 5. REVOKE inicial · deny-by-default en tablas y sequences existentes
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA {{TENANT}} FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA {{TENANT}} FROM PUBLIC, anon, authenticated;

-- ⚠️  SEQUENCES: si alguna tabla usa SERIAL/BIGSERIAL/nextval, habilitar
--     puntualmente su sequence. Si todo usa gen_random_uuid(), no hace falta.
--   GRANT USAGE ON SEQUENCE {{TENANT}}.<tabla>_id_seq TO authenticated;

-- ---------------------------------------------------------------------
-- 6. GRANTs por grupo · COMPLETAR con tablas reales del tenant
-- ---------------------------------------------------------------------

-- Grupo A · PUBLIC_TABLES → SELECT anon+authenticated + DML authenticated (RLS filtra)
-- GRANT SELECT ON
--   {{TENANT}}.brands, {{TENANT}}.categories, {{TENANT}}.products
-- TO anon, authenticated;
-- GRANT INSERT, UPDATE, DELETE ON
--   {{TENANT}}.brands, {{TENANT}}.categories, {{TENANT}}.products
-- TO authenticated;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON
--   {{TENANT}}.brands, {{TENANT}}.categories, {{TENANT}}.products
-- TO service_role;

-- Grupo B · ADMIN_CRUD_TABLES → SELECT+DML authenticated (RLS filtra al admin)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON
--   {{TENANT}}.orders, {{TENANT}}.customers, {{TENANT}}.payments
-- TO authenticated;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON
--   {{TENANT}}.orders, {{TENANT}}.customers, {{TENANT}}.payments
-- TO service_role;

-- Grupo C · ADMIN_READONLY_TABLES → SELECT authenticated (RLS filtra); DML solo service_role
GRANT SELECT ON
  {{TENANT}}.admin_users, {{TENANT}}.audit_log
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON
  {{TENANT}}.admin_users, {{TENANT}}.audit_log
TO service_role;

-- ---------------------------------------------------------------------
-- 7. Cerrar TODAS las funciones/RPC del tenant · habilitar puntualmente
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA {{TENANT}} FROM PUBLIC, anon, authenticated;

-- Habilitar puntualmente si hay RPCs necesarias:
--   GRANT EXECUTE ON FUNCTION {{TENANT}}.rpc_publica(...) TO anon, authenticated;
--   GRANT EXECUTE ON FUNCTION {{TENANT}}.rpc_admin(...)   TO authenticated;

-- ---------------------------------------------------------------------
-- 8. Public READ policies (SOLO para PUBLIC_TABLES)
-- ---------------------------------------------------------------------
-- Patrón A · tabla con columna `active`:
--   CREATE POLICY "public read active <tabla>"
--     ON {{TENANT}}.<tabla> FOR SELECT TO anon, authenticated
--     USING (active IS TRUE);
--
-- Patrón B · hija gateada por el estado del padre:
--   CREATE POLICY "public read <hija> of active <padre>"
--     ON {{TENANT}}.<hija> FOR SELECT TO anon, authenticated
--     USING (EXISTS (
--       SELECT 1 FROM {{TENANT}}.<padre> p
--        WHERE p.id = <hija>.<padre>_id AND p.active IS TRUE
--     ));
--
-- Patrón C · relación N:M — ambos extremos activos:
--   CREATE POLICY "public read <rel>"
--     ON {{TENANT}}.<rel> FOR SELECT TO anon, authenticated
--     USING (
--       EXISTS (SELECT 1 FROM {{TENANT}}.<a> a WHERE a.id = <rel>.<a>_id AND a.active IS TRUE)
--       AND EXISTS (SELECT 1 FROM {{TENANT}}.<b> b WHERE b.id = <rel>.<b>_id AND b.active IS TRUE)
--     );

-- ---------------------------------------------------------------------
-- 9a. Admin CRUD · PUBLIC_TABLES
-- ---------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[/* PUBLIC_TABLES — ej: 'brands','categories','products' */];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format($f$
      CREATE POLICY "admin select %1$s" ON {{TENANT}}.%1$I
        FOR SELECT TO authenticated USING ((SELECT private.{{TENANT_ADMIN}}()));
      CREATE POLICY "admin insert %1$s" ON {{TENANT}}.%1$I
        FOR INSERT TO authenticated WITH CHECK ((SELECT private.{{TENANT_ADMIN}}()));
      CREATE POLICY "admin update %1$s" ON {{TENANT}}.%1$I
        FOR UPDATE TO authenticated
        USING ((SELECT private.{{TENANT_ADMIN}}()))
        WITH CHECK ((SELECT private.{{TENANT_ADMIN}}()));
      CREATE POLICY "admin delete %1$s" ON {{TENANT}}.%1$I
        FOR DELETE TO authenticated USING ((SELECT private.{{TENANT_ADMIN}}()));
    $f$, t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 9b. Admin CRUD · ADMIN_CRUD_TABLES
-- ---------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[/* ADMIN_CRUD_TABLES — ej: 'orders','customers','payments','settings' */];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format($f$
      CREATE POLICY "admin select %1$s" ON {{TENANT}}.%1$I
        FOR SELECT TO authenticated USING ((SELECT private.{{TENANT_ADMIN}}()));
      CREATE POLICY "admin insert %1$s" ON {{TENANT}}.%1$I
        FOR INSERT TO authenticated WITH CHECK ((SELECT private.{{TENANT_ADMIN}}()));
      CREATE POLICY "admin update %1$s" ON {{TENANT}}.%1$I
        FOR UPDATE TO authenticated
        USING ((SELECT private.{{TENANT_ADMIN}}()))
        WITH CHECK ((SELECT private.{{TENANT_ADMIN}}()));
      CREATE POLICY "admin delete %1$s" ON {{TENANT}}.%1$I
        FOR DELETE TO authenticated USING ((SELECT private.{{TENANT_ADMIN}}()));
    $f$, t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 9c. Admin SELECT-only · ADMIN_READONLY_TABLES
--     Escrituras vía backend/service_role (bypassa RLS).
-- ---------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY['admin_users','audit_log'
                        /* agregar más si aparecen: 'security_events','integration_logs',... */];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format($f$
      CREATE POLICY "admin select %1$s" ON {{TENANT}}.%1$I
        FOR SELECT TO authenticated USING ((SELECT private.{{TENANT_ADMIN}}()));
    $f$, t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 10. Storage — policies sobre bucket {{BUCKET}}
--     PRECONDICIÓN: el bucket debe existir y ser Public (crear vía
--     Dashboard / Storage API / supabase/config.toml).
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "anon read {{BUCKET}}"    ON storage.objects;
DROP POLICY IF EXISTS "admin list {{BUCKET}}"   ON storage.objects;
DROP POLICY IF EXISTS "admin upload {{BUCKET}}" ON storage.objects;
DROP POLICY IF EXISTS "admin update {{BUCKET}}" ON storage.objects;
DROP POLICY IF EXISTS "admin delete {{BUCKET}}" ON storage.objects;

-- LIST solo para admin (downloads públicos van por URL directa, bypassa RLS)
CREATE POLICY "admin list {{BUCKET}}"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = '{{BUCKET}}' AND (SELECT private.{{TENANT_ADMIN}}()));

CREATE POLICY "admin upload {{BUCKET}}"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = '{{BUCKET}}' AND (SELECT private.{{TENANT_ADMIN}}()));

CREATE POLICY "admin update {{BUCKET}}"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = '{{BUCKET}}' AND (SELECT private.{{TENANT_ADMIN}}()))
  WITH CHECK (bucket_id = '{{BUCKET}}' AND (SELECT private.{{TENANT_ADMIN}}()));

CREATE POLICY "admin delete {{BUCKET}}"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = '{{BUCKET}}' AND (SELECT private.{{TENANT_ADMIN}}()));


-- =====================================================================
-- SECURITY CHECKS — correr después del pack
-- =====================================================================

-- 1) Tablas del tenant sin RLS (esperado: 0)
SELECT schemaname, tablename FROM pg_tables
 WHERE schemaname = '{{TENANT}}' AND rowsecurity IS FALSE;

-- 2) Grants de escritura al anon (esperado: 0)
SELECT table_schema, table_name, privilege_type
  FROM information_schema.role_table_grants
 WHERE table_schema = '{{TENANT}}' AND grantee = 'anon'
   AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE');

-- 3) authenticated NO puede escribir admin_users / audit_log (esperado: f)
SELECT
  has_table_privilege('authenticated', '{{TENANT}}.admin_users', 'INSERT') AS can_insert_admin,
  has_table_privilege('authenticated', '{{TENANT}}.admin_users', 'UPDATE') AS can_update_admin,
  has_table_privilege('authenticated', '{{TENANT}}.admin_users', 'DELETE') AS can_delete_admin,
  has_table_privilege('authenticated', '{{TENANT}}.audit_log',   'INSERT') AS can_insert_audit,
  has_table_privilege('authenticated', '{{TENANT}}.audit_log',   'UPDATE') AS can_update_audit,
  has_table_privilege('authenticated', '{{TENANT}}.audit_log',   'DELETE') AS can_delete_audit;

-- 4) service_role SÍ puede administrar admin_users / audit_log (esperado: t)
SELECT
  has_table_privilege('service_role', '{{TENANT}}.admin_users', 'INSERT') AS sr_admin_users,
  has_table_privilege('service_role', '{{TENANT}}.audit_log',   'INSERT') AS sr_audit_log;

-- 5) Funciones ejecutables por anon (esperado: 0)
SELECT n.nspname, p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = '{{TENANT}}' AND has_function_privilege('anon', p.oid, 'EXECUTE');

-- 6) Bucket público (esperado: t) — precondición manual
SELECT id, public FROM storage.buckets WHERE id = '{{BUCKET}}';

-- 7) Policies por tabla (esperado: ≥1 cada una)
SELECT tablename, count(*) AS policies FROM pg_policies
 WHERE schemaname = '{{TENANT}}' GROUP BY tablename ORDER BY tablename;

-- 8a) VIEWS normales — cada una debe tener security_invoker=true
SELECT n.nspname AS schema, c.relname AS view,
       (SELECT option_value FROM pg_options_to_table(c.reloptions)
         WHERE option_name = 'security_invoker') AS security_invoker
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = '{{TENANT}}' AND c.relkind = 'v';

-- 8b) MATERIALIZED VIEWS — controlar con GRANTs (no soportan security_invoker)
SELECT n.nspname AS schema, c.relname AS materialized_view
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = '{{TENANT}}' AND c.relkind = 'm';
-- =====================================================================
