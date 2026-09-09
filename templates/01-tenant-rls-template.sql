-- =====================================================================
-- NEURA · 01 · TENANT RLS TEMPLATE
-- =====================================================================
-- Plantilla por tenant. Buscar y reemplazar antes de correr:
--
--   {{TENANT}}         → slug del tenant (ej. `flux`)                → nombre del schema
--   {{TENANT_ADMIN}}   → ej. `is_flux_admin`                         → función en `private`
--   {{BUCKET}}         → ej. `product-images`                        → bucket público de assets
--   {{PUBLIC_TABLES}}  → lista de tablas públicas (SELECT anon)      → completar al pie
--   {{ADMIN_TABLES}}   → lista de tablas admin-only (SELECT admin)   → completar al pie
--
-- Requisitos:
--   - Correr 00-neura-security-bootstrap.sql antes.
--   - En {{TENANT}}.admin_users debe existir la columna user_id UUID
--     con FK a auth.users(id) (la sección 2 la crea si falta).
--
-- Deny-by-default · Idempotente · Multi-tenant safe (no toca otros schemas)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. USAGE + default privileges del schema del tenant
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA {{TENANT}} TO anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA {{TENANT}}
  REVOKE ALL      ON TABLES    FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA {{TENANT}}
  REVOKE EXECUTE  ON FUNCTIONS FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA {{TENANT}}
  REVOKE USAGE, SELECT ON SEQUENCES FROM anon, authenticated;

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
-- 2. Limpieza de policies del tenant + wrapper local viejo (si existía)
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

-- IMPORTANTE: NO hacer DROP de otras funciones de `private`. Cada tenant
-- solo administra su propia is_<tenant>_admin().

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
-- 4. RLS ON en todas las tablas del tenant + admin_users/audit_log
-- ---------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT tablename
             FROM pg_tables
            WHERE schemaname = '{{TENANT}}'
  LOOP
    EXECUTE format('ALTER TABLE {{TENANT}}.%I ENABLE ROW LEVEL SECURITY', r.tablename);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 5. GRANT/REVOKE sobre tablas existentes
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA {{TENANT}} FROM anon, authenticated;

-- Tablas públicas: SELECT anon+authenticated; DML solo authenticated (RLS filtra)
--   → COMPLETAR la lista {{PUBLIC_TABLES}} y descomentar:
-- GRANT SELECT ON {{PUBLIC_TABLES}} TO anon, authenticated;
-- GRANT INSERT, UPDATE, DELETE ON {{PUBLIC_TABLES}} TO authenticated;

-- Tablas 100% administrativas · SOLO SELECT desde el frontend
GRANT SELECT ON {{TENANT}}.admin_users TO authenticated;
GRANT SELECT ON {{TENANT}}.audit_log   TO authenticated;

-- ---------------------------------------------------------------------
-- 6. Cerrar TODAS las funciones/RPC del tenant · habilitar puntualmente
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA {{TENANT}} FROM PUBLIC, anon, authenticated;

-- Habilitar puntualmente si hay RPCs necesarias:
--   GRANT EXECUTE ON FUNCTION {{TENANT}}.rpc_publica(...) TO anon, authenticated;
--   GRANT EXECUTE ON FUNCTION {{TENANT}}.rpc_admin(...)   TO authenticated;

-- ---------------------------------------------------------------------
-- 7. Public READ policies (patrones a instanciar por cada tabla)
-- ---------------------------------------------------------------------
-- Patrón A · tabla con columna `active`:
--   CREATE POLICY "public read active <tabla>"
--     ON {{TENANT}}.<tabla> FOR SELECT TO anon, authenticated
--     USING (active IS TRUE);
--
-- Patrón B · tabla hija — gateada por el estado del padre:
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
-- 8. Admin CRUD — generador para lista de tablas públicas del tenant
-- ---------------------------------------------------------------------
-- COMPLETAR el array con las tablas públicas del tenant:
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[/* {{PUBLIC_TABLES sin schema}} p.ej. 'brands','products' */];
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
-- 9. admin_users + audit_log · SOLO SELECT
-- ---------------------------------------------------------------------
CREATE POLICY "admin select admin_users"
  ON {{TENANT}}.admin_users FOR SELECT TO authenticated
  USING ((SELECT private.{{TENANT_ADMIN}}()));

