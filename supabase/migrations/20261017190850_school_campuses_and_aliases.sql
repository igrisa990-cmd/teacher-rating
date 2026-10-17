-- Organizations remain the owner of teachers and reviews; campuses are separately sourced locations.
create table public.school_campuses(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id) on delete cascade,
 source_key text not null check(source_key~'^[a-f0-9]{64}$'),
 name text not null check(length(name) between 2 and 300),
 kind text not null check(kind in('school','branch','preschool','education_place')),
 address text not null check(length(address) between 8 and 1000),
 city text,region text,aliases text[] not null default '{}',
 source_url text not null check(source_url~'^https?://[^/]+/'),
 identity_url text not null check(identity_url~'^https?://[^/]+/'),
 identity_method text not null check(identity_method in('official_organization_api','official_license_record_link','explicit_ogrn','exact_name_address','exact_name_locality_postcode')),
 identity_sha256 text not null check(identity_sha256~'^[a-f0-9]{64}$'),
 source_sha256 text not null check(source_sha256~'^[a-f0-9]{64}$'),
 verified_at timestamptz not null,
 unique(school_id,source_key)
);
create index school_campuses_region_city_idx on public.school_campuses(region,city,school_id);
alter table public.school_campuses enable row level security;
create policy campus_visible_school on public.school_campuses for select to anon,authenticated
 using(exists(select 1 from public.schools s where s.id=school_id and s.archived_at is null));
revoke all on public.school_campuses from public,anon,authenticated;
grant select on public.school_campuses to anon,authenticated;
grant all on public.school_campuses to service_role;

-- Empty duplicate profiles retain their IDs and source data. Public links resolve to the reviewed organization.
create table public.school_profile_aliases(
 alias_school_id uuid primary key references public.schools(id) on delete cascade,
 school_id uuid not null references public.schools(id) on delete cascade,
 source_url text not null check(source_url~'^https?://[^/]+/'),
 source_sha256 text not null check(source_sha256~'^[a-f0-9]{64}$'),
 verified_at timestamptz not null,
 check(alias_school_id<>school_id)
);
create index school_profile_aliases_school_idx on public.school_profile_aliases(school_id);
alter table public.school_profile_aliases enable row level security;
create policy alias_visible_school on public.school_profile_aliases for select to anon,authenticated
 using(exists(select 1 from public.schools s where s.id=school_id and s.archived_at is null));
revoke all on public.school_profile_aliases from public,anon,authenticated;
grant select on public.school_profile_aliases to anon,authenticated;
grant all on public.school_profile_aliases to service_role;

-- Public, admin-maintained summaries keep normal search/profile requests bounded.
alter table public.schools add column campus_summary jsonb not null default '[]'::jsonb check(jsonb_typeof(campus_summary)='array'),
 add column campus_search_text text not null default '',
 add column campus_regions text[] not null default '{}';
alter table catalog_spelling.school_documents add column campus_regions text[] not null default '{}';

-- This trigger still copies only an already-authorized NEW source row. No additional privileged reads.
create or replace function catalog_spelling.sync_school_document() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_TABLE_SCHEMA<>'public' or TG_TABLE_NAME<>'schools' then raise exception 'Unsupported search source';end if;
 if auth.uid() is null and session_user not in('postgres','supabase_admin','service_role') and coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Authorized catalog write required';end if;
 if TG_OP='DELETE' then delete from catalog_spelling.school_documents where id=OLD.id;return null;end if;
 if NEW.archived_at is not null then delete from catalog_spelling.school_documents where id=NEW.id;return null;end if;
 insert into catalog_spelling.school_documents(id,name,name_key,name_document,region,city,catalog_search_document,campus_regions)
 values(NEW.id,NEW.name,public.catalog_normalize(NEW.name),pg_catalog.strip(pg_catalog.to_tsvector('simple',public.catalog_normalize(NEW.name))),NEW.region,NEW.city,pg_catalog.strip(NEW.catalog_search_document||pg_catalog.to_tsvector('simple',public.catalog_normalize(NEW.campus_search_text))),NEW.campus_regions)
 on conflict(id) do update set name=excluded.name,name_key=excluded.name_key,name_document=excluded.name_document,region=excluded.region,city=excluded.city,catalog_search_document=excluded.catalog_search_document,campus_regions=excluded.campus_regions;
 return null;
