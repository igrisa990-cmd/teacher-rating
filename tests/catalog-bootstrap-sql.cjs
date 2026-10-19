const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {PGlite}=require(process.env.PGLITE_PATH||path.resolve('work/pglite-runtime/package'));
(async()=>{const db=new PGlite();await db.exec(`
create role anon;create role authenticated;create schema catalog_search_internal;
create table public.schools(id uuid primary key default gen_random_uuid(),name text,region text,archived_at timestamptz,hidden boolean default false,search_document tsvector,catalog_search_document tsvector);
create table public.teachers(id uuid primary key default gen_random_uuid(),school_id uuid references public.schools(id),name text,rating numeric default 0,hidden boolean default false,search_document tsvector,staff_search_document tsvector);
alter table public.schools enable row level security;alter table public.teachers enable row level security;
create policy schools_read on public.schools for select to anon,authenticated using(archived_at is null and not hidden);
create policy teachers_read on public.teachers for select to anon,authenticated using(not hidden and exists(select 1 from public.schools s where s.id=teachers.school_id));
grant select on public.schools,public.teachers to anon,authenticated;
grant usage on schema catalog_search_internal to anon,authenticated;
create function public.catalog_stats() returns jsonb language sql stable as $$select '{"schools":110,"teachers":510}'::jsonb$$;
create function catalog_search_internal.bootstrap_ids(p_region text) returns table(kind text,id uuid,school_id uuid)
language sql stable security definer set search_path='' rows 120 as $$
 (select 'school'::text,s.id,s.id from public.schools s where s.archived_at is null and(p_region='' or s.region=p_region) order by s.name,s.id limit 80)
 union all
 (select 'teacher',t.id,t.school_id from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null and(p_region='' or s.region=p_region)order by t.rating desc,t.id limit 40);$$;
grant execute on function catalog_search_internal.bootstrap_ids(text) to anon,authenticated;
insert into schools(name,region)select 'Школа '||lpad(i::text,3,'0'),case when i<=100 then 'Москва' else 'Тестовый регион' end from generate_series(1,110)i;
insert into teachers(school_id,name,rating)select s.id,'Учитель '||i,i from schools s cross join generate_series(1,5)i;
update schools set hidden=true where name='Школа 001';
update teachers set hidden=true where school_id=(select id from schools where name='Школа 002');
update schools set archived_at=now() where name='Школа 003';
`);await db.exec(fs.readFileSync('supabase/migrations/20261019162706_catalog_bootstrap_point_lookups.sql','utf8'));
for(const role of ['anon','authenticated']){await db.exec('set role '+role);
for(const region of ['Москва','Тестовый регион','Неизвестный регион','']){
 const result=(await db.query('select public.catalog_bootstrap($1) result',[region])).rows[0].result;
 assert(result.schools.length<=120);assert(result.teachers.length<=40);assert.deepEqual(result.stats,{schools:110,teachers:510});
 if(region==='Неизвестный регион'){assert.deepEqual(result.schools,[]);assert.deepEqual(result.teachers,[])}else assert(result.schools.length>0);
 for(const s of result.schools){assert.equal(s.hidden,false);assert.equal(s.archived_at,null);assert(!('search_document'in s));assert(!('catalog_search_document'in s));if(region)assert.equal(s.region,region)}
 for(const t of result.teachers){assert.equal(t.hidden,false);assert(result.schools.some(s=>s.id===t.school_id));assert(!('search_document'in t));assert(!('staff_search_document'in t))}
}await db.exec('reset role')}
await db.close();console.log('PASS: bounded bootstrap, teacher schools, region filters, caller school/teacher RLS and response fields for anon/authenticated');
})().catch(e=>{console.error(e);process.exitCode=1});
