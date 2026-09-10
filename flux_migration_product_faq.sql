-- =====================================================================
-- FLUX · Migración: FAQ por producto
-- =====================================================================
-- Agrega columna product_faq a flux.products para poder editar
-- desde el panel el bloque "Preguntas frecuentes" que aparece
-- al final del acordeón del PDP.
--
-- Los beneficios ya existían en la columna `benefits`, solo faltaba
-- exponerlo en el admin (hecho en el drawer sin cambio de schema).
--
-- Las imágenes extras de galería ya están soportadas por la tabla
-- flux.product_images (usar is_primary=false + sort_order).
--
-- Después de correr esto, ejecutar:
--   NOTIFY pgrst, 'reload schema';
-- para que la API refresque el cache.
-- =====================================================================

ALTER TABLE flux.products
  ADD COLUMN IF NOT EXISTS product_faq TEXT;

NOTIFY pgrst, 'reload schema';