end;$$;
revoke all on function catalog_spelling.sync_school_document() from public,anon,authenticated;
drop trigger schools_sync_search_document on public.schools;
create trigger schools_sync_search_document after insert or delete or update of name,city,address,region,registry_name,accreditation_name,archived_at,campus_search_text,campus_regions on public.schools for each row execute function catalog_spelling.sync_school_document();

-- The importer explicitly calls this for changed organizations; no public write capability is added.
create function private.refresh_school_campus_summaries(p_ids uuid[]) returns integer language plpgsql security invoker set search_path='' as $$
declare changed integer;
begin
 if cardinality(p_ids)>5000 then raise exception 'Bounded campus refresh required';end if;
 update public.schools s set
 campus_summary=coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'kind',c.kind,'address',c.address,'city',c.city,'region',c.region,'source_url',c.source_url,'verified_at',c.verified_at,'aliases',c.aliases) order by c.kind,c.name,c.address,c.id) from public.school_campuses c where c.school_id=s.id),'[]'::jsonb),
 campus_search_text=coalesce((select string_agg(c.name||' '||c.address||' '||coalesce(c.city,'')||' '||coalesce(c.region,'')||' '||array_to_string(c.aliases,' '),' ') from public.school_campuses c where c.school_id=s.id),''),
 campus_regions=coalesce((select array_agg(distinct c.region) filter(where c.region is not null) from public.school_campuses c where c.school_id=s.id),'{}')
 where s.id=any(p_ids);
 get diagnostics changed=row_count;return changed;
end;$$;
revoke all on function private.refresh_school_campus_summaries(uuid[]) from public,anon,authenticated;

