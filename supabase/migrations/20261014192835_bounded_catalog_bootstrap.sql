-- Public aggregate counts contain no individual records. Compute them once
-- per call, without repeating caller RLS checks for every counted staff row.
create function catalog_search_internal.statistics() returns jsonb language sql stable security definer set search_path='' as $$
 with counts as materialized(
  select region,count(*) n,count(*)filter(where registry_url is not null or registry_snapshot_url is not null) licensed,count(*)filter(where accreditation_url is not null) accredited,count(*)filter(where osm_id is not null) mapped
  from public.schools where archived_at is null group by region
 )select jsonb_build_object('schools',coalesce(sum(n),0),'teachers',(select count(*) from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null),'regions',coalesce(jsonb_agg(jsonb_build_object('region',region,'count',n)order by region),'[]'),'sources',jsonb_build_object('licenses',coalesce(sum(licensed),0),'accreditation',coalesce(sum(accredited),0),'map',coalesce(sum(mapped),0)))from counts;
$$;
create index teachers_bootstrap_rating_idx on public.teachers(rating desc,id) include(school_id);
create function catalog_search_internal.bootstrap_ids(p_region text) returns table(kind text,id uuid,school_id uuid)
language sql stable security definer set search_path='' rows 320 as $$
 (select 'school'::text,s.id,s.id from public.schools s where s.archived_at is null and(nullif(nullif(p_region,''),'all') is null or s.region=p_region)order by s.name,s.id limit 200)
 union all
 (select 'teacher',t.id,t.school_id from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null and(nullif(nullif(p_region,''),'all') is null or s.region=p_region)order by t.rating desc,t.id limit 120);
$$;
revoke all on function catalog_search_internal.statistics(),catalog_search_internal.bootstrap_ids(text) from public;
grant execute on function catalog_search_internal.statistics(),catalog_search_internal.bootstrap_ids(text) to anon,authenticated;
create or replace function public.catalog_stats() returns jsonb language sql stable security invoker set search_path='' set statement_timeout='8s' as $$select catalog_search_internal.statistics();$$;
create or replace function public.catalog_bootstrap(p_region text default '') returns jsonb language sql stable security invoker set search_path='' set statement_timeout='8s' as $$
 with picked as materialized(select * from catalog_search_internal.bootstrap_ids(p_region)),
 allowed_teachers as materialized(select t.* from picked p join public.teachers t on p.kind='teacher' and t.id=p.id join public.schools s on s.id=t.school_id where s.archived_at is null),
 school_ids as(select id from picked where kind='school' union select school_id from allowed_teachers)
 select jsonb_build_object('schools',coalesce((select jsonb_agg(to_jsonb(s)-'search_document'-'catalog_search_document' order by s.name,s.id)from school_ids i join public.schools s on s.id=i.id where s.archived_at is null),'[]'),
 'teachers',coalesce((select jsonb_agg(to_jsonb(t)-'search_document'-'staff_search_document' order by t.rating desc,t.id)from allowed_teachers t),'[]'),'stats',public.catalog_stats());
$$;
revoke all on function public.catalog_stats(),public.catalog_bootstrap(text) from public;
grant execute on function public.catalog_stats(),public.catalog_bootstrap(text) to anon,authenticated;
