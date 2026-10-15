const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{createRequire}=require('module');
const root=process.env.PGLITE_PATH||path.resolve('work/pglite-runtime/package'),req=createRequire(path.join(root,'package.json'));
const {PGlite}=require(root),{pg_trgm}=req('@electric-sql/pglite/contrib/pg_trgm');
(async()=>{const db=new PGlite({extensions:{pg_trgm}});
await db.exec(`create role anon;create role authenticated;create role service_role;
create schema extensions;create extension pg_trgm with schema extensions;
grant usage on schema extensions to anon,authenticated,service_role;
create schema auth;create function auth.uid() returns uuid language sql stable as $$select null::uuid$$;create function auth.jwt() returns jsonb language sql stable as $$select '{}'::jsonb$$;
grant usage on schema auth to anon,authenticated;grant execute on all functions in schema auth to anon,authenticated;
create function public.catalog_normalize(value text) returns text language sql immutable set search_path='pg_catalog' as $$select trim(regexp_replace(replace(lower(coalesce(value,'')),'ё','е'),'[^[:alnum:]]+',' ','g'))$$;
create table public.schools(id uuid primary key default gen_random_uuid(),name text not null,city text default '',region text,address text default '',country_code text,source_type text,registry_name text,accreditation_name text,archived_at timestamptz,
catalog_search_document tsvector generated always as(to_tsvector('simple',public.catalog_normalize(coalesce(name,'')||' '||coalesce(registry_name,'')||' '||coalesce(accreditation_name,'')||' '||coalesce(city,'')||' '||coalesce(address,'')||' '||coalesce(region,''))))stored);
create table public.teachers(id uuid primary key default gen_random_uuid(),school_id uuid not null references public.schools(id),name text not null,subject text not null,staff_subject text,source_type text,
staff_search_document tsvector generated always as(to_tsvector('simple',public.catalog_normalize(coalesce(name,'')||' '||coalesce(subject,'')||' '||coalesce(staff_subject,''))))stored);
alter table public.schools enable row level security;alter table public.teachers enable row level security;
create policy schools_public_read on public.schools for select to anon,authenticated using(true);
create policy schools_active_catalog on public.schools as restrictive for all to anon,authenticated using(archived_at is null);
create policy teachers_public_read on public.teachers for select to anon,authenticated using(true);
create policy active_school_catalog on public.teachers as restrictive for all to anon,authenticated using(exists(select 1 from public.schools s where s.id=teachers.school_id and s.archived_at is null));
grant select on public.schools,public.teachers to anon,authenticated;
create index schools_active_id_idx on public.schools(id) where archived_at is null;
create index teachers_school_idx on public.teachers(school_id);
select extensions.similarity('load','load');`);
assert.equal((await db.query("select lower('ФАДЕЕВА') value")).rows[0].value,'фадеева','Test database must support Russian case folding');
for(const file of [
'20261015175709_fuzzy_catalog_search.sql','20261015183309_bounded_fuzzy_catalog_search.sql','20261015192848_fast_spelling_catalog_search.sql','20261015194557_catalog_search_materialized_matches.sql','20261015195852_rls_school_search_cache.sql','20261015201027_catalog_search_spelling_prefilter.sql','20261015210101_school_cache_source_id_set.sql','20261015210621_teacher_visibility_source_id_set.sql'
,'20261015211029_fuzzy_catalog_relevance.sql','20261015211532_catalog_search_request_budget.sql','20261015211714_lazy_catalog_spelling.sql'])await db.exec(fs.readFileSync(path.join('supabase/migrations',file),'utf8'));
await db.exec('begin;'+fs.readFileSync('tests/fuzzy-catalog-search.sql','utf8')+'rollback;');
assert.equal((await db.query('select count(*)::int n from public.schools')).rows[0].n,0,'Fixtures must roll back');
await db.exec(`begin;
insert into schools(id,name,region,country_code,source_type)values('88888888-0000-4000-8000-000000000001','Скрытая тестовая школа','Закрытый регион','RU','community');
insert into teachers(school_id,name,subject,source_type)values('88888888-0000-4000-8000-000000000001','Скрытая Анна Петровна','Химия','community');
create policy source_visibility_probe on schools as restrictive for select to anon using(id<>'88888888-0000-4000-8000-000000000001');set local role anon;`);
assert.equal((await db.query("select count(*)::int n from catalog_spelling.school_documents where id='88888888-0000-4000-8000-000000000001'")).rows[0].n,0,'Cache must honor additional source RLS even when its row still exists');
assert.equal((await db.query("select count(*)::int n from public.teachers where school_id='88888888-0000-4000-8000-000000000001'")).rows[0].n,0,'Teachers must honor additional source-school RLS');
assert.equal((await db.query("select jsonb_array_length(public.search_catalog('Скрытая','all','Закрытый регион','',0)) n")).rows[0].n,0,'Hidden source records must never serialize');
await assert.rejects(db.query("insert into catalog_spelling.words values('подмена')"),/permission denied/);
await db.exec('rollback;');
await db.close();console.log('PASS: complete migration chain, case/prefix/typo search, pagination, source RLS propagation to cache, cache write denial, rolled-back fixtures');
})().catch(e=>{console.error(e.message);process.exitCode=1});
