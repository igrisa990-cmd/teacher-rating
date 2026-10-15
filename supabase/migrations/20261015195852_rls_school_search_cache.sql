-- This cache has no privileged read path: caller RLS on the source school
-- is checked for every cache row, including after future source-policy changes.
create table catalog_spelling.school_documents(
 id uuid primary key references public.schools(id) on delete cascade,
 name text not null,name_key text not null,name_document tsvector not null,
 region text,city text,catalog_search_document tsvector not null,
 archived_at timestamptz check(archived_at is null)
);
alter table catalog_spelling.school_documents alter column catalog_search_document set storage plain;
alter table catalog_spelling.school_documents alter column name_document set storage plain;
alter table catalog_spelling.school_documents enable row level security;
create policy source_school_visibility on catalog_spelling.school_documents for select to anon,authenticated using(exists(select 1 from public.schools s where s.id=school_documents.id and s.archived_at is null));
grant usage on schema catalog_spelling to service_role;
grant select on catalog_spelling.school_documents to anon,authenticated,service_role;
insert into catalog_spelling.school_documents(id,name,name_key,name_document,region,city,catalog_search_document)
 select id,name,public.catalog_normalize(name),strip(to_tsvector('simple',public.catalog_normalize(name))),region,city,strip(catalog_search_document) from public.schools where archived_at is null;
create index school_documents_region_city_idx on catalog_spelling.school_documents(region,city,id);

-- Trigger-only writes copy already-authorized source changes. No source record
-- is read as definer or returned to a client by this maintenance function.
create function catalog_spelling.sync_school_document() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_TABLE_SCHEMA<>'public' or TG_TABLE_NAME<>'schools' then raise exception 'Unsupported search source';end if;
 if auth.uid() is null and session_user not in('postgres','supabase_admin','service_role') and coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Authorized catalog write required';end if;
 if TG_OP='DELETE' then delete from catalog_spelling.school_documents where id=OLD.id;return null;end if;
 if NEW.archived_at is not null then delete from catalog_spelling.school_documents where id=NEW.id;return null;end if;
 insert into catalog_spelling.school_documents(id,name,name_key,name_document,region,city,catalog_search_document)
 values(NEW.id,NEW.name,public.catalog_normalize(NEW.name),pg_catalog.strip(pg_catalog.to_tsvector('simple',public.catalog_normalize(NEW.name))),NEW.region,NEW.city,pg_catalog.strip(NEW.catalog_search_document))
 on conflict(id) do update set name=excluded.name,name_key=excluded.name_key,name_document=excluded.name_document,region=excluded.region,city=excluded.city,catalog_search_document=excluded.catalog_search_document;
 return null;
end;$$;
revoke all on function catalog_spelling.sync_school_document() from public,anon,authenticated;
create trigger schools_sync_search_document after insert or delete or update of name,city,address,region,registry_name,accreditation_name,archived_at on public.schools for each row execute function catalog_spelling.sync_school_document();
analyze catalog_spelling.school_documents;

