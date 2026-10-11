-- Registry provenance does not confer trust on a school website or staff identities.
alter table public.schools
 add column registry_ogrn text check(registry_ogrn ~ '^[0-9]{13}$'),
 add column registry_name text,
 add column registry_url text check(registry_url ~ '^https://islod\.obrnadzor\.gov\.ru/view/[0-9]+$'),
 add column registry_checked_at timestamptz,
 add column registry_license text,
 add column registry_programs jsonb;
create unique index schools_registry_ogrn_idx on public.schools(registry_ogrn) where registry_ogrn is not null;
comment on column public.schools.registry_url is 'Organization license provenance; never an allowlisted school website for staff verification.';
