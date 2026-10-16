-- The caller's school and teacher RLS apply to both exact and typo matches.
create function public.search_school_teachers(p_school_id uuid,p_query text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path=''
set jit=off set statement_timeout='5s' as $$
declare normalized text;terms text;q tsquery;result jsonb;
begin
 if length(coalesce(p_query,''))>160 or p_offset is null or p_offset<0 or p_offset>100000 then
  raise exception 'Некорректные параметры поиска';
 end if;
 normalized:=public.catalog_normalize(p_query);
 select string_agg(quote_literal(token)||case when token~'^[0-9]+$' then '' else ':*' end,' & ')
 into terms from regexp_split_to_table(normalized,' +')token where token<>'';
 if terms is not null then q:=to_tsquery('simple',terms);end if;
 with school as materialized(select * from public.schools where id=p_school_id and archived_at is null),
 hits as materialized(
  select t.*,case when public.catalog_normalize(t.name)=normalized then 4 else 0 end+
   case when q is null then 0 else 2*ts_rank(t.staff_search_document,q) end as match_rank
  from public.teachers t join school s on s.id=t.school_id
  where q is null or t.staff_search_document@@q
  order by match_rank desc,t.name,t.id limit 21 offset p_offset
 )
 select coalesce(jsonb_agg(jsonb_build_object('kind','teacher','match_type','exact',
  'record',to_jsonb(h)-'match_rank'-'search_document'-'staff_search_document',
  'school',to_jsonb(s)-'search_document'-'catalog_search_document') order by h.match_rank desc,h.name,h.id),'[]'::jsonb)
 into result from hits h join school s on s.id=h.school_id;
 if jsonb_array_length(result)>0 or length(normalized)<4 or exists(
  select 1 from public.teachers t join public.schools s on s.id=t.school_id
  where s.id=p_school_id and s.archived_at is null and t.staff_search_document@@q
 )then return result;end if;
 -- Spelling fallback is limited to words in this school's visible roster.
 with school as materialized(select * from public.schools where id=p_school_id and archived_at is null),
 staff as materialized(
  select t.*,public.catalog_normalize(t.name||' '||coalesce(t.staff_subject,t.subject,'')) as word_text
  from public.teachers t join school s on s.id=t.school_id
 ),scored as(
  select t.id,min(m.best) as weakest,sum(m.best) as match_rank
  from staff t cross join lateral regexp_split_to_table(normalized,' +')token
  cross join lateral(
   select max(case when word=token or word like token||'%' then 1::real
    when token~'^[[:alpha:]]{4,32}$' and abs(length(word)-length(token))<=2
    then extensions.similarity(token,word) else 0::real end) as best
   from regexp_split_to_table(t.word_text,' +')word
  )m group by t.id
 ),page as(
  select t.*,r.match_rank from staff t join scored r on r.id=t.id where r.weakest>=0.4
  order by r.match_rank desc,t.name,t.id limit 21 offset p_offset
 )
 select coalesce(jsonb_agg(jsonb_build_object('kind','teacher','match_type','similar',
  'record',to_jsonb(h)-'word_text'-'match_rank'-'search_document'-'staff_search_document',
  'school',to_jsonb(s)-'search_document'-'catalog_search_document') order by h.match_rank desc,h.name,h.id),'[]'::jsonb)
 into result from page h join school s on s.id=h.school_id;
 return result;
end;$$;
revoke all on function public.search_school_teachers(uuid,text,integer) from public;
grant execute on function public.search_school_teachers(uuid,text,integer) to anon,authenticated;
