# Neura · RLS Templates

Plantillas oficiales para configurar Row Level Security en proyectos Supabase de Neura.

## Archivos

- **`00-neura-security-bootstrap.sql`** — Setup global. Se corre **una sola vez** por instancia Supabase.
- **`01-tenant-rls-template.sql`** — Plantilla por tenant. Se copia, se hace find-replace de los placeholders, y se corre por cada cliente.

## Orden de aplicación

```
Instancia Supabase (proyecto)
│
├── 1. Correr 00-neura-security-bootstrap.sql   ⚠️ UNA SOLA VEZ
│      ├── crea schema `private`
│      ├── revoke defaults en `private`
│      └── cierra funciones existentes en `private`
│      NO re-correr después de instalar tenants: stripearía
│      el EXECUTE de is_<tenant>_admin() ya instaladas.
│
├── 2. Dashboard → Data API → Exposed schemas:
│      ├── agregar el schema del tenant (ej. `flux`)
│      └── NO agregar `private`
│
└── 3. Correr 01-tenant-rls-template.sql (una vez por tenant, re-runnable)
       │
       ├── previamente: find-replace de placeholders
       │      {{TENANT}}       → flux
       │      {{TENANT_ADMIN}} → is_flux_admin
       │      {{BUCKET}}       → flux-product-images   (tenant-prefixed!)
       │
       ├── completar la lista `tables` en la sección 8
       │   con las tablas públicas del tenant
       │
       └── completar los GRANT SELECT / INSERT / UPDATE / DELETE
           en la sección 5 con las tablas públicas
```

## Placeholders a reemplazar

| Placeholder | Ejemplo | Uso |
|---|---|---|
| `{{TENANT}}` | `flux` | Nombre del schema del tenant |
| `{{TENANT_ADMIN}}` | `is_flux_admin` | Nombre de la función admin en `private` |
| `{{BUCKET}}` | `flux-product-images` | Bucket público del tenant — **debe ser globalmente único** (namespace: `<tenant>-<uso>`). `storage.objects` es una tabla compartida por toda la instancia. |

## Grupos de tablas del tenant

Cada tabla del tenant cae en uno de estos 3 grupos. Completar los arrays en el template (`ARRAY['...','...']`) según corresponda.

| Grupo | Anon | Auth normal | Admin | Ejemplo |
|---|---|---|---|---|
| **PUBLIC_TABLES** | SELECT filtrado (`active IS TRUE`, hijos gateados por padre) | igual que anon | CRUD completo | `brands`, `categories`, `products`, `ingredients`, `testimonials` |
| **ADMIN_CRUD_TABLES** | nada | nada | CRUD completo | `orders`, `customers`, `payments`, `settings` |
| **ADMIN_READONLY_TABLES** | nada | nada | solo SELECT (escrituras vía backend/service_role) | `admin_users`, `audit_log` |

El template ya trae fijo el grupo READONLY (`admin_users` + `audit_log`) porque son el estándar Neura. Los otros dos grupos se completan por tenant.

## Modelo de seguridad

```
anon
  → SELECT en tablas públicas donde active/approved = TRUE
  → sin escrituras

authenticated (no admin)
  → mismos permisos que anon
  → sin acceso administrativo

authenticated + admin (fila en {{TENANT}}.admin_users con user_id=auth.uid() y active=TRUE)
  → CRUD completo en tablas públicas del tenant
  → SELECT (solo lectura) en admin_users y audit_log

backend / service_role
  → gestión sensible: crear admins, insertar audit_log, etc.
```

## Requisitos por tenant

Cada tenant debe tener en su schema:

- Tabla `{{TENANT}}.admin_users` con columnas mínimas: `id`, `email`, `active`, `user_id UUID REFERENCES auth.users(id)`.
- Tabla `{{TENANT}}.audit_log` (aunque esté vacía — el pack asume que existe).

## Verificación post-instalación

El pack tenant termina con 8 SECURITY CHECKS. Los outputs esperados están documentados inline. En particular:

- `has_table_privilege('authenticated', '{{TENANT}}.admin_users', 'INSERT')` → `false`
- `has_table_privilege('authenticated', '{{TENANT}}.audit_log', 'INSERT')` → `false`
- Bucket `public = t`
- 0 tablas del tenant sin RLS
- 0 funciones ejecutables por anon
- Cada view normal (relkind='v') del schema con `security_invoker = true`
- Materialized views (relkind='m') listadas para revisión manual — no soportan `security_invoker`, controlar acceso con GRANTs

## Operaciones sensibles (fuera del panel)

- **Crear un admin**: Dashboard → Authentication → Users (crear auth user) + INSERT en `{{TENANT}}.admin_users` vía SQL Editor (usa service_role).
- **Insertar audit_log**: trigger `SECURITY DEFINER` en las tablas auditadas, o backend con service_role.
- **Rotación de admin**: `UPDATE {{TENANT}}.admin_users SET active=FALSE WHERE user_id=...` vía SQL Editor.
