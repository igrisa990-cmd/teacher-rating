begin;
alter table public.account_preferences add column region_onboarding_seen boolean not null default false;
update public.account_preferences set region_onboarding_seen=true where preferred_region is not null;

create or replace function public.save_my_profile(p_name text,p_bio text,p_school_id uuid,p_region text,p_avatar_color text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare profile public.profiles; preferences public.account_preferences;
begin
 if auth.uid() is null or not private.has_verified_account() then raise exception 'Подтвердите аккаунт';end if;
 if p_name is null or char_length(btrim(p_name)) not between 2 and 80 or char_length(coalesce(p_bio,''))>240 or (p_region is not null and char_length(btrim(p_region)) not between 2 and 160) then raise exception 'Проверьте имя и регион';end if;
 if p_school_id is not null and not exists(select 1 from public.schools where id=p_school_id and archived_at is null) then raise exception 'Школа недоступна';end if;
 update public.profiles set name=btrim(p_name),bio=btrim(coalesce(p_bio,'')),school_id=p_school_id where id=auth.uid() returning * into profile;
 if profile.id is null then raise exception 'Профиль недоступен';end if;
 insert into public.account_preferences(user_id,preferred_region,avatar_color) values(auth.uid(),btrim(p_region),p_avatar_color) on conflict(user_id) do update set preferred_region=coalesce(excluded.preferred_region,public.account_preferences.preferred_region),avatar_color=excluded.avatar_color,updated_at=now() returning * into preferences;
 return jsonb_build_object('profile',to_jsonb(profile),'preferences',to_jsonb(preferences));
end;$$;

alter table public.schools
 add column accreditation_ogrn text check(accreditation_ogrn is null or accreditation_ogrn~'^[0-9]{13}$'),
 add column accreditation_name text,
 add column accreditation_id text check(accreditation_id is null or accreditation_id~'^[a-fA-F0-9-]{20,100}$'),
 add column accreditation_number text,
 add column accreditation_url text,
 add column accreditation_checked_at timestamptz,
 add column accreditation_programs jsonb,
 add column accreditation_address text,
 add column city_key text generated always as(regexp_replace(lower(city),'^(?:(?:г|с|д|п|пос|пгт|рп|тер|ст-ца|х)\.?|город|село|деревня|посёлок|поселок|станица|аул|хутор)[[:space:]]+','','i')) stored,
 add column organization_ogrn text generated always as(coalesce(registry_ogrn,accreditation_ogrn)) stored,
 add constraint schools_organization_ogrn_consistent check(registry_ogrn is null or accreditation_ogrn is null or registry_ogrn=accreditation_ogrn),
 add constraint schools_accreditation_url check(accreditation_url is null or accreditation_url='https://isga.obrnadzor.gov.ru/accredreestr/details/'||accreditation_id);
create unique index schools_organization_ogrn_unique on public.schools(organization_ogrn) where organization_ogrn is not null;
create index schools_city_prefix_idx on public.schools(city_key text_pattern_ops) where archived_at is null;
create index schools_region_city_prefix_idx on public.schools(region,city_key text_pattern_ops) where archived_at is null;

create table private.catalog_accreditation_stage(run_key text not null,ogrn text not null,payload jsonb not null,primary key(run_key,ogrn));
create table private.catalog_import_runs(run_key text primary key,source_url text not null,snapshot_sha256 text not null,expected_rows integer not null,applied_at timestamptz,summary jsonb);
alter table private.catalog_accreditation_stage enable row level security;
alter table private.catalog_import_runs enable row level security;
revoke all on private.catalog_accreditation_stage,private.catalog_import_runs from public,anon,authenticated;

create function public.catalog_stats() returns jsonb language sql stable security invoker set search_path='' set statement_timeout='8s' as $$
 select jsonb_build_object('schools',(select count(*) from public.schools where archived_at is null),'teachers',(select count(*) from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null),'regions',coalesce((select jsonb_agg(to_jsonb(r)) from (select region,count(*)::integer as count from public.schools where archived_at is null group by region order by region)r),'[]'::jsonb),'sources',jsonb_build_object('licenses',(select count(*) from public.schools where archived_at is null and registry_url is not null),'accreditation',(select count(*) from public.schools where archived_at is null and accreditation_url is not null),'map',(select count(*) from public.schools where archived_at is null and osm_id is not null)));
$$;
create function public.catalog_bootstrap(p_region text default '') returns jsonb language sql stable security invoker set search_path='' set statement_timeout='8s' as $$
 with picked_schools as materialized(select s.* from public.schools s where s.archived_at is null and (nullif(nullif(p_region,''),'all') is null or s.region=p_region) order by s.name,s.id limit 200),
 picked_teachers as materialized(select t.* from public.teachers t join public.schools s on s.id=t.school_id where s.archived_at is null and (nullif(nullif(p_region,''),'all') is null or s.region=p_region) order by t.rating desc,t.id limit 120),
 needed_schools as (select * from picked_schools union select s.* from public.schools s where s.id in(select school_id from picked_teachers))
 select jsonb_build_object('schools',coalesce((select jsonb_agg(to_jsonb(s)) from needed_schools s),'[]'::jsonb),'teachers',coalesce((select jsonb_agg(to_jsonb(t)) from picked_teachers t),'[]'::jsonb),'stats',public.catalog_stats());
$$;
create function public.catalog_localities(p_query text,p_region text default '') returns table(city text,region text) language sql stable security invoker set search_path='' set statement_timeout='5s' as $$
 select s.city,s.region from public.schools s where s.archived_at is null and char_length(btrim(p_query)) between 2 and 80 and (nullif(p_region,'') is null or s.region=p_region) and s.city_key like replace(replace(replace(regexp_replace(lower(btrim(p_query)),'^(?:(?:г|с|д|п|пос|пгт|рп|тер|ст-ца|х)\.?|город|село|деревня|посёлок|поселок|станица|аул|хутор)[[:space:]]+','','i'),'\','\\'),'%','\%'),'_','\_')||'%' group by s.city,s.region order by s.city,s.region limit 30;
$$;
revoke all on function public.catalog_stats(),public.catalog_bootstrap(text),public.catalog_localities(text,text) from public;
grant execute on function public.catalog_stats(),public.catalog_bootstrap(text),public.catalog_localities(text,text) to anon,authenticated;
-- Admin-only, reviewed snapshot import. Preserve IDs, edits, reviews and archive state.
create or replace function private.apply_accreditation_snapshot(p_run text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare expected integer; actual integer; attached integer; updated integer; inserted integer; result jsonb;
begin
 perform pg_advisory_xact_lock(hashtext('catalog-accreditation-import'));
 select expected_rows into expected from private.catalog_import_runs where run_key=p_run for update;
 select count(*) into actual from private.catalog_accreditation_stage where run_key=p_run;
 if expected is null or expected<>actual or expected<1 then raise exception 'Incomplete staged snapshot: % / %',actual,expected;end if;
 create temporary table if not exists accreditation_prepared(ogrn text primary key,p jsonb,city_key text,name_key text,address_key text) on commit drop;
 truncate pg_temp.accreditation_prepared;
 insert into pg_temp.accreditation_prepared
 select ogrn,payload,
 regexp_replace(lower(payload->>'city'),'^(?:(?:г|с|д|п|пос|пгт|рп|тер|ст-ца|х)\.?|город|село|деревня|посёлок|поселок|станица|аул|хутор)[[:space:]]+','','i'),
 regexp_replace(lower(payload->>'name'),'[^а-яёa-z0-9]+','','g'),
 regexp_replace(lower(payload->>'address'),'[^а-яёa-z0-9]+','','g')
 from private.catalog_accreditation_stage where run_key=p_run;
 if exists(select 1 from pg_temp.accreditation_prepared where ogrn!~'^[0-9]{13}$' or p->>'accreditation_ogrn' is distinct from ogrn or p->>'accreditation_url' is distinct from 'https://isga.obrnadzor.gov.ru/accredreestr/details/'||(p->>'accreditation_id') or coalesce(length(p->>'city'),0)<2 or coalesce(length(p->>'address'),0)<5 or coalesce(length(p->>'region'),0)<2) then raise exception 'Invalid staged identity/address';end if;
 -- Attach only an unambiguous exact address or exact name in the same locality.
 -- Number alone is insufficient to establish an organization identity.
 with matches as (
 select s.id,p.ogrn,count(*) over(partition by s.id) sc,count(*) over(partition by p.ogrn) pc
 from public.schools s join pg_temp.accreditation_prepared p on s.region=p.p->>'region' and s.city_key=p.city_key
 and ((length(p.name_key)>4 and regexp_replace(lower(s.name),'[^а-яёa-z0-9]+','','g')=p.name_key)
 or (length(p.address_key)>10 and regexp_replace(lower(s.address),'[^а-яёa-z0-9]+','','g')=p.address_key))
 where s.archived_at is null and s.osm_id is not null and s.organization_ogrn is null
 and not exists(select 1 from public.schools known where known.organization_ogrn=p.ogrn)
 ) update public.schools s set accreditation_ogrn=m.ogrn from matches m where m.id=s.id and m.sc=1 and m.pc=1;
 get diagnostics attached=row_count;
 update public.schools s set accreditation_ogrn=p.ogrn,accreditation_name=p.p->>'accreditation_name',accreditation_id=p.p->>'accreditation_id',accreditation_number=p.p->>'accreditation_number',accreditation_url=p.p->>'accreditation_url',accreditation_checked_at=(p.p->>'accreditation_checked_at')::timestamptz,accreditation_programs=p.p->'accreditation_programs',accreditation_address=p.p->>'address'
 from pg_temp.accreditation_prepared p where s.organization_ogrn=p.ogrn and (s.accreditation_checked_at is null or s.accreditation_checked_at<=(p.p->>'accreditation_checked_at')::timestamptz);
 get diagnostics updated=row_count;
 insert into public.schools(name,city,address,region,country_code,source_type,accreditation_ogrn,accreditation_name,accreditation_id,accreditation_number,accreditation_url,accreditation_checked_at,accreditation_programs,accreditation_address)
 select p->>'name',p->>'city',p->>'address',p->>'region','RU','accreditation',ogrn,p->>'accreditation_name',p->>'accreditation_id',p->>'accreditation_number',p->>'accreditation_url',(p->>'accreditation_checked_at')::timestamptz,p->'accreditation_programs',p->>'address'
 from pg_temp.accreditation_prepared p where not exists(select 1 from public.schools s where s.organization_ogrn=p.ogrn);
 get diagnostics inserted=row_count;
 result=jsonb_build_object('snapshot_rows',actual,'inserted',inserted,'attached_map',attached,'metadata_updated',updated,'active_schools',(select count(*) from public.schools where archived_at is null));
 update private.catalog_import_runs set applied_at=now(),summary=result where run_key=p_run;
 return result;
end;$$;
revoke all on function private.apply_accreditation_snapshot(text) from public,anon,authenticated;

commit;
