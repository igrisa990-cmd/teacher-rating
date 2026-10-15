-- An unassociated public-word vocabulary, outside the exposed Data API schemas.
create schema catalog_spelling;
revoke all on schema catalog_spelling from public;
create table catalog_spelling.words(word text primary key check(word~'^[[:alpha:]]{4,32}$'));
alter table catalog_spelling.words enable row level security;
create policy published_spelling_words on catalog_spelling.words for select to anon,authenticated using(true);
grant usage on schema catalog_spelling to anon,authenticated;
grant select on catalog_spelling.words to anon,authenticated;
insert into catalog_spelling.words(word)
 select distinct word from(
  select unnest(tsvector_to_array(s.catalog_search_document)) word from public.schools s where s.archived_at is null
  union all
  select unnest(tsvector_to_array(t.staff_search_document)) from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null
 )v where word~'^[[:alpha:]]{4,32}$';
create index spelling_words_trgm_idx on catalog_spelling.words using gin(word extensions.gin_trgm_ops);

-- Trigger-only maintenance may write the private cache after an already-authorized
-- catalog change. It never changes a source record, grants a role or returns data.
create function catalog_spelling.sync_words() returns trigger language plpgsql security definer set search_path='' as $$
declare old_words text[]:='{}';new_words text[]:='{}';linked_words text[]:='{}';w text;
begin
 if TG_TABLE_SCHEMA<>'public' or TG_TABLE_NAME not in('schools','teachers') then raise exception 'Unsupported spelling source';end if;
 if auth.uid() is null and session_user not in('postgres','supabase_admin') and coalesce(auth.jwt()->>'role','')<>'service_role' then return null;end if;
 if TG_TABLE_NAME='teachers' then
  if TG_OP<>'INSERT' then old_words:=tsvector_to_array(OLD.staff_search_document);end if;
  if TG_OP<>'DELETE' and exists(select 1 from public.schools where id=NEW.school_id and archived_at is null) then new_words:=tsvector_to_array(NEW.staff_search_document);end if;
 else
  if TG_OP<>'INSERT' and OLD.archived_at is null then old_words:=tsvector_to_array(OLD.catalog_search_document);end if;
  if TG_OP<>'DELETE' and NEW.archived_at is null then new_words:=tsvector_to_array(NEW.catalog_search_document);end if;
  if TG_OP='UPDATE' and (OLD.archived_at is null)<>(NEW.archived_at is null) then
   select coalesce(array_agg(distinct word),'{}') into linked_words from public.teachers t cross join lateral unnest(tsvector_to_array(t.staff_search_document))word where t.school_id=NEW.id;
   if NEW.archived_at is null then new_words:=new_words||linked_words;else old_words:=old_words||linked_words;end if;
  end if;
 end if;
 insert into catalog_spelling.words(word) select distinct x from unnest(new_words)x where x~'^[[:alpha:]]{4,32}$' on conflict(word) do nothing;
 for w in select distinct x from unnest(old_words)x where x~'^[[:alpha:]]{4,32}$' and not x=any(new_words) loop
  delete from catalog_spelling.words d where d.word=w
   and not exists(select 1 from public.schools s where s.archived_at is null and s.catalog_search_document@@pg_catalog.to_tsquery('simple',pg_catalog.quote_literal(w)))
   and not exists(select 1 from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null and t.staff_search_document@@pg_catalog.to_tsquery('simple',pg_catalog.quote_literal(w)));
 end loop;
 return null;
end;$$;
revoke all on function catalog_spelling.sync_words() from public,anon,authenticated;
create trigger schools_sync_spelling after insert or delete or update of name,city,address,region,registry_name,accreditation_name,archived_at on public.schools for each row execute function catalog_spelling.sync_words();
create trigger teachers_sync_spelling after insert or delete or update of name,subject,staff_subject,school_id on public.teachers for each row execute function catalog_spelling.sync_words();
analyze catalog_spelling.words;
