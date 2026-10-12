begin;
alter table public.schools add column search_document tsvector generated always as(to_tsvector('simple'::regconfig,replace(lower(coalesce(name,'')||' '||coalesce(city,'')||' '||coalesce(address,'')||' '||coalesce(region,'')),'ё','е'))) stored;
create index schools_search_document_idx on public.schools using gin(search_document) where archived_at is null;
create index schools_active_region_city_idx on public.schools(region,city,id) where archived_at is null;
alter table public.teachers add column search_document tsvector generated always as(to_tsvector('simple'::regconfig,replace(lower(coalesce(name,'')||' '||coalesce(subject,'')),'ё','е'))) stored;
create index teachers_search_document_idx on public.teachers using gin(search_document);
create or replace function public.search_catalog(p_query text default '',p_kind text default 'all',p_region text default '',p_city text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path=public set statement_timeout='5s' as $$
declare q tsquery;terms text;result jsonb;
begin
 if length(coalesce(p_query,''))>160 or p_offset<0 or p_offset>100000 or p_kind not in('all','schools','teachers') then raise exception 'Некорректные параметры поиска';end if;
 select string_agg(quote_literal(t)||':*',' & ') into terms from regexp_split_to_table(catalog_normalize(p_query),' +') t where length(t)>0;
 if terms is not null then q:=to_tsquery('simple',terms);end if;
 select coalesce(jsonb_agg(to_jsonb(r)),'[]') into result from (
 select kind,record,school from (
 select 'school' as kind,to_jsonb(s)-'search_document' as record,null::jsonb as school,s.name as sort_name,s.id as sort_id,
 case when q is null then 0 else ts_rank(s.search_document,q) end as rank
 from schools s where s.archived_at is null and p_kind<>'teachers' and (coalesce(p_region,'')='' or s.region=p_region) and (coalesce(p_city,'')='' or s.city=p_city) and (q is null or s.search_document@@q)
 union all
 select 'teacher',to_jsonb(t)-'search_document',to_jsonb(s)-'search_document',t.name,t.id,
 case when q is null then 0 else ts_rank(t.search_document||s.search_document,q) end
 from teachers t join schools s on s.id=t.school_id where s.archived_at is null and p_kind<>'schools' and (coalesce(p_region,'')='' or s.region=p_region) and (coalesce(p_city,'')='' or s.city=p_city) and (q is null or (t.search_document||s.search_document)@@q)
 ) hits order by rank desc,sort_name,sort_id limit 21 offset p_offset
 ) r;
 return result;
end;$$;
revoke all on function public.search_catalog(text,text,text,text,integer) from public;
grant execute on function public.search_catalog(text,text,text,text,integer) to anon,authenticated;
create or replace function public.catalog_places(p_region text default '') returns table(region text,city text) language sql stable security invoker set search_path=public as $$select distinct s.region,s.city from schools s where archived_at is null and (coalesce(p_region,'')='' or s.region=p_region) order by s.region,s.city;$$;
revoke all on function public.catalog_places(text) from public;
grant execute on function public.catalog_places(text) to anon,authenticated;
commit;
