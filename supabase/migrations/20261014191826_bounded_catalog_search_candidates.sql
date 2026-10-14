-- RLS security barriers prevent full-text predicates from using GIN before
-- the per-row active-school check. A narrowly scoped helper returns at most
-- 21 public IDs. The public wrapper still reads every record under caller RLS.
create schema catalog_search_internal;
revoke all on schema catalog_search_internal from public;
grant usage on schema catalog_search_internal to anon,authenticated;
create function catalog_search_internal.candidates(p_query text,p_kind text,p_region text,p_city text,p_offset integer)
returns table(kind text,id uuid,school_id uuid,sort_name text,rank real)
language plpgsql stable security definer set search_path='' set statement_timeout='5s' as $$
declare q tsquery;q_any tsquery;terms text;any_terms text;
begin
 if length(coalesce(p_query,''))>160 or p_offset is null or p_offset<0 or p_offset>100000 or p_kind is null or p_kind not in('all','schools','teachers') then raise exception 'Некорректные параметры поиска';end if;
 select string_agg(term,' & '),string_agg(term,' | ') into terms,any_terms from(select quote_literal(t)||case when t~'^[0-9]+$' then '' else ':*' end term from regexp_split_to_table(public.catalog_normalize(p_query),' +')t where length(t)>0)tokens;
 if terms is null then
  return query select h.* from(
   select 'school'::text kind,s.id,s.id school_id,s.name sort_name,0::real rank from public.schools s where s.archived_at is null and p_kind<>'teachers' and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
   union all
   select 'teacher',t.id,t.school_id,t.name,0::real from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null and p_kind<>'schools' and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
  )h order by h.sort_name,h.id limit 21 offset p_offset;
  return;
 end if;
 q:=to_tsquery('simple',terms);q_any:=to_tsquery('simple',any_terms);
 return query with teacher_ids as materialized(
  select t.id from public.teachers t where p_kind<>'schools' and t.staff_search_document@@q_any
  union
  select t.id from public.schools s join public.teachers t on t.school_id=s.id where p_kind<>'schools' and s.archived_at is null and s.catalog_search_document@@q_any and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
 )select h.* from(
  select 'school'::text kind,s.id,s.id school_id,s.name sort_name,2*ts_rank(to_tsvector('simple',replace(lower(s.name),'ё','е')),q)+ts_rank(s.catalog_search_document,q) rank
  from public.schools s where p_kind<>'teachers' and s.archived_at is null and s.catalog_search_document@@q and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
  union all
  select 'teacher',t.id,t.school_id,t.name,2*ts_rank(t.staff_search_document,q)+ts_rank(t.staff_search_document||s.catalog_search_document,q)
  from teacher_ids c join public.teachers t on t.id=c.id join public.schools s on s.id=t.school_id where s.archived_at is null and(t.staff_search_document||s.catalog_search_document)@@q and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
 )h order by h.rank desc,h.sort_name,h.id limit 21 offset p_offset;
end;$$;
revoke all on function catalog_search_internal.candidates(text,text,text,text,integer) from public;
grant execute on function catalog_search_internal.candidates(text,text,text,text,integer) to anon,authenticated;
create or replace function public.search_catalog(p_query text default '',p_kind text default 'all',p_region text default '',p_city text default '',p_offset integer default 0)
returns jsonb language sql stable security invoker set search_path='' set statement_timeout='5s' as $$
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.rank desc,h.sort_name,h.id),'[]')
 from catalog_search_internal.candidates(p_query,p_kind,p_region,p_city,p_offset)h
 join public.schools s on s.id=h.school_id
 left join public.teachers t on h.kind='teacher' and t.id=h.id
 where s.archived_at is null and(h.kind='school' or t.id is not null);
$$;
revoke all on function public.search_catalog(text,text,text,text,integer) from public;
grant execute on function public.search_catalog(text,text,text,text,integer) to anon,authenticated;
