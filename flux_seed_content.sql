-- =====================================================================
-- FLUX · SEED contenido editorial (ingredientes, rutinas, testimonios, FAQs)
-- Correr DESPUÉS del schema, policies y flux_seed_products.sql
-- Idempotente (ON CONFLICT DO UPDATE / DO NOTHING).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. INGREDIENTES (los 8 del carousel "Fórmulas transparentes")
-- ---------------------------------------------------------------------
INSERT INTO flux.ingredients (slug, name, kind, description, color, image_url, sort_order, active) VALUES
  ('complejo-b',    'Complejo B',    'Vitamina',     'Metabolismo energético y sistema nervioso.',       '#FF83A7', 'assets/catalogo/vitaminas-y-minerales/multivitaminico-y-multimineral/04_multivitaminico_packs_vitaminway-b5fc3afd.png', 10, TRUE),
  ('bisglicinato',  'Bisglicinato',  'Aminoácido',   'Alta absorción, sin molestias digestivas.',       '#AFC8FF', 'assets/catalogo/vitaminas-y-minerales/bisglicinato-de-magnesio/03_bisglisinato_magnesio_packs_vitaminway-7deba50c.png', 20, TRUE),
  ('ashwagandha',   'Ashwagandha',   'Adaptógeno',   'KSM-66 con evidencia clínica.',                   '#C9A7FF', 'assets/catalogo/sueno-stress/relax-dia/02_relax_dia_packs_vitaminway-774ced97.png', 30, TRUE),
  ('omega-3',       'Omega 3',       'Ácido graso',  'EPA y DHA de aceite de pescado ultrapurificado.', '#8FE9F4', 'assets/catalogo/colesterol/omega-3/04_omega_3_packs_vitaminway-aab9ba1b.png', 40, TRUE),
  ('colageno',      'Colágeno',      'Proteína',     'Péptidos tipo I y III de fácil absorción.',       '#FFD6E8', 'assets/catalogo/nutricosmetica/colageno-beauty/04_colageno_beuty-9d7a0fec.png', 50, TRUE),
  ('d3-k2',         'D3 + K2',       'Vitamina',     'Absorción de calcio y salud ósea.',               '#B7C9FF', 'assets/catalogo/vitaminas-y-minerales/k2-d3/04_k2_d3_packs_vitaminway-e2e9ff75.png', 60, TRUE),
  ('probioticos',   'Probióticos',   'Cepas activas','Equilibrio de la flora intestinal.',              '#C3D9AB', 'assets/catalogo/digestion/probioticos-prebiotico/04_probiotico_1k_packs_vitaminway-44060204.png', 70, TRUE),
  ('coenzima-q10',  'Coenzima Q10',  'Antioxidante', 'Soporte celular y energía mitocondrial.',         '#E07AAE', 'assets/catalogo/nutricosmetica/coenzima-q10/02_coenzima_q10_packs_vitaminway-38a38666.png', 80, TRUE)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name, kind = EXCLUDED.kind, description = EXCLUDED.description,
  color = EXCLUDED.color, image_url = EXCLUDED.image_url, sort_order = EXCLUDED.sort_order;


-- ---------------------------------------------------------------------
-- 2. RUTINAS (las 3 combinaciones "Tu rutina, a tu manera")
-- ---------------------------------------------------------------------
INSERT INTO flux.routines (slug, name, time_label, description, image_url, total_price, savings, sort_order, active) VALUES
  ('rutina-energia',    'Rutina Energía',    'Mañana',         'Para arrancar el día con base y foco.',             'assets/life/wellness-breakfast.jpg', 313000, 35000, 10, TRUE),
  ('rutina-activa',     'Rutina Activa',     'Durante el día', 'Rendimiento y recuperación en días de entreno.',    'assets/life/wellness-active.jpg',    365000, 40000, 20, TRUE),
  ('rutina-equilibrio', 'Rutina Equilibrio', 'Noche',          'Descanso, digestión y bienestar femenino.',         'assets/life/wellness-water.jpg',     309000, 35000, 30, TRUE)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name, time_label = EXCLUDED.time_label, description = EXCLUDED.description,
  image_url = EXCLUDED.image_url, total_price = EXCLUDED.total_price, savings = EXCLUDED.savings;


