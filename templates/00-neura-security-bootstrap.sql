-- =====================================================================
-- NEURA · 00 · SECURITY BOOTSTRAP  (global · una sola vez por instancia)
-- =====================================================================
-- Ejecutar UNA sola vez al inicializar la instancia Supabase,
-- ANTES de aplicar cualquier tenant pack.
--
-- ⚠️  NO re-ejecutar la sección "OBJETOS PRIVATE YA EXISTENTES" una vez
--     instalados los tenants: el REVOKE EXECUTE sobre ALL FUNCTIONS IN
--     SCHEMA private stripearía el EXECUTE de is_<tenant>_admin() ya
--     instaladas y los paneles admin dejarían de autorizar hasta
--     re-correr sus packs.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Schema `private` (NUNCA agregar a Exposed schemas en Data API)
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL   ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT  USAGE ON SCHEMA private TO authenticated;

-- ---------------------------------------------------------------------
-- 2. DEFAULT PRIVILEGES GLOBALES para el rol `postgres`
--    (sin IN SCHEMA → aplica a objetos futuros creados por postgres
--     en CUALQUIER schema; cancela también el default global de PUBLIC
--     que otorga EXECUTE en funciones)
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE ALL     ON TABLES    FROM PUBLIC, anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE USAGE, SELECT ON SEQUENCES FROM PUBLIC, anon, authenticated;

-- ⚠️  Nota importante: ALTER DEFAULT PRIVILEGES es POR ROL.
--     Si migraciones/procesos crean objetos con otro owner
--     (p.ej. `supabase_admin`, un rol de CI/CD, o un rol de app),
--     repetir estos ALTER FOR ROLE <ese_rol> para que su default
--     también nazca cerrado. Verificación:
--       SELECT rolname FROM pg_roles;

-- ---------------------------------------------------------------------
-- 3. Cierre de objetos EXISTENTES en `private`
--    (solo tiene efecto la primera vez — ver warning arriba)
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;

-- =====================================================================
-- CONFIG MANUAL EN DASHBOARD (una sola vez, no scripteable):
--   Data API → Exposed schemas:
--     - agregar cada schema de tenant (flux, joguaha, wimali, …)
--     - NO agregar `private`
-- =====================================================================