CREATE POLICY "admin select audit"
  ON {{TENANT}}.audit_log FOR SELECT TO authenticated
  USING ((SELECT private.{{TENANT_ADMIN}}()));

-- ---------------------------------------------------------------------
-- 10. Storage — bucket {{BUCKET}} público (forzado por script)
-- ---------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('{{BUCKET}}', '{{BUCKET}}', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

-- Cleanup (idempotente)
DROP POLICY IF EXISTS "anon read {{BUCKET}}"    ON storage.objects;
DROP POLICY IF EXISTS "admin list {{BUCKET}}"   ON storage.objects;
DROP POLICY IF EXISTS "admin upload {{BUCKET}}" ON storage.objects;
DROP POLICY IF EXISTS "admin update {{BUCKET}}" ON storage.objects;
DROP POLICY IF EXISTS "admin delete {{BUCKET}}" ON storage.objects;

-- LIST solo para admin autenticado (downloads por URL bypasean RLS por bucket=Public)
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
SELECT schemaname, tablename
  FROM pg_tables
 WHERE schemaname = '{{TENANT}}' AND rowsecurity IS FALSE;

-- 2) Grants de escritura al anon en el tenant (esperado: 0)
SELECT table_schema, table_name, privilege_type
  FROM information_schema.role_table_grants
 WHERE table_schema = '{{TENANT}}' AND grantee = 'anon'
   AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE');

-- 3) authenticated NO puede escribir admin_users (esperado: f | f | f)
SELECT
  has_table_privilege('authenticated', '{{TENANT}}.admin_users', 'INSERT') AS can_insert_admin,
  has_table_privilege('authenticated', '{{TENANT}}.admin_users', 'UPDATE') AS can_update_admin,
  has_table_privilege('authenticated', '{{TENANT}}.admin_users', 'DELETE') AS can_delete_admin;

-- 4) authenticated NO puede escribir audit_log (esperado: f | f | f)
SELECT
  has_table_privilege('authenticated', '{{TENANT}}.audit_log', 'INSERT') AS can_insert_audit,
  has_table_privilege('authenticated', '{{TENANT}}.audit_log', 'UPDATE') AS can_update_audit,
  has_table_privilege('authenticated', '{{TENANT}}.audit_log', 'DELETE') AS can_delete_audit;

-- 5) Funciones ejecutables por anon en el tenant (esperado: 0)
SELECT n.nspname AS schema, p.proname AS function
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = '{{TENANT}}' AND has_function_privilege('anon', p.oid, 'EXECUTE');

-- 6) Bucket público (esperado: t)
SELECT id, public FROM storage.buckets WHERE id = '{{BUCKET}}';

-- 7) Recuento de policies por tabla (esperado: ≥1 cada una)
SELECT tablename, count(*) AS policies
  FROM pg_policies WHERE schemaname = '{{TENANT}}'
 GROUP BY tablename ORDER BY tablename;

-- 8) VIEWS en el schema expuesto — cada una debe tener security_invoker=true
--    o quedar fuera del schema expuesto. Revisar manualmente:
SELECT n.nspname AS schema, c.relname AS view,
       (SELECT option_value FROM pg_options_to_table(c.reloptions)
         WHERE option_name = 'security_invoker') AS security_invoker
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = '{{TENANT}}' AND c.relkind IN ('v','m');
--    Para arreglar una view sensible:
--      ALTER VIEW {{TENANT}}.<view> SET (security_invoker = true);
-- =====================================================================