-- ---------------------------------------------------------------------
-- 3. ROUTINE_ITEMS (productos por rutina)
-- ---------------------------------------------------------------------
-- Rutina Energía: Essential + Mental Balance
INSERT INTO flux.routine_items (routine_id, product_id, quantity, sort_order) VALUES
  ((SELECT id FROM flux.routines WHERE slug='rutina-energia'),    (SELECT id FROM flux.products WHERE slug='essential'), 1, 10),
  ((SELECT id FROM flux.routines WHERE slug='rutina-energia'),    (SELECT id FROM flux.products WHERE slug='mental'),    1, 20),
  ((SELECT id FROM flux.routines WHERE slug='rutina-activa'),     (SELECT id FROM flux.products WHERE slug='active'),    1, 10),
  ((SELECT id FROM flux.routines WHERE slug='rutina-activa'),     (SELECT id FROM flux.products WHERE slug='greens'),    1, 20),
  ((SELECT id FROM flux.routines WHERE slug='rutina-equilibrio'), (SELECT id FROM flux.products WHERE slug='women'),     1, 10),
  ((SELECT id FROM flux.routines WHERE slug='rutina-equilibrio'), (SELECT id FROM flux.products WHERE slug='digestive'), 1, 20)
ON CONFLICT DO NOTHING;


-- ---------------------------------------------------------------------
-- 4. TESTIMONIOS (los 15 reales)
-- ---------------------------------------------------------------------
INSERT INTO flux.testimonials (quote, author_name, author_meta, avatar_url, rating, approved, featured, sort_order) VALUES
  ('Lo sumé a la mañana y el cambio en mi energía fue lo primero que noté.',                'Camila R.',    'Essential · 4 meses de uso',       'assets/life/wellness-portrait.jpg', 5, TRUE, TRUE,  10),
  ('Me ordenó la rutina. Ahora sé qué tomar y en qué momento del día.',                     'Lucía B.',     'Rutina completa · 6 meses',        'assets/life/wellness-skincare.jpg', 5, TRUE, TRUE,  20),
  ('Mental Balance me acompaña en las semanas más cargadas de trabajo.',                    'Sofía M.',     'Mental Balance · 3 meses',         'assets/life/wellness-yoga.jpg',     5, TRUE, TRUE,  30),
  ('La presentación y la información clara fueron lo que me convenció.',                    'Ana P.',       'Women · 5 meses',                  'assets/life/wellness-hands.jpg',    5, TRUE, FALSE, 40),
  ('El colágeno me cambió la textura del cabello en menos de dos meses.',                   'Micaela V.',   'Colágeno Beauty · 2 meses',        'assets/life/wellness-skincare.jpg', 5, TRUE, FALSE, 50),
  ('Entreno mejor con el pre-work de FLUX, sin bajones ni palpitaciones.',                  'Rodrigo A.',   'Pre-Work · 5 semanas',             'assets/life/wellness-active.jpg',   5, TRUE, FALSE, 60),
  ('Duermo distinto desde que sumo el magnesio antes de acostarme.',                        'Valeria S.',   'Sleep + Calm · 3 meses',           'assets/life/wellness-portrait.jpg', 5, TRUE, FALSE, 70),
  ('Nunca tuve una marca de suplementos que se explique tan claro.',                        'Josefina C.',  'Multivitamínico · 6 meses',        'assets/life/wellness-hands.jpg',    5, TRUE, FALSE, 80),
  ('La atención por WhatsApp fue lo que definió mi primera compra.',                        'Belén M.',     'Essential + Women · 2 meses',      'assets/life/wellness-yoga.jpg',     5, TRUE, FALSE, 90),
  ('Los omega 3 sin regusto son una diferencia enorme, lo aprecio.',                        'Nicolás F.',   'Omega 3 · 4 meses',                'assets/life/wellness-active.jpg',   5, TRUE, FALSE, 100),
  ('Probé la spirulina y se nota más en el sistema inmune que otras marcas.',               'Andrea K.',    'Spirulina · 3 meses',              'assets/life/wellness-morning.jpg',  5, TRUE, FALSE, 110),
  ('La rutina de la noche me cambió el descanso. Cero pantallas antes.',                    'Paula H.',     'Rutina noche · 2 meses',           'assets/life/wellness-portrait.jpg', 5, TRUE, FALSE, 120),
  ('Fórmulas serias, sin promesas mágicas. Justo lo que buscaba.',                          'Gonzalo T.',   'Multivitamínico · 5 meses',        'assets/life/wellness-hands.jpg',    5, TRUE, FALSE, 130),
  ('Los probióticos me acompañaron durante todo el tratamiento antibiótico.',               'Luciana O.',   'Probióticos · 4 meses',            'assets/life/wellness-skincare.jpg', 5, TRUE, FALSE, 140),
  ('El envío llegó a Encarnación en 48 hs. Se agradece el detalle.',                        'Martín G.',    'Cliente reciente',                 'assets/life/wellness-active.jpg',   5, TRUE, FALSE, 150)
