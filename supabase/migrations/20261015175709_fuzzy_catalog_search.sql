-- Prefix matches stay first; indexed typo matches fill the remaining page.
set lock_timeout='5s';
create extension if not exists pg_trgm with schema extensions;
create index teachers_staff_fuzzy_idx on public.teachers using gin
 (public.catalog_normalize(coalesce(name,'')||' '||coalesce(subject,'')||' '||coalesce(staff_subject,'')) extensions.gin_trgm_ops);
create index schools_catalog_fuzzy_idx on public.schools using gin
 (public.catalog_normalize(coalesce(name,'')||' '||coalesce(registry_name,'')||' '||coalesce(accreditation_name,'')||' '||coalesce(city,'')||' '||coalesce(address,'')) extensions.gin_trgm_ops) where archived_at is null;

create or replace function public.search_catalog(p_query text default '',p_kind text default 'all',p_region text default '',p_city text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions
set statement_timeout='5s' set pg_trgm.word_similarity_threshold='0.45' as $$
declare q tsquery;q_any tsquery;terms text;any_terms text;normalized text;result jsonb;fuzzy_result jsonb;exact_count bigint;
begin
 if length(coalesce(p_query,''))>160 or p_offset is null or p_offset<0 or p_offset>100000 or p_kind is null or p_kind not in('all','schools','teachers') then raise exception 'Некорректные параметры поиска';end if;
 normalized:=catalog_normalize(p_query);
 select string_agg(term,' & '),string_agg(term,' | ') into terms,any_terms
 from(select quote_literal(t)||case when t~'^[0-9]+$' then '' else ':*' end term from regexp_split_to_table(normalized,' +')t where length(t)>0)tokens;
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
  select t.id from teachers t where p_kind<>'schools' and t.staff_search_document@@q_any
  union
  select t.id from schools s join teachers t on t.school_id=s.id where p_kind<>'schools' and s.archived_at is null and s.catalog_search_document@@q_any and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
 ),exact_hits as materialized(
  select 'school' kind,s.id,s.id school_id,s.name sort_name,
   (case when catalog_normalize(s.name)=normalized then 4 when catalog_normalize(s.name) like normalized||'%' then 2 else 0 end)+2*ts_rank(to_tsvector('simple',catalog_normalize(s.name)),q)+ts_rank(s.catalog_search_document,q) rank
  from schools s where p_kind<>'teachers' and s.archived_at is null and s.catalog_search_document@@q and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
  union all
  select 'teacher',t.id,t.school_id,t.name,
   (case when catalog_normalize(t.name)=normalized then 4 when catalog_normalize(t.name) like normalized||'%' then 2 else 0 end)+2*ts_rank(t.staff_search_document,q)+ts_rank(t.staff_search_document||s.catalog_search_document,q)
  from teacher_candidates c join teachers t on t.id=c.id join schools s on s.id=t.school_id where s.archived_at is null and(t.staff_search_document||s.catalog_search_document)@@q and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
 ),page as(select * from exact_hits order by rank desc,sort_name,id limit 21 offset p_offset)
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'match_type','exact','record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.rank desc,h.sort_name,h.id),'[]'),(select count(*) from exact_hits)
 into result,exact_count from page h join schools s on s.id=h.school_id left join teachers t on h.kind='teacher' and t.id=h.id;
 if jsonb_array_length(result)=21 or length(normalized)<4 then return result;end if;

 with tokens as materialized(
  select term,to_tsquery('simple',quote_literal(term)||case when term~'^[0-9]+$' then '' else ':*' end) term_query
  from regexp_split_to_table(normalized,' +')term where length(term)>0
 ),school_candidates as materialized(
  select s.id from schools s where s.archived_at is null and s.catalog_search_document@@q_any and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
  union
  select s.id from tokens k join schools s on length(k.term)>=4 and k.term!~'^[0-9]+$' and catalog_normalize(coalesce(s.name,'')||' '||coalesce(s.registry_name,'')||' '||coalesce(s.accreditation_name,'')||' '||coalesce(s.city,'')||' '||coalesce(s.address,'')) OPERATOR(extensions.%>) k.term
  where s.archived_at is null and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
 ),teacher_candidates as materialized(
  select t.id from teachers t where p_kind<>'schools' and t.staff_search_document@@q_any
  union
  select t.id from tokens k join teachers t on length(k.term)>=4 and k.term!~'^[0-9]+$' and catalog_normalize(coalesce(t.name,'')||' '||coalesce(t.subject,'')||' '||coalesce(t.staff_subject,'')) OPERATOR(extensions.%>) k.term where p_kind<>'schools'
  union
  select t.id from school_candidates c join teachers t on t.school_id=c.id where p_kind<>'schools'
 ),candidates as materialized(
  select 'school' kind,s.id,s.id school_id,s.name sort_name,s.catalog_search_document document,
   catalog_normalize(coalesce(s.name,'')||' '||coalesce(s.registry_name,'')||' '||coalesce(s.accreditation_name,'')||' '||coalesce(s.city,'')||' '||coalesce(s.address,'')) search_text
  from school_candidates c join schools s on s.id=c.id where p_kind<>'teachers' and not s.catalog_search_document@@q
  union all
  select 'teacher',t.id,t.school_id,t.name,t.staff_search_document||s.catalog_search_document,
   catalog_normalize(coalesce(t.name,'')||' '||coalesce(t.subject,'')||' '||coalesce(t.staff_subject,'')||' '||coalesce(s.name,'')||' '||coalesce(s.registry_name,'')||' '||coalesce(s.accreditation_name,'')||' '||coalesce(s.city,'')||' '||coalesce(s.address,''))
  from teacher_candidates c join teachers t on t.id=c.id join schools s on s.id=t.school_id where s.archived_at is null and not(t.staff_search_document||s.catalog_search_document)@@q and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
 ),hits as materialized(
  select c.*,score.rank from candidates c cross join lateral(
   select avg(extensions.word_similarity(k.term,c.search_text)) rank,
    bool_and(c.document@@k.term_query or (length(k.term)>=4 and k.term!~'^[0-9]+$' and extensions.word_similarity(k.term,c.search_text)>=0.45)) matches from tokens k
  )score where score.matches order by score.rank desc,c.sort_name,c.id
  limit (21-jsonb_array_length(result)) offset greatest(0,p_offset-exact_count)
 )
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'match_type','similar','record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.rank desc,h.sort_name,h.id),'[]') into fuzzy_result from hits h join schools s on s.id=h.school_id left join teachers t on h.kind='teacher' and t.id=h.id;
 return result||fuzzy_result;
end;$$;
revoke all on function public.search_catalog(text,text,text,text,integer) from public;
grant execute on function public.search_catalog(text,text,text,text,integer) to anon,authenticated;
analyze public.schools;
analyze public.teachers;
