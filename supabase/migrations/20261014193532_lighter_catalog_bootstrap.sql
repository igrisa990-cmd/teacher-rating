-- The full catalog is searched remotely and profiles load by ID. Start small.
create or replace function catalog_search_internal.bootstrap_ids(p_region text) returns table(kind text,id uuid,school_id uuid)
language sql stable security definer set search_path='' rows 120 as $$
 (select 'school'::text,s.id,s.id from public.schools s where s.archived_at is null and(nullif(nullif(p_region,''),'all') is null or s.region=p_region)order by s.name,s.id limit 80)
 union all
 (select 'teacher',t.id,t.school_id from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null and(nullif(nullif(p_region,''),'all') is null or s.region=p_region)order by t.rating desc,t.id limit 40);
$$;