-- Search also respects explicitly published campus regions, with the same caller RLS and request bounds.
-- Ordinary matches do not initialize or tune the optional typo extension.
-- Prefer closer spelling within the existing RLS-protected fuzzy candidates.
create or replace function public.search_catalog(p_query text default '',p_kind text default 'all',p_region text default '',p_city text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions
set jit=off set plan_cache_mode=force_custom_plan set statement_timeout='8s' as $$
declare q tsquery;q_any tsquery;terms text;any_terms text;normalized text;result jsonb;fuzzy_result jsonb;exact_count bigint;exact_feasible boolean:=true;exact_own_strict boolean;exact_own_any boolean;token text;alternatives text;expanded text;expanded_any text;q_fuzzy tsquery;q_fuzzy_any tsquery;
begin
 if length(coalesce(p_query,''))>160 or p_offset is null or p_offset<0 or p_offset>100000 or p_kind is null or p_kind not in('all','schools','teachers') then raise exception 'Некорректные параметры поиска';end if;
 normalized:=catalog_normalize(p_query);
 select string_agg(term,' & '),string_agg(term,' | ') into terms,any_terms
 from(select quote_literal(t)||case when t~'^[0-9]+$' then '' else ':*' end term from regexp_split_to_table(normalized,' +')t where length(t)>0)tokens;
 if terms is null then
  with hits as materialized(
   select * from(
    select 'school' kind,s.id,s.id school_id,s.name sort_name from schools s where s.archived_at is null and p_kind<>'teachers' and(coalesce(p_region,'')='' or s.region=p_region or p_region=any(s.campus_regions))and(coalesce(p_city,'')='' or s.city=p_city)
    union all
    select 'teacher',t.id,t.school_id,t.name from teachers t join schools s on s.id=t.school_id where s.archived_at is null and p_kind<>'schools' and(coalesce(p_region,'')='' or s.region=p_region or p_region=any(s.campus_regions))and(coalesce(p_city,'')='' or s.city=p_city)
   )r order by sort_name,id limit 21 offset p_offset
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.sort_name,h.id),'[]') into result from hits h join schools s on s.id=h.school_id left join teachers t on h.kind='teacher' and t.id=h.id;
  return result;
 end if;
 q:=to_tsquery('simple',terms);q_any:=to_tsquery('simple',any_terms);
 for token in select t from regexp_split_to_table(normalized,' +')t where t~'^[[:alpha:]]{4,32}$' loop
  if not exists(select 1 from catalog_spelling.words where word like token||'%') then exact_feasible:=false;exit;end if;
 end loop;
 if exact_feasible then
 with teacher_own_strict as materialized(
 select t.id,t.school_id,t.name,t.staff_search_document document from teachers t
 where p_kind<>'schools' and t.staff_search_document@@q and((coalesce(p_region,'')='' and coalesce(p_city,'')='') or t.school_id in(select id from catalog_spelling.school_documents where archived_at is null and(coalesce(p_region,'')='' or region=p_region or p_region=any(campus_regions))and(coalesce(p_city,'')='' or city=p_city)))
),teacher_own_any as materialized(
 select t.id,t.school_id,t.name,t.staff_search_document document from teachers t
 where p_kind<>'schools' and not exists(select 1 from teacher_own_strict) and t.staff_search_document@@q_any and((coalesce(p_region,'')='' and coalesce(p_city,'')='') or t.school_id in(select id from catalog_spelling.school_documents where archived_at is null and(coalesce(p_region,'')='' or region=p_region or p_region=any(campus_regions))and(coalesce(p_city,'')='' or city=p_city)))
),teacher_candidates as materialized(
 select t.*,t.document match_document from teacher_own_strict t
 union all
 select t.*,t.document||s.catalog_search_document from teacher_own_any t join catalog_spelling.school_documents s on s.id=t.school_id where s.archived_at is null and(t.document||s.catalog_search_document)@@q
 union all
 select t.id,t.school_id,t.name,t.staff_search_document,t.staff_search_document||s.catalog_search_document
 from (select id,catalog_search_document from catalog_spelling.school_documents where p_kind='teachers' and not exists(select 1 from teacher_own_strict) and not exists(select 1 from teacher_own_any) and archived_at is null and catalog_search_document@@q and(coalesce(p_region,'')='' or region=p_region or p_region=any(campus_regions))and(coalesce(p_city,'')='' or city=p_city) offset 0)s join teachers t on t.school_id=s.id
),exact_hits as materialized(
  select 'school' kind,s.id,s.id school_id,s.name sort_name,
   (case when s.name_key=normalized then 4 when s.name_key like normalized||'%' then 2 else 0 end)+2*ts_rank(s.name_document,q)+ts_rank(s.catalog_search_document,q) rank
  from catalog_spelling.school_documents s where p_kind<>'teachers' and s.archived_at is null and s.catalog_search_document@@q and(coalesce(p_region,'')='' or s.region=p_region or p_region=any(s.campus_regions))and(coalesce(p_city,'')='' or s.city=p_city)
  union all
  select 'teacher',t.id,t.school_id,t.name,
   (case when catalog_normalize(t.name)=normalized then 4 when catalog_normalize(t.name) like normalized||'%' then 2 else 0 end)+2*ts_rank(t.document,q)+ts_rank(t.match_document,q)
  from teacher_candidates t
 ),page as(select * from exact_hits order by rank desc,sort_name,id limit 21 offset p_offset)
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'match_type','exact','record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.rank desc,h.sort_name,h.id),'[]'),(select count(*) from exact_hits),exists(select 1 from teacher_own_strict),exists(select 1 from teacher_own_any)
 into result,exact_count,exact_own_strict,exact_own_any from page h join schools s on s.id=h.school_id left join teachers t on h.kind='teacher' and t.id=h.id;
 else result:='[]';exact_count:=0;exact_own_strict:=false;exact_own_any:=false;
 end if;
 if jsonb_array_length(result)>0 or length(normalized)<4 then return result;end if;

 perform extensions.similarity('','');
 perform set_config('pg_trgm.similarity_threshold','0.3',true);

 for token in select t from regexp_split_to_table(normalized,' +')t where length(t)>0 loop
  alternatives:=null;
  if length(token)>=4 and token!~'^[0-9]+$' then
   select string_agg(quote_literal(word)||':*',' | ' order by score desc,word) into alternatives from(
    select word,extensions.similarity(word,token) score from catalog_spelling.words where word OPERATOR(extensions.%) token and abs(length(word)-length(token))<=2 and word<>token and word not like token||'%'
    order by score desc,word limit 4
   )nearest;
  end if;
  alternatives:='('||quote_literal(token)||case when token~'^[0-9]+$' then '' else ':*' end||case when alternatives is not null then ' | '||alternatives else '' end||')';
  expanded:=concat_ws(' & ',expanded,alternatives);expanded_any:=concat_ws(' | ',expanded_any,alternatives);
 end loop;
 q_fuzzy:=to_tsquery('simple',expanded);q_fuzzy_any:=to_tsquery('simple',expanded_any);
 if q_fuzzy=q then return result;end if;
 with teacher_own_strict as materialized(
 select t.id,t.school_id,t.name,t.staff_search_document document from teachers t
 where p_kind<>'schools' and t.staff_search_document@@q_fuzzy and((coalesce(p_region,'')='' and coalesce(p_city,'')='') or t.school_id in(select id from catalog_spelling.school_documents where archived_at is null and(coalesce(p_region,'')='' or region=p_region or p_region=any(campus_regions))and(coalesce(p_city,'')='' or city=p_city)))
),teacher_own_any as materialized(
 select t.id,t.school_id,t.name,t.staff_search_document document from teachers t
 where p_kind<>'schools' and not exists(select 1 from teacher_own_strict) and t.staff_search_document@@q_fuzzy_any and((coalesce(p_region,'')='' and coalesce(p_city,'')='') or t.school_id in(select id from catalog_spelling.school_documents where archived_at is null and(coalesce(p_region,'')='' or region=p_region or p_region=any(campus_regions))and(coalesce(p_city,'')='' or city=p_city)))
),teacher_candidates as materialized(
 select t.*,t.document match_document from teacher_own_strict t
 union all
 select t.*,t.document||s.catalog_search_document from teacher_own_any t join catalog_spelling.school_documents s on s.id=t.school_id where s.archived_at is null and(t.document||s.catalog_search_document)@@q_fuzzy
 union all
 select t.id,t.school_id,t.name,t.staff_search_document,t.staff_search_document||s.catalog_search_document
 from (select id,catalog_search_document from catalog_spelling.school_documents where p_kind='teachers' and not exists(select 1 from teacher_own_strict) and not exists(select 1 from teacher_own_any) and archived_at is null and catalog_search_document@@q_fuzzy and(coalesce(p_region,'')='' or region=p_region or p_region=any(campus_regions))and(coalesce(p_city,'')='' or city=p_city) offset 0)s join teachers t on t.school_id=s.id
),hits as materialized(
  select * from(
   select 'school' kind,s.id,s.id school_id,s.name sort_name,2*extensions.word_similarity(normalized,s.name_key)+2*ts_rank(s.name_document,q_fuzzy)+ts_rank(s.catalog_search_document,q_fuzzy) rank
   from catalog_spelling.school_documents s where p_kind<>'teachers' and s.archived_at is null and s.catalog_search_document@@q_fuzzy and not s.catalog_search_document@@q and(coalesce(p_region,'')='' or s.region=p_region or p_region=any(s.campus_regions))and(coalesce(p_city,'')='' or s.city=p_city)
   union all
   select 'teacher',t.id,t.school_id,t.name,2*extensions.word_similarity(normalized,catalog_normalize(t.name))+2*ts_rank(t.document,q_fuzzy)+ts_rank(t.match_document,q_fuzzy)
   from teacher_candidates t where not(case when exact_own_strict then t.document@@q when exact_own_any then t.document@@q_any and t.match_document@@q when p_kind='teachers' then t.match_document@@q else false end)
  )ranked order by rank desc,sort_name,id limit(21-jsonb_array_length(result)) offset greatest(0,p_offset-exact_count)
 )
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'match_type','similar','record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.rank desc,h.sort_name,h.id),'[]') into fuzzy_result from hits h join schools s on s.id=h.school_id left join teachers t on h.kind='teacher' and t.id=h.id;
 return result||fuzzy_result;