-- Materialize matching public teacher rows before joining school documents. Invoker RLS is unchanged.
create or replace function public.search_catalog(p_query text default '',p_kind text default 'all',p_region text default '',p_city text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions
set jit=off set plan_cache_mode=force_custom_plan set statement_timeout='5s' as $$
declare q tsquery;q_any tsquery;terms text;any_terms text;normalized text;result jsonb;fuzzy_result jsonb;exact_count bigint;exact_own_strict boolean;exact_own_any boolean;token text;alternatives text;expanded text;expanded_any text;q_fuzzy tsquery;q_fuzzy_any tsquery;
begin
 if length(coalesce(p_query,''))>160 or p_offset is null or p_offset<0 or p_offset>100000 or p_kind is null or p_kind not in('all','schools','teachers') then raise exception 'Некорректные параметры поиска';end if;
 perform extensions.similarity('','');
 perform set_config('pg_trgm.similarity_threshold','0.3',true);
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
 with teacher_own_strict as materialized(
 select t.id,t.school_id,t.name,t.staff_search_document document from teachers t
 where p_kind<>'schools' and t.staff_search_document@@q and((coalesce(p_region,'')='' and coalesce(p_city,'')='') or t.school_id in(select id from catalog_spelling.school_documents where archived_at is null and(coalesce(p_region,'')='' or region=p_region)and(coalesce(p_city,'')='' or city=p_city)))
),teacher_own_any as materialized(
 select t.id,t.school_id,t.name,t.staff_search_document document from teachers t
 where p_kind<>'schools' and not exists(select 1 from teacher_own_strict) and t.staff_search_document@@q_any and((coalesce(p_region,'')='' and coalesce(p_city,'')='') or t.school_id in(select id from catalog_spelling.school_documents where archived_at is null and(coalesce(p_region,'')='' or region=p_region)and(coalesce(p_city,'')='' or city=p_city)))
),teacher_candidates as materialized(
 select t.*,t.document match_document from teacher_own_strict t
 union all
 select t.*,t.document||s.catalog_search_document from teacher_own_any t join catalog_spelling.school_documents s on s.id=t.school_id where s.archived_at is null and(t.document||s.catalog_search_document)@@q
 union all
 select t.id,t.school_id,t.name,t.staff_search_document,t.staff_search_document||s.catalog_search_document
 from (select id,catalog_search_document from catalog_spelling.school_documents where p_kind='teachers' and not exists(select 1 from teacher_own_strict) and not exists(select 1 from teacher_own_any) and archived_at is null and catalog_search_document@@q and(coalesce(p_region,'')='' or region=p_region)and(coalesce(p_city,'')='' or city=p_city) offset 0)s join teachers t on t.school_id=s.id
),exact_hits as materialized(
  select 'school' kind,s.id,s.id school_id,s.name sort_name,
   (case when s.name_key=normalized then 4 when s.name_key like normalized||'%' then 2 else 0 end)+2*ts_rank(s.name_document,q)+ts_rank(s.catalog_search_document,q) rank
  from catalog_spelling.school_documents s where p_kind<>'teachers' and s.archived_at is null and s.catalog_search_document@@q and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
  union all
  select 'teacher',t.id,t.school_id,t.name,
   (case when catalog_normalize(t.name)=normalized then 4 when catalog_normalize(t.name) like normalized||'%' then 2 else 0 end)+2*ts_rank(t.document,q)+ts_rank(t.match_document,q)
  from teacher_candidates t
 ),page as(select * from exact_hits order by rank desc,sort_name,id limit 21 offset p_offset)
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'match_type','exact','record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.rank desc,h.sort_name,h.id),'[]'),(select count(*) from exact_hits),exists(select 1 from teacher_own_strict),exists(select 1 from teacher_own_any)
 into result,exact_count,exact_own_strict,exact_own_any from page h join schools s on s.id=h.school_id left join teachers t on h.kind='teacher' and t.id=h.id;
 if jsonb_array_length(result)=21 or length(normalized)<4 then return result;end if;

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
 where p_kind<>'schools' and t.staff_search_document@@q_fuzzy and((coalesce(p_region,'')='' and coalesce(p_city,'')='') or t.school_id in(select id from catalog_spelling.school_documents where archived_at is null and(coalesce(p_region,'')='' or region=p_region)and(coalesce(p_city,'')='' or city=p_city)))
),teacher_own_any as materialized(
 select t.id,t.school_id,t.name,t.staff_search_document document from teachers t
 where p_kind<>'schools' and not exists(select 1 from teacher_own_strict) and t.staff_search_document@@q_fuzzy_any and((coalesce(p_region,'')='' and coalesce(p_city,'')='') or t.school_id in(select id from catalog_spelling.school_documents where archived_at is null and(coalesce(p_region,'')='' or region=p_region)and(coalesce(p_city,'')='' or city=p_city)))
),teacher_candidates as materialized(
 select t.*,t.document match_document from teacher_own_strict t
 union all
 select t.*,t.document||s.catalog_search_document from teacher_own_any t join catalog_spelling.school_documents s on s.id=t.school_id where s.archived_at is null and(t.document||s.catalog_search_document)@@q_fuzzy
 union all
 select t.id,t.school_id,t.name,t.staff_search_document,t.staff_search_document||s.catalog_search_document
 from (select id,catalog_search_document from catalog_spelling.school_documents where p_kind='teachers' and not exists(select 1 from teacher_own_strict) and not exists(select 1 from teacher_own_any) and archived_at is null and catalog_search_document@@q_fuzzy and(coalesce(p_region,'')='' or region=p_region)and(coalesce(p_city,'')='' or city=p_city) offset 0)s join teachers t on t.school_id=s.id
),hits as materialized(
  select * from(
   select 'school' kind,s.id,s.id school_id,s.name sort_name,2*ts_rank(s.name_document,q_fuzzy)+ts_rank(s.catalog_search_document,q_fuzzy) rank
   from catalog_spelling.school_documents s where p_kind<>'teachers' and s.archived_at is null and s.catalog_search_document@@q_fuzzy and not s.catalog_search_document@@q and(coalesce(p_region,'')='' or s.region=p_region)and(coalesce(p_city,'')='' or s.city=p_city)
   union all
   select 'teacher',t.id,t.school_id,t.name,2*ts_rank(t.document,q_fuzzy)+ts_rank(t.match_document,q_fuzzy)
   from teacher_candidates t where not(case when exact_own_strict then t.document@@q when exact_own_any then t.document@@q_any and t.match_document@@q when p_kind='teachers' then t.match_document@@q else false end)
  )ranked order by rank desc,sort_name,id limit(21-jsonb_array_length(result)) offset greatest(0,p_offset-exact_count)
 )
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'match_type','similar','record',case when h.kind='school' then to_jsonb(s)-'search_document'-'catalog_search_document' else to_jsonb(t)-'search_document'-'staff_search_document' end,'school',case when h.kind='teacher' then to_jsonb(s)-'search_document'-'catalog_search_document' else null end)order by h.rank desc,h.sort_name,h.id),'[]') into fuzzy_result from hits h join schools s on s.id=h.school_id left join teachers t on h.kind='teacher' and t.id=h.id;
 return result||fuzzy_result;
end;$$;
revoke all on function public.search_catalog(text,text,text,text,integer) from public;
grant execute on function public.search_catalog(text,text,text,text,integer) to anon,authenticated;

