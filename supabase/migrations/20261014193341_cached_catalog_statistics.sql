-- Aggregate public counts are recomputed on catalog writes, not every page read.
create table catalog_search_internal.statistics_cache(singleton boolean primary key default true check(singleton),payload jsonb not null,updated_at timestamptz not null default now());
alter table catalog_search_internal.statistics_cache enable row level security;
revoke all on catalog_search_internal.statistics_cache from public,anon,authenticated;
create function catalog_search_internal.refresh_statistics() returns void language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtext('catalog-statistics-cache'));
 with counts as materialized(
  select region,count(*) n,count(*)filter(where registry_url is not null or registry_snapshot_url is not null) licensed,count(*)filter(where accreditation_url is not null) accredited,count(*)filter(where osm_id is not null) mapped
  from public.schools where archived_at is null group by region
 ),stats as(
  select jsonb_build_object('schools',coalesce(sum(n),0),'teachers',(select count(*) from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null),'regions',coalesce(jsonb_agg(jsonb_build_object('region',region,'count',n)order by region),'[]'),'sources',jsonb_build_object('licenses',coalesce(sum(licensed),0),'accreditation',coalesce(sum(accredited),0),'map',coalesce(sum(mapped),0))) payload from counts
 )insert into catalog_search_internal.statistics_cache(singleton,payload,updated_at)select true,payload,now()from stats on conflict(singleton)do update set payload=excluded.payload,updated_at=excluded.updated_at;
end;$$;
create function catalog_search_internal.lock_statistics_write()returns trigger language plpgsql security definer set search_path='' as $$begin perform pg_advisory_xact_lock(hashtext('catalog-statistics-cache'));return null;end;$$;
create function catalog_search_internal.update_statistics_after_write()returns trigger language plpgsql security definer set search_path='' as $$begin perform catalog_search_internal.refresh_statistics();return null;end;$$;
revoke all on function catalog_search_internal.refresh_statistics(),catalog_search_internal.lock_statistics_write(),catalog_search_internal.update_statistics_after_write()from public,anon,authenticated;
-- Acquire the same lock before writes, so concurrent refreshes see committed changes.
create trigger catalog_statistics_school_lock before insert or delete or update of archived_at,region,registry_url,registry_snapshot_url,accreditation_url,osm_id on public.schools for each statement execute function catalog_search_internal.lock_statistics_write();
create trigger catalog_statistics_school_refresh after insert or delete or update of archived_at,region,registry_url,registry_snapshot_url,accreditation_url,osm_id on public.schools for each statement execute function catalog_search_internal.update_statistics_after_write();
create trigger catalog_statistics_teacher_lock before insert or delete or update of school_id on public.teachers for each statement execute function catalog_search_internal.lock_statistics_write();
create trigger catalog_statistics_teacher_refresh after insert or delete or update of school_id on public.teachers for each statement execute function catalog_search_internal.update_statistics_after_write();
create or replace function catalog_search_internal.statistics()returns jsonb language sql stable security definer set search_path='' as $$select payload from catalog_search_internal.statistics_cache where singleton;$$;
select catalog_search_internal.refresh_statistics();