end;$$;
revoke all on function public.search_catalog(text,text,text,text,integer) from public;
grant execute on function public.search_catalog(text,text,text,text,integer) to anon,authenticated;

-- Keep prefix and typo vocabulary consistent with public campus aliases.
create or replace function catalog_spelling.sync_words() returns trigger language plpgsql security definer set search_path='' as $$
declare old_words text[]:='{}';new_words text[]:='{}';linked_words text[]:='{}';w text;
begin
 if TG_TABLE_SCHEMA<>'public' or TG_TABLE_NAME not in('schools','teachers') then raise exception 'Unsupported spelling source';end if;
 if auth.uid() is null and session_user not in('postgres','supabase_admin') and coalesce(auth.jwt()->>'role','')<>'service_role' then return null;end if;
 if TG_TABLE_NAME='teachers' then
  if TG_OP<>'INSERT' then old_words:=tsvector_to_array(OLD.staff_search_document);end if;
  if TG_OP<>'DELETE' and exists(select 1 from public.schools where id=NEW.school_id and archived_at is null) then new_words:=tsvector_to_array(NEW.staff_search_document);end if;
 else
  if TG_OP<>'INSERT' and OLD.archived_at is null then old_words:=tsvector_to_array(OLD.catalog_search_document||pg_catalog.to_tsvector('simple',public.catalog_normalize(OLD.campus_search_text)));end if;
  if TG_OP<>'DELETE' and NEW.archived_at is null then new_words:=tsvector_to_array(NEW.catalog_search_document||pg_catalog.to_tsvector('simple',public.catalog_normalize(NEW.campus_search_text)));end if;
  if TG_OP='UPDATE' and (OLD.archived_at is null)<>(NEW.archived_at is null) then
   select coalesce(array_agg(distinct word),'{}') into linked_words from public.teachers t cross join lateral unnest(tsvector_to_array(t.staff_search_document))word where t.school_id=NEW.id;
   if NEW.archived_at is null then new_words:=new_words||linked_words;else old_words:=old_words||linked_words;end if;
  end if;
 end if;
 insert into catalog_spelling.words(word) select distinct x from unnest(new_words)x where x~'^[[:alpha:]]{4,32}$' on conflict(word) do nothing;
 for w in select distinct x from unnest(old_words)x where x~'^[[:alpha:]]{4,32}$' and not x=any(new_words) loop
  delete from catalog_spelling.words d where d.word=w
   and not exists(select 1 from public.schools s where s.archived_at is null and (s.catalog_search_document||pg_catalog.to_tsvector('simple',public.catalog_normalize(s.campus_search_text)))@@pg_catalog.to_tsquery('simple',pg_catalog.quote_literal(w)))
   and not exists(select 1 from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null and t.staff_search_document@@pg_catalog.to_tsquery('simple',pg_catalog.quote_literal(w)));
 end loop;
 return null;
