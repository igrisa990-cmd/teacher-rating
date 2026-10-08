-- Match the actual profiles schema; users cannot supply their own role during signup.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,name,role)
 values(new.id,left(coalesce(nullif(trim(new.raw_user_meta_data->>'name'),''),'Ученик'),120),'student')
 on conflict(id) do nothing;
 return new;
end;$$;
revoke all on function public.handle_new_user() from public,anon,authenticated;
