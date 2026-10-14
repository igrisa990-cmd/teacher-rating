begin;
alter table public.teachers add column staff_subject text,add column staff_identity_url text,add column staff_role text;
create table private.catalog_staff_stage(run_key text not null,school_ogrn text not null,name_key text not null,payload jsonb not null,primary key(run_key,school_ogrn,name_key));
create table private.staff_import_keys(school_id uuid not null references public.schools(id) on delete cascade,name_key text not null,teacher_id uuid not null references public.teachers(id) on delete cascade,source_url text not null,identity_url text not null,checked_at timestamptz not null,primary key(school_id,name_key));
create index staff_import_keys_teacher_idx on private.staff_import_keys(teacher_id);
alter table private.catalog_staff_stage enable row level security;alter table private.staff_import_keys enable row level security;revoke all on private.catalog_staff_stage,private.staff_import_keys from public,anon,authenticated;
create or replace function private.staff_name_key(value text) returns text language sql immutable security invoker set search_path='' as $$select btrim(regexp_replace(replace(lower(value),'ё','е'),'[^[:alnum:]]+',' ','g'));$$;
create or replace function private.apply_staff_snapshot(p_run text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare expected integer;actual integer;linked integer;inserted integer;refreshed integer;result jsonb;
begin
 perform pg_advisory_xact_lock(hashtext('catalog-staff-import'));
 select expected_rows into expected from private.catalog_import_runs where run_key=p_run for update;
 select count(*) into actual from private.catalog_staff_stage where run_key=p_run;
 if expected is null or expected<>actual or expected<1 then raise exception 'Incomplete staff snapshot: % / %',actual,expected;end if;
 if exists(select 1 from private.catalog_staff_stage where run_key=p_run and (school_ogrn!~'^[0-9]{13}$' or coalesce(length(payload->>'name'),0) not between 3 and 200 or coalesce(length(payload->>'subject'),0) not between 0 and 1000 or not(payload?'subject') or jsonb_typeof(payload->'subject')<>'string' or coalesce(payload->>'source_url','') !~ '^https?://[^/]+/' or coalesce(payload->>'identity_url','') !~ '^https?://[^/]+/' or coalesce(payload->>'identity_method','') not in('explicit_ogrn','exact_name_address','exact_name_locality_postcode'))) then raise exception 'Invalid staff source identity';end if;
 create temporary table if not exists staff_ready(school_id uuid,name_key text,p jsonb,primary key(school_id,name_key)) on commit drop;
 truncate pg_temp.staff_ready;
 insert into pg_temp.staff_ready select s.id,private.staff_name_key(st.payload->>'name'),st.payload from private.catalog_staff_stage st join public.schools s on s.organization_ogrn=st.school_ogrn and s.archived_at is null where st.run_key=p_run;
 with candidates as(select r.school_id,r.name_key,min(t.id::text)::uuid teacher_id,count(*) n from pg_temp.staff_ready r join public.teachers t on t.school_id=r.school_id and private.staff_name_key(t.name)=r.name_key group by r.school_id,r.name_key)
 insert into private.staff_import_keys(school_id,name_key,teacher_id,source_url,identity_url,checked_at) select c.school_id,c.name_key,c.teacher_id,r.p->>'source_url',r.p->>'identity_url',(r.p->>'checked_at')::timestamptz from candidates c join pg_temp.staff_ready r using(school_id,name_key) where c.n=1 on conflict(school_id,name_key) do nothing;
 get diagnostics linked=row_count;
 with added as(
 insert into public.teachers(name,subject,category,initials,school_id,source_type,source_url,verified_at,verification_status,verification_method,verification_checked_at,staff_subject,staff_identity_url,staff_role)
 select r.p->>'name',r.p->>'subject','other',left(r.p->>'name',1)||left(split_part(r.p->>'name',' ',2),1),r.school_id,'official',r.p->>'source_url',(r.p->>'checked_at')::timestamptz,'verified','official_website',(r.p->>'checked_at')::timestamptz,r.p->>'subject',r.p->>'identity_url',r.p->>'role'
 from pg_temp.staff_ready r where not exists(select 1 from private.staff_import_keys k where k.school_id=r.school_id and k.name_key=r.name_key) and not exists(select 1 from public.teachers t where t.school_id=r.school_id and private.staff_name_key(t.name)=r.name_key)
 returning id,school_id,name)
 insert into private.staff_import_keys(school_id,name_key,teacher_id,source_url,identity_url,checked_at) select a.school_id,r.name_key,a.id,r.p->>'source_url',r.p->>'identity_url',(r.p->>'checked_at')::timestamptz from added a join pg_temp.staff_ready r on r.school_id=a.school_id and r.name_key=private.staff_name_key(a.name);
 get diagnostics inserted=row_count;
 update public.teachers t set staff_subject=nullif(r.p->>'subject',''),staff_identity_url=r.p->>'identity_url',staff_role=r.p->>'role',source_url=r.p->>'source_url',verified_at=(r.p->>'checked_at')::timestamptz,verification_status='verified',verification_method='official_website',verification_checked_at=(r.p->>'checked_at')::timestamptz from private.staff_import_keys k join pg_temp.staff_ready r using(school_id,name_key) where t.id=k.teacher_id and (t.verification_checked_at is null or t.verification_checked_at<=(r.p->>'checked_at')::timestamptz);
 get diagnostics refreshed=row_count;
 update private.staff_import_keys k set source_url=r.p->>'source_url',identity_url=r.p->>'identity_url',checked_at=(r.p->>'checked_at')::timestamptz from pg_temp.staff_ready r where r.school_id=k.school_id and r.name_key=k.name_key and k.checked_at<=(r.p->>'checked_at')::timestamptz;
 with sites as(select distinct on(school_id) school_id,p from pg_temp.staff_ready order by school_id,(p->>'checked_at') desc)
 update public.schools s set source_url=r.p->>'school_website',verified_at=(r.p->>'checked_at')::timestamptz from sites r where s.id=r.school_id and s.source_url is null and r.p->>'school_website' ~ '^https?://[^/]+/';
 result=jsonb_build_object('snapshot_rows',actual,'inserted',inserted,'linked_existing',linked,'metadata_refreshed',refreshed,'unmatched_schools',actual-(select count(*) from pg_temp.staff_ready),'ambiguous_names',(select count(*) from pg_temp.staff_ready r where not exists(select 1 from private.staff_import_keys k where k.school_id=r.school_id and k.name_key=r.name_key)),'active_teachers',(select count(*) from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null));
 update private.catalog_import_runs set applied_at=now(),summary=result where run_key=p_run;
 return result;
end;$$;
revoke all on function private.staff_name_key(text),private.apply_staff_snapshot(text) from public,anon,authenticated;

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


create or replace function public.catalog_stats() returns jsonb language sql stable security invoker set search_path='' set statement_timeout='8s' as $$
 select jsonb_build_object('schools',(select count(*) from public.schools where archived_at is null),'teachers',(select count(*) from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null),'regions',coalesce((select jsonb_agg(to_jsonb(r)) from (select region,count(*)::integer as count from public.schools where archived_at is null group by region order by region)r),'[]'::jsonb),'sources',jsonb_build_object('licenses',(select count(*) from public.schools where archived_at is null and (registry_url is not null or registry_snapshot_url is not null)),'accreditation',(select count(*) from public.schools where archived_at is null and accreditation_url is not null),'map',(select count(*) from public.schools where archived_at is null and osm_id is not null)));
$$;
commit;
