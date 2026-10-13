begin;
alter table public.profiles add column if not exists bio text not null default '';
alter table public.profiles add constraint profiles_bio_length check(char_length(bio)<=240) not valid;
alter table public.profiles add constraint profiles_name_length check(char_length(btrim(name)) between 2 and 120) not valid;
alter table public.profiles enable row level security;
-- Replace overlapping policies and prohibit changing role/id or creating one's own role.
do $$declare p record;begin for p in select policyname from pg_policies where schemaname='public' and tablename='profiles' loop execute format('drop policy %I on public.profiles',p.policyname);end loop;end$$;
revoke all on public.profiles from public,anon,authenticated;
grant select on public.profiles to authenticated;
grant update(name,bio,school_id,class_name) on public.profiles to authenticated;
create policy profiles_owner_read on public.profiles for select to authenticated using(id=(select auth.uid()));
create policy profiles_owner_update on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()) and (select private.has_verified_account()));

create table public.account_preferences(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 preferred_region text check(preferred_region is null or char_length(preferred_region) between 2 and 160),
 theme text not null default 'original' check(theme in ('original','cloud','pixel','ocean','forest','sunset','candy','paper','neon','mono','terminal','cosmos')),
 color_mode text not null default 'theme' check(color_mode in ('theme','light','dark','system')),
 motion text not null default 'full' check(motion in ('full','reduced')),
 dock_visible boolean not null default true,
 dock_items text[] not null default array['home','teachers','schools','atmosphere']::text[] check(cardinality(dock_items)<=4 and dock_items<@array['home','teachers','schools','directors','atmosphere','voting','guides']::text[]),
 avatar_color text not null default 'violet' check(avatar_color in ('violet','mint','sky','rose','amber','slate')),
 updated_at timestamptz not null default now()
);
alter table public.account_preferences enable row level security;
revoke all on public.account_preferences from public,anon,authenticated;
grant select,insert,update on public.account_preferences to authenticated;
create policy account_preferences_owner_read on public.account_preferences for select to authenticated using(user_id=(select auth.uid()));
create policy account_preferences_owner_insert on public.account_preferences for insert to authenticated with check(user_id=(select auth.uid()) and (select private.has_verified_account()));
create policy account_preferences_owner_update on public.account_preferences for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and (select private.has_verified_account()));
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,name,role) values(new.id,left(coalesce(nullif(btrim(new.raw_user_meta_data->>'name'),''),'Ученик'),120),'student') on conflict(id) do nothing;
 insert into public.account_preferences(user_id,preferred_region) values(new.id,case when char_length(new.raw_user_meta_data->>'preferred_region') between 2 and 160 then new.raw_user_meta_data->>'preferred_region' else null end) on conflict(user_id) do nothing;
 return new;
end;$$;
revoke all on function public.handle_new_user() from public,anon,authenticated;
insert into public.account_preferences(user_id,preferred_region)
 select p.id,case when char_length(u.raw_user_meta_data->>'preferred_region') between 2 and 160 then u.raw_user_meta_data->>'preferred_region' else null end from public.profiles p join auth.users u on u.id=p.id on conflict(user_id) do nothing;

create function public.save_my_profile(p_name text,p_bio text,p_school_id uuid,p_region text,p_avatar_color text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare profile public.profiles; preferences public.account_preferences;
begin
 if auth.uid() is null or not private.has_verified_account() then raise exception 'Подтвердите аккаунт';end if;
 if char_length(btrim(p_name)) not between 2 and 80 or p_name is null or char_length(coalesce(p_bio,''))>240 or char_length(btrim(p_region)) not between 2 and 160 or p_region is null then raise exception 'Проверьте имя и регион';end if;
 if p_school_id is not null and not exists(select 1 from public.schools where id=p_school_id and archived_at is null) then raise exception 'Школа недоступна';end if;
 update public.profiles set name=btrim(p_name),bio=btrim(coalesce(p_bio,'')),school_id=p_school_id where id=auth.uid() returning * into profile;
 if profile.id is null then raise exception 'Профиль недоступен';end if;
 insert into public.account_preferences(user_id,preferred_region,avatar_color) values(auth.uid(),btrim(p_region),p_avatar_color) on conflict(user_id) do update set preferred_region=excluded.preferred_region,avatar_color=excluded.avatar_color,updated_at=now() returning * into preferences;
 return jsonb_build_object('profile',to_jsonb(profile),'preferences',to_jsonb(preferences));
end;$$;
revoke all on function public.save_my_profile(text,text,uuid,text,text) from public,anon;
grant execute on function public.save_my_profile(text,text,uuid,text,text) to authenticated;
create index if not exists profiles_school_id_idx on public.profiles(school_id);
commit;
