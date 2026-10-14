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
