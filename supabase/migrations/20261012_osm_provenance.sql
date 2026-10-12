begin;
alter table public.schools add column osm_id text check(osm_id ~ '^(node|way|relation)/[0-9]+$'),add column osm_lat double precision check(osm_lat between -90 and 90),add column osm_lon double precision check(osm_lon between -180 and 180),add column osm_checked_at timestamptz;
create unique index schools_osm_id_unique on public.schools(osm_id) where osm_id is not null;
commit;