ON CONFLICT DO NOTHING;


-- ---------------------------------------------------------------------
-- 5. FAQ_CATEGORIES + FAQS (las 10 de la sección FAQs)
-- ---------------------------------------------------------------------
INSERT INTO flux.faq_categories (slug, name, sort_order, active) VALUES
  ('generales', 'Generales', 10, TRUE)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO flux.faqs (category_id, question, answer, sort_order, active) VALUES
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Cuánto tarda mi pedido?',                          'Los envíos dentro de Asunción llegan en 24 hs. A todo Paraguay entre 48 y 72 hs. Recibís seguimiento por WhatsApp.', 10, TRUE),
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Cómo elijo mi suplemento?',                        'Filtrá el catálogo por marca u objetivo (energía, foco, equilibrio, glow, digestión, salud femenina), o escribinos por WhatsApp si querés que te asesoremos.', 20, TRUE),
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Se pueden combinar varios FLUX?',                  'Sí. Las rutinas Mañana / Día / Noche están pensadas para combinarse. Si tenés dudas, escribinos por WhatsApp y te armamos una combinación personalizada.', 30, TRUE),
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Los suplementos reemplazan una comida?',           'No. Los suplementos acompañan tu alimentación y estilo de vida. No sustituyen consultas profesionales ni una dieta variada.', 40, TRUE),
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Tienen ingredientes de origen animal?',            'Depende de la fórmula. La mayoría de nuestras cápsulas son vegetales (aptas para veganos), pero algunas contienen colágeno bovino u omega de pescado. Cada ficha lo aclara.', 50, TRUE),
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Puedo tomar FLUX si estoy embarazada o amamantando?', 'Recomendamos consultar con tu profesional de la salud antes de empezar cualquier suplemento durante el embarazo o la lactancia.', 60, TRUE),
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Cuáles son los métodos de pago?',                  'Aceptamos VISA, Mastercard, Bancard, transferencia bancaria y efectivo contra entrega en el área metropolitana.', 70, TRUE),
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Puedo cambiar o devolver un producto?',            'Sí, dentro de los 7 días de recibido y siempre que el envase esté cerrado. Escribinos y coordinamos el cambio.', 80, TRUE),
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Dónde se fabrica FLUX?',                           'FLUX Nutrition se formula en Paraguay con el respaldo del grupo FIVA — más de 30 años en la industria farmacéutica local.', 90, TRUE),
  ((SELECT id FROM flux.faq_categories WHERE slug='generales'), '¿Puedo usar FLUX si estoy tomando medicamentos?',   'Algunos activos pueden interactuar con medicación. Siempre consultá con tu médico o farmacéutico antes de combinarlos.', 100, TRUE)
ON CONFLICT DO NOTHING;
