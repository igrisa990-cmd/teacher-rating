-- Preserve historical profiles and attach explicit source status without broader access.
alter table public.schools add column registry_license_status text check(registry_license_status in('active','inactive'));
alter table public.schools add column registry_status_checked_at timestamptz;
alter table public.schools add column registry_status_snapshot_url text;
alter table public.schools add constraint registry_status_proof check(registry_license_status is null or(registry_status_checked_at is not null and registry_status_snapshot_url is not null and registry_status_snapshot_url ~ '^https://islod[.]obrnadzor[.]gov[.]ru/opendata-lic/data-[0-9]{8}-structure-20150421[.]zip$'));

-- Invoker-only maintenance of an already-authorized source row; no source reads.
create function private.sync_license_status() returns trigger language plpgsql security invoker set search_path='' as $$
declare version text;previous text;
begin
 version:=substring(NEW.registry_snapshot_url from '^https://islod[.]obrnadzor[.]gov[.]ru/opendata-lic/data-([0-9]{8})-structure-20150421[.]zip$');
 if version is null or NEW.registry_checked_at is null or NEW.registry_ogrn is null then return NEW;end if;
 if TG_OP='UPDATE' then
  previous:=substring(OLD.registry_status_snapshot_url from 'data-([0-9]{8})-');
  if previous>version or OLD.registry_status_checked_at>NEW.registry_checked_at then return NEW;end if;
 end if;
 NEW.registry_license_status:='active';NEW.registry_status_checked_at:=NEW.registry_checked_at;NEW.registry_status_snapshot_url:=NEW.registry_snapshot_url;
 return NEW;
end;$$;
revoke all on function private.sync_license_status() from public,anon,authenticated;
create trigger schools_source_license_status before insert or update of registry_checked_at,registry_snapshot_url,registry_ogrn on public.schools for each row execute function private.sync_license_status();
