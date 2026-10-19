-- Hydrate the bounded ID set through primary-key lookups. OFFSET 0 keeps the
-- planner from expanding a cached function plan into scans of every wide row.
-- Candidate selection, caller RLS, statistics and the public response stay intact.
create or replace function public.catalog_bootstrap(p_region text default '')
returns jsonb language sql stable security invoker
set search_path='' set jit=off set plan_cache_mode=force_custom_plan set statement_timeout='8s' as $$
 with picked as materialized(select * from catalog_search_internal.bootstrap_ids(p_region)),
 allowed_teachers as materialized(
  select t.* from picked p
  join lateral(select * from public.teachers t0 where p.kind='teacher' and t0.id=p.id offset 0)t on true
  join lateral(select id from public.schools s0 where s0.id=t.school_id and s0.archived_at is null offset 0)s on true
 ),
 school_ids as(select id from picked where kind='school' union select school_id from allowed_teachers)
 select jsonb_build_object(
  'schools',coalesce((select jsonb_agg(to_jsonb(s)-'search_document'-'catalog_search_document' order by s.name,s.id)
   from school_ids i join lateral(select * from public.schools s0 where s0.id=i.id and s0.archived_at is null offset 0)s on true),'[]'),
  'teachers',coalesce((select jsonb_agg(to_jsonb(t)-'search_document'-'staff_search_document' order by t.rating desc,t.id)from allowed_teachers t),'[]'),
  'stats',public.catalog_stats());
$$;
revoke all on function public.catalog_bootstrap(text) from public;
grant execute on function public.catalog_bootstrap(text) to anon,authenticated;
