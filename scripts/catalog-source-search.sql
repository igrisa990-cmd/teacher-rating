
alter table public.schools add column catalog_search_document tsvector generated always as(to_tsvector('simple'::regconfig,replace(lower(coalesce(name,'')||' '||coalesce(registry_name,'')||' '||coalesce(accreditation_name,'')||' '||coalesce(city,'')||' '||coalesce(address,'')||' '||coalesce(region,'')),'ё','е'))) stored;
create index schools_catalog_search_idx on public.schools using gin(catalog_search_document) where archived_at is null;
alter table public.teachers add column staff_search_document tsvector generated always as(to_tsvector('simple'::regconfig,replace(lower(coalesce(name,'')||' '||coalesce(staff_subject,subject,'')),'ё','е'))) stored;
create index teachers_staff_search_idx on public.teachers using gin(staff_search_document);
CREATE OR REPLACE FUNCTION public.search_catalog(p_query text DEFAULT ''::text, p_kind text DEFAULT 'all'::text, p_region text DEFAULT ''::text, p_city text DEFAULT ''::text, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
 SET statement_timeout TO '5s'
AS $function$
declare q tsquery;terms text;result jsonb;
begin
 if length(coalesce(p_query,''))>160 or p_offset<0 or p_offset>100000 or p_kind not in('all','schools','teachers') then raise exception 'Некорректные параметры поиска';end if;
 select string_agg(quote_literal(t)||case when t~'^[0-9]+$' then '' else ':*' end,' & ') into terms from regexp_split_to_table(catalog_normalize(p_query),' +') t where length(t)>0;
 if terms is not null then q:=to_tsquery('simple',terms);end if;
 select coalesce(jsonb_agg(to_jsonb(r)),'[]') into result from (
 select kind,record,school from (
 select 'school' as kind,to_jsonb(s)-'search_document'-'catalog_search_document' as record,null::jsonb as school,s.name as sort_name,s.id as sort_id,
 case when q is null then 0 else 2*ts_rank(to_tsvector('simple',replace(lower(s.name),'ё','е')),q)+ts_rank(s.catalog_search_document,q) end as rank
 from schools s where s.archived_at is null and p_kind<>'teachers' and (coalesce(p_region,'')='' or s.region=p_region) and (coalesce(p_city,'')='' or s.city=p_city) and (q is null or s.catalog_search_document@@q)
 union all
 select 'teacher',to_jsonb(t)-'search_document'-'staff_search_document',to_jsonb(s)-'search_document'-'catalog_search_document',t.name,t.id,
 case when q is null then 0 else 2*ts_rank(t.staff_search_document,q)+ts_rank(t.staff_search_document||s.catalog_search_document,q) end
 from teachers t join schools s on s.id=t.school_id where s.archived_at is null and p_kind<>'schools' and (coalesce(p_region,'')='' or s.region=p_region) and (coalesce(p_city,'')='' or s.city=p_city) and (q is null or (t.staff_search_document||s.catalog_search_document)@@q)
 ) hits order by rank desc,sort_name,sort_id limit 21 offset p_offset
 ) r;
 return result;
end;$function$
;
revoke all on function public.search_catalog(text,text,text,text,integer) from public;grant execute on function public.search_catalog(text,text,text,text,integer) to anon,authenticated;