end;$$;
revoke all on function catalog_spelling.sync_words() from public,anon,authenticated;
drop trigger schools_sync_spelling on public.schools;
create trigger schools_sync_spelling after insert or delete or update of name,city,address,region,registry_name,accreditation_name,archived_at,campus_search_text on public.schools for each row execute function catalog_spelling.sync_words();

create table private.school_campus_import_runs(
 run_id text primary key,expected_count integer not null check(expected_count between 1 and 20000),
 payload_md5 text not null check(payload_md5~'^[a-f0-9]{32}$'),teacher_digest text not null,
 created_at timestamptz not null default now(),applied_at timestamptz,applied_rows integer,applied_schools integer
);
create table private.school_profile_correction_audit(
 school_id uuid primary key references public.schools(id),
 canonical_school_id uuid references public.schools(id),before_data jsonb not null,
 reason text not null,source_url text not null,source_sha256 text not null,
 corrected_at timestamptz not null default now()
);
create index school_profile_correction_canonical_idx on private.school_profile_correction_audit(canonical_school_id);
alter table private.school_profile_correction_audit enable row level security;
revoke all on private.school_profile_correction_audit from public,anon,authenticated;
grant all on private.school_profile_correction_audit to service_role;
create table private.school_campus_import_stage(
 run_id text not null references private.school_campus_import_runs(run_id),ordinal integer not null check(ordinal>=0),
 row_text text not null check(length(row_text)<20000),primary key(run_id,ordinal)
);
alter table private.school_campus_import_runs enable row level security;
alter table private.school_campus_import_stage enable row level security;
revoke all on private.school_campus_import_runs,private.school_campus_import_stage from public,anon,authenticated;
grant all on private.school_campus_import_runs,private.school_campus_import_stage to service_role;
create function private.apply_school_campus_import(p_run text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare r private.school_campus_import_runs; n integer; checksum text; staff_digest text; ids uuid[]; changed integer;
begin
 select * into strict r from private.school_campus_import_runs where run_id=p_run for update;
 if r.applied_at is not null then raise exception 'Campus import already applied';end if;
 select count(*),md5(string_agg(row_text,E'\n' order by ordinal)) into n,checksum from private.school_campus_import_stage where run_id=p_run;
 if n<>r.expected_count or checksum<>r.payload_md5 then raise exception 'Campus payload integrity mismatch';end if;
 select md5(string_agg(id::text||'|'||school_id::text||'|'||coalesce(source_url,'')||'|'||coalesce(staff_identity_url,''),E'\n' order by id)) into staff_digest from public.teachers;
 if staff_digest is distinct from r.teacher_digest then raise exception 'Teacher mapping changed; review baseline';end if;
 if exists(select 1 from private.school_campus_import_stage st where st.run_id=p_run and (select count(*) from public.schools s where s.organization_ogrn=st.row_text::jsonb->>'school_ogrn' and s.archived_at is null)<>1) then raise exception 'Ambiguous or missing active organization';end if;
 if exists(select 1 from private.school_campus_import_stage st where st.run_id=p_run and (st.row_text::jsonb->>'verified_at')::timestamptz>now()+interval '1 day') then raise exception 'Future verification date';end if;
 insert into public.school_campuses(school_id,source_key,name,kind,address,city,region,aliases,source_url,identity_url,identity_method,identity_sha256,source_sha256,verified_at)
 select s.id,p->>'source_key',p->>'name',p->>'kind',p->>'address',p->>'city',p->>'region',array(select jsonb_array_elements_text(p->'aliases')),p->>'source_url',p->>'identity_url',p->>'identity_method',p->>'identity_sha256',p->>'source_sha256',(p->>'verified_at')::timestamptz
 from private.school_campus_import_stage st cross join lateral(select st.row_text::jsonb p)j join public.schools s on s.organization_ogrn=p->>'school_ogrn' and s.archived_at is null where st.run_id=p_run
 on conflict(school_id,source_key) do update set name=excluded.name,kind=excluded.kind,address=excluded.address,city=excluded.city,region=excluded.region,aliases=excluded.aliases,source_url=excluded.source_url,identity_url=excluded.identity_url,identity_method=excluded.identity_method,identity_sha256=excluded.identity_sha256,source_sha256=excluded.source_sha256,verified_at=excluded.verified_at where excluded.verified_at>=school_campuses.verified_at;
 get diagnostics changed=row_count;
 select array_agg(distinct s.id) into ids from private.school_campus_import_stage st join public.schools s on s.organization_ogrn=st.row_text::jsonb->>'school_ogrn' and s.archived_at is null where st.run_id=p_run;
 perform private.refresh_school_campus_summaries(ids);
 select md5(string_agg(id::text||'|'||school_id::text||'|'||coalesce(source_url,'')||'|'||coalesce(staff_identity_url,''),E'\n' order by id)) into staff_digest from public.teachers;
 if staff_digest is distinct from r.teacher_digest then raise exception 'Teacher mapping invariant failed';end if;
 update private.school_campus_import_runs set applied_at=now(),applied_rows=changed,applied_schools=cardinality(ids) where run_id=p_run;
 return jsonb_build_object('campuses',changed,'schools',cardinality(ids),'teacher_digest',staff_digest);
end;$$;
revoke all on function private.apply_school_campus_import(text) from public,anon,authenticated;

-- Soft corrections are explicit, admin-only, and refuse every referenced profile.
create function private.apply_school_profile_corrections(p_actions jsonb,p_teacher_digest text) returns integer language plpgsql security invoker set search_path='' as $$
declare x jsonb;target uuid;canonical uuid;fk record;linked boolean;staff_digest text;changed integer;
begin
 if jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions) not between 1 and 500 then raise exception 'Bounded reviewed corrections required';end if;
 select md5(string_agg(id::text||'|'||school_id::text||'|'||coalesce(source_url,'')||'|'||coalesce(staff_identity_url,''),E'\n' order by id)) into staff_digest from public.teachers;
 if staff_digest is distinct from p_teacher_digest then raise exception 'Teacher mapping changed';end if;
 if (select count(distinct a->>'school_id') from jsonb_array_elements(p_actions)a)<>jsonb_array_length(p_actions) then raise exception 'Duplicate correction target';end if;
 perform 1 from public.schools where id in(select(a->>'school_id')::uuid from jsonb_array_elements(p_actions)a) order by id for update;
 for x in select * from jsonb_array_elements(p_actions) loop
  target:=(x->>'school_id')::uuid;canonical:=(x->>'canonical_school_id')::uuid;
  if not exists(select 1 from public.schools where id=target and archived_at is null and osm_id is not null and organization_ogrn is null) then raise exception 'Only an active unlicensed map profile can be corrected';end if;
  if canonical is not null and not exists(select 1 from public.schools where id=canonical and id<>target and archived_at is null and organization_ogrn is not null) then raise exception 'Verified canonical organization required';end if;
  if coalesce(x->>'source_url','')!~'^https?://[^/]+/' or coalesce(x->>'source_sha256','')!~'^[a-f0-9]{64}$' or length(coalesce(x->>'reason',''))<20 then raise exception 'Reviewed source and reason required';end if;
  for fk in select c.conrelid::regclass relation,a.attname column_name,cardinality(c.conkey) columns from pg_catalog.pg_constraint c join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1] where c.contype='f' and c.confrelid='public.schools'::regclass and c.conrelid<>'catalog_spelling.school_documents'::regclass loop
   if fk.columns<>1 then raise exception 'Composite school reference requires review';end if;
   execute format('select exists(select 1 from %s where %I=$1)',fk.relation,fk.column_name) into linked using target;
   if linked then raise exception 'Referenced school profile must be reviewed without archiving: %',target;end if;
  end loop;
  insert into private.school_profile_correction_audit(school_id,canonical_school_id,before_data,reason,source_url,source_sha256) select target,canonical,to_jsonb(s),x->>'reason',x->>'source_url',x->>'source_sha256' from public.schools s where id=target;
  if canonical is not null then insert into public.school_profile_aliases(alias_school_id,school_id,source_url,source_sha256,verified_at) values(target,canonical,x->>'source_url',x->>'source_sha256',now());end if;
 end loop;
 update public.schools s set archived_at=now(),archive_reason=a.reason from private.school_profile_correction_audit a where s.id=a.school_id and s.archived_at is null and s.id in(select(item.value->>'school_id')::uuid from jsonb_array_elements(p_actions) as item(value));
 get diagnostics changed=row_count;
 select md5(string_agg(id::text||'|'||school_id::text||'|'||coalesce(source_url,'')||'|'||coalesce(staff_identity_url,''),E'\n' order by id)) into staff_digest from public.teachers;
 if staff_digest is distinct from p_teacher_digest then raise exception 'Teacher preservation invariant failed';end if;
 return changed;
end;$$;
revoke all on function private.apply_school_profile_corrections(jsonb,text) from public,anon,authenticated;
