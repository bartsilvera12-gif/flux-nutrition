-- =====================================================================
-- NEURA · 00 · SECURITY BOOTSTRAP  (global · una sola vez por instancia)
-- =====================================================================
-- Ejecutar UNA sola vez al inicializar la instancia Supabase,
-- ANTES de aplicar cualquier tenant pack.
--
-- ⚠️  NO re-ejecutar después de instalar tenants: el `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA private` de la sección 1 stripearía el
--     EXECUTE de todas las funciones is_<tenant>_admin() ya instaladas
--     y los paneles admin dejarían de autorizar hasta re-correr sus packs.
--
-- No pertenece a ningún tenant. NO tocar desde una migración de tenant.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Schema `private` (NUNCA agregar a "Exposed schemas" en Data API)
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL   ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT  USAGE ON SCHEMA private TO authenticated;

-- Default privileges para futuras funciones/tablas privadas
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private
  REVOKE ALL     ON TABLES    FROM anon, authenticated;

-- Cierre inicial de funciones EXISTENTES en `private`
-- (los tenant packs habilitan puntualmente su propia is_<tenant>_admin())
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;

-- =====================================================================
-- CONFIG MANUAL EN DASHBOARD (una sola vez, no scripteable):
--   Data API → Exposed schemas: NO agregar `private`.
--   Agregar solo los schemas de tenants (flux, joguaha, wimali, …).
-- =====================================================================
