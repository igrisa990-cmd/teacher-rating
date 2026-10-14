-- Restrictive staff RLS checks only active school IDs; keep that set small to read.
create index schools_active_id_idx on public.schools(id) where archived_at is null;
create or replace function public.search_catalog(p_query text default '',p_kind text default 'all',p_region text default '',p_city text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path='public' set statement_timeout='5s' as $$
declare q tsquery;q_any tsquery;terms text;any_terms text;result jsonb;
begin
 if length(coalesce(p_query,''))>160 or p_offset<0 or p_offset>100000 or p_kind not in('all','schools','teachers') then raise exception 'Некорректные параметры поиска';end if;
 select string_agg(term,' & '),string_agg(term,' | ') into terms,any_terms from(select quote_literal(t)||case when t~'^[0-9]+$' then '' else ':*' end term from regexp_split_to_table(catalog_normalize(p_query),' +')t where length(t)>0)tokens;
 if terms is null then
  with hits as materialized(
   select * from(
    select 'school' kind,s.id,s.id school_id,s.name sort_name from schools s where s.archived_at is null and p_kind<>'teachers' and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
    union all
    select 'teacher',t.id,t.school_id,t.name from teachers t join schools s on s.id=t.school_id where s.archived_at is null and p_kind<>'schools' and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
   )r order by sort_name,id limit 21 offset p_offset
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.sort_name,h.id),'[]') into result from hits h join schools s on s.id=h.school_id left join teachers t on h.kind='teacher' and t.id=h.id;
  return result;
 end if;
 q:=to_tsquery('simple',terms);q_any:=to_tsquery('simple',any_terms);
 with teacher_candidates as materialized(
  -- Any matching term is a necessary precondition for the final combined match.
  -- Each branch can use its own GIN index, including mixed teacher/school queries.
  select t.id from teachers t where p_kind<>'schools' and t.staff_search_document@@q_any
  union
  select t.id from schools s join teachers t on t.school_id=s.id where p_kind<>'schools' and s.archived_at is null and s.catalog_search_document@@q_any and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
 ),hits as materialized(
  select * from(
   select 'school' kind,s.id,s.id school_id,s.name sort_name,2*ts_rank(to_tsvector('simple',replace(lower(s.name),'ё','е')),q)+ts_rank(s.catalog_search_document,q) rank
   from schools s where p_kind<>'teachers' and s.archived_at is null and s.catalog_search_document@@q and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
   union all
   select 'teacher',t.id,t.school_id,t.name,2*ts_rank(t.staff_search_document,q)+ts_rank(t.staff_search_document||s.catalog_search_document,q)
   from teacher_candidates c join teachers t on t.id=c.id join schools s on s.id=t.school_id where s.archived_at is null and(t.staff_search_document||s.catalog_search_document)@@q and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
  )r order by rank desc,sort_name,id limit 21 offset p_offset
 )
 -- Build public JSON only for the requested page, after ranking and pagination.
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.rank desc,h.sort_name,h.id),'[]') into result from hits h join schools s on s.id=h.school_id left join teachers t on h.kind='teacher' and t.id=h.id;
 return result;
end;$$;
revoke all on function public.search_catalog(text,text,text,text,integer) from public;
grant execute on function public.search_catalog(text,text,text,text,integer) to anon,authenticated;
analyze public.schools;
analyze public.teachers;
