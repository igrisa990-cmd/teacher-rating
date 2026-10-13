begin;
create table private.auth_sms_deliveries(
 id text primary key check(id~'^[a-f0-9]{64}$'),
 phone_hash text not null check(phone_hash~'^[a-f0-9]{64}$'),
 status text not null default 'claimed' check(status in ('claimed','sent','tested','failed','unknown')),
 created_at timestamptz not null default now()
);
create index auth_sms_deliveries_created_idx on private.auth_sms_deliveries(created_at);
create index auth_sms_deliveries_phone_idx on private.auth_sms_deliveries(phone_hash,created_at);
alter table private.auth_sms_deliveries enable row level security;
revoke all on private.auth_sms_deliveries from public,anon,authenticated;
grant usage on schema private to service_role;
grant select,insert,update,delete on private.auth_sms_deliveries to service_role;
-- Invoker access: only the server service role can use this guard.
create function public.claim_auth_sms_delivery(p_id text,p_phone_hash text) returns text language plpgsql security invoker set search_path='' as $$
declare old_status text;
begin
 perform pg_advisory_xact_lock(773401);
 delete from private.auth_sms_deliveries where created_at<now()-interval '1 day';
 select status into old_status from private.auth_sms_deliveries where id=p_id;
 if old_status is not null then return case when old_status='claimed' then 'in_progress' else old_status end;end if;
 if (select count(*) from private.auth_sms_deliveries where created_at>now()-interval '1 hour')>=30 or (select count(*) from private.auth_sms_deliveries where phone_hash=p_phone_hash and created_at>now()-interval '10 minutes')>=3 then return 'limited';end if;
 insert into private.auth_sms_deliveries(id,phone_hash) values(p_id,p_phone_hash);
 return 'claimed';
end;$$;
create function public.finish_auth_sms_delivery(p_id text,p_status text) returns void language sql security invoker set search_path='' as $$
 update private.auth_sms_deliveries set status=p_status where id=p_id and status='claimed' and p_status in ('sent','tested','failed','unknown');
$$;
revoke all on function public.claim_auth_sms_delivery(text,text),public.finish_auth_sms_delivery(text,text) from public,anon,authenticated;
grant execute on function public.claim_auth_sms_delivery(text,text),public.finish_auth_sms_delivery(text,text) to service_role;
commit;
