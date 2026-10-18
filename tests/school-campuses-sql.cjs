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
await db.exec("create schema private;alter table schools add organization_ogrn text,add osm_id text,add archive_reason text;alter table teachers add source_url text,add staff_identity_url text;");
await db.exec(fs.readFileSync('supabase/migrations/20261017190850_school_campuses_and_aliases.sql','utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20261018154426_catalog_region_index_candidates.sql','utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20261018154833_catalog_point_lookup_results.sql','utf8'));
await db.exec(`insert into schools(id,name,region,city,organization_ogrn) values('11111111-1111-4111-8111-111111111111','Комплекс Квант','Ярославская область','Ярославль','1027600512532'),('22222222-2222-4222-8222-222222222222','Школа 548','Москва','Москва','1037739570384');`);
const rows=[{school_ogrn:'1027600512532',source_key:'a'.repeat(64),name:'Центр образования школа № 99',kind:'school',address:'Ярославль, улица Труфанова, дом 25а',city:'Ярославль',region:'Ярославская область',aliases:[],source_url:'https://school.example/common',identity_url:'https://school.example/common',identity_method:'official_license_record_link',identity_sha256:'b'.repeat(64),source_sha256:'b'.repeat(64),verified_at:'2026-10-17T12:00:00Z'},{school_ogrn:'1037739570384',source_key:'c'.repeat(64),name:'Инженерный корпус',kind:'school',address:'Московская область, Видное, дом 21А',city:'Видное',region:'Московская область',aliases:[],source_url:'https://school.example/addresses',identity_url:'https://school.example/organization',identity_method:'official_organization_api',identity_sha256:'d'.repeat(64),source_sha256:'e'.repeat(64),verified_at:'2026-10-17T12:00:00Z'}];
await db.exec("insert into teachers(school_id,name,subject) values('11111111-1111-4111-8111-111111111111','Учитель Проверки','Математика')");
await db.query(`insert into private.school_campus_import_runs values('test',2,md5($1),(select md5(string_agg(id::text||'|'||school_id::text||'|'||coalesce(source_url,'')||'|'||coalesce(staff_identity_url,''),E'\\n' order by id)) from teachers),now(),null,null,null)`,[rows.map(JSON.stringify).join('\n')]);
for(let i=0;i<rows.length;i++)await db.query('insert into private.school_campus_import_stage values($1,$2,$3)',['test',i,JSON.stringify(rows[i])]);
const applied=(await db.query("select private.apply_school_campus_import('test') result")).rows[0].result;assert.equal(applied.campuses,2);assert.equal(applied.schools,2);
await assert.rejects(db.query("select private.apply_school_campus_import('test')"),/already applied/);
await db.exec("set role anon");
let found=(await db.query("select public.search_catalog('99','schools','Ярославская область','',0) result")).rows[0].result;assert.equal(found.length,1);assert.equal(found[0].record.id,'11111111-1111-4111-8111-111111111111');
found=(await db.query("select public.search_catalog('Труфанова','schools','Ярославская область','',0) result")).rows[0].result;assert.equal(found.length,1,'New street tokens must participate in the spelling prefilter');
found=(await db.query("select public.search_catalog('548','schools','Московская область','',0) result")).rows[0].result;assert.equal(found.length,1,'Explicit branch region makes the legal organization discoverable');
for(const query of ['учит пров','УЧИТ ПРОВ','учитель проврки','']) {
 found=(await db.query('select public.search_catalog($1,\'teachers\',\'Ярославская область\',\'\',0) result',[query])).rows[0].result;
 assert.equal(found.length,1,`Regional teacher prefix/spelling/browse: ${query}`);
 assert.equal(found[0].record.school_id,'11111111-1111-4111-8111-111111111111');
}
assert.equal((await db.query("select jsonb_array_length(public.search_catalog('учит','teachers','Москва','',0)) n")).rows[0].n,0,'Other regions must not leak matching teachers');
assert.equal((await db.query("select jsonb_array_length(public.search_catalog('учит','teachers','Ярославская область','Ярославль',0)) n")).rows[0].n,1,'Explicit city filter is preserved');
await assert.rejects(db.query("insert into public.school_campuses(school_id) values('11111111-1111-4111-8111-111111111111')"),/permission denied/);
await assert.rejects(db.query("select private.apply_school_campus_import('test')"),/permission denied/);
await db.exec("reset role;create policy extra_visibility on schools as restrictive for select to anon using(id<>'11111111-1111-4111-8111-111111111111');set role anon");
assert.equal((await db.query("select count(*)::int n from school_campuses where school_id='11111111-1111-4111-8111-111111111111'")).rows[0].n,0);
assert.equal((await db.query("select jsonb_array_length(public.search_catalog('99','schools','Ярославская область','',0)) n")).rows[0].n,0,'Campus search must honor caller source RLS');
assert.equal((await db.query("select jsonb_array_length(public.search_catalog('учит','teachers','Ярославская область','',0)) n")).rows[0].n,0,'Regional teacher candidates must honor caller school RLS');
assert.equal((await db.query("select jsonb_array_length(public.search_catalog('','teachers','Ярославская область','',0)) n")).rows[0].n,0,'Regional browsing must honor caller school RLS');
await db.exec("reset role;insert into schools(id,name,osm_id) values('33333333-3333-4333-8333-333333333333','Карта школа 99','node/1');");
const digest=(await db.query("select md5(string_agg(id::text||'|'||school_id::text||'|'||coalesce(source_url,'')||'|'||coalesce(staff_identity_url,''),E'\\n' order by id)) digest from teachers")).rows[0].digest;
const actions=[{school_id:'33333333-3333-4333-8333-333333333333',canonical_school_id:'11111111-1111-4111-8111-111111111111',reason:'Reviewed explicit school number and exact campus address',source_url:'https://school.example/common',source_sha256:'b'.repeat(64)}];
await db.exec("create table school_comments(school_id uuid references schools(id));insert into school_comments values('33333333-3333-4333-8333-333333333333')");
await assert.rejects(db.query('select private.apply_school_profile_corrections($1::jsonb,$2)',[JSON.stringify(actions),digest]),/Referenced school profile/);
assert.equal((await db.query("select count(*)::int n from private.school_profile_correction_audit")).rows[0].n,0);
await db.exec('delete from school_comments');assert.equal((await db.query('select private.apply_school_profile_corrections($1::jsonb,$2) n',[JSON.stringify(actions),digest])).rows[0].n,1);
await db.exec('set role anon');assert.equal((await db.query('select count(*)::int n from school_profile_aliases')).rows[0].n,0,'Aliases inherit additional source RLS');
await assert.rejects(db.query('select private.apply_school_profile_corrections($1::jsonb,$2)',[JSON.stringify(actions),digest]),/permission denied/);
await db.exec('reset role');await db.close();console.log('PASS: campus integrity/no replay, organization/branch search, vocabulary, RLS, FK-safe soft correction, source-preserving aliases and public write denial');
})().catch(e=>{console.error(e.message, e.position, e.query?.slice(Math.max(0,Number(e.position)-100),Number(e.position)+100));process.exitCode=1});
