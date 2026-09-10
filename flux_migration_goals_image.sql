-- =====================================================================
-- FLUX · Migración: image_url en goals
-- =====================================================================
-- Agrega una columna image_url a flux.goals para que cada objetivo pueda
-- tener su propia imagen en la home (sección "Compra según lo que necesitás").
-- Idempotente.
-- =====================================================================

ALTER TABLE flux.goals
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Opcional: seed con las imágenes que usa la home hardcoded actual
UPDATE flux.goals SET image_url = 'assets/catalogo/energia-y-rendimiento-fisico/cafeina-energy/04_cafeina_energy_packs_vitaminway-8fec079e.png' WHERE slug = 'energia' AND image_url IS NULL;
UPDATE flux.goals SET image_url = 'assets/catalogo/memoria/cognitive-dha/02_cognitive_dha_packs_vitaminway-944c902b.png'                        WHERE slug = 'foco'     AND image_url IS NULL;
UPDATE flux.goals SET image_url = 'assets/catalogo/vitaminas-y-minerales/citrato-de-magnesio-sleep-calm/02_citrato_de_magnesio_sleep_calm_packs_vitaminway-3de20bc1.png' WHERE slug = 'equilibrio' AND image_url IS NULL;
UPDATE flux.goals SET image_url = 'assets/catalogo/digestion/probioticos-prebiotico/04_probiotico_1k_packs_vitaminway-44060204.png'             WHERE slug = 'digestion' AND image_url IS NULL;
UPDATE flux.goals SET image_url = 'assets/catalogo/nutricosmetica/colageno-beauty/04_colageno_beuty-9d7a0fec.png'                              WHERE slug = 'belleza'   AND image_url IS NULL;
UPDATE flux.goals SET image_url = 'assets/catalogo/mujer/arandano-ury/02_arandano_ury_packs_vitaminway-263ccce7.png'                           WHERE slug = 'femenina'  AND image_url IS NULL;
UPDATE flux.goals SET image_url = 'assets/catalogo/sport-fitness/pre-work/03_guia_vitaminway_sport_pre_work-2ab2ee51.png'                      WHERE slug = 'rendimiento' AND image_url IS NULL;
UPDATE flux.goals SET image_url = 'assets/catalogo/vitaminas-y-minerales/multivitaminico-y-multimineral/04_multivitaminico_packs_vitaminway-b5fc3afd.png' WHERE slug = 'bienestar' AND image_url IS NULL;
