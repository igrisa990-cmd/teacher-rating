-- School chat, video links, manual classes and school/class polls.
-- Run after the existing schools and director_reviews migrations.
begin;
create table if not exists public.school_classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  name text not null check(name ~ '^([1-9]|1[01])[А-ЯA-Z]?$'),
  created_at timestamptz not null default now(),
  unique(school_id,name), unique(id,school_id)
);
create or replace function public.valid_school_poll_options(options jsonb)
returns boolean language sql immutable set search_path=pg_catalog as $$
 select case when jsonb_typeof(options) <> 'array' then false else
 jsonb_array_length(options) between 2 and 8
 and not exists(select 1 from jsonb_array_elements(options) x where jsonb_typeof(x) <> 'string' or char_length(trim(x #>> '{}')) not between 1 and 100)
 and (select count(distinct lower(trim(x #>> '{}'))) from jsonb_array_elements(options) x)=jsonb_array_length(options) end
$$;
create table if not exists public.school_polls (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id) on delete cascade,
 class_id uuid,
 created_by uuid not null references auth.users(id),
 question text not null check(char_length(trim(question)) between 3 and 200),
 options jsonb not null check(public.valid_school_poll_options(options)),
 ends_at timestamptz,
 created_at timestamptz not null default now(),
 foreign key(class_id,school_id) references public.school_classes(id,school_id) on delete cascade,
 check(ends_at is null or ends_at>created_at)
);
create table if not exists public.school_poll_votes (
 poll_id uuid not null references public.school_polls(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 option_index integer not null check(option_index between 0 and 7),
 created_at timestamptz not null default now(),
 primary key(poll_id,user_id)
);
create table if not exists public.school_messages (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 alias text not null default 'Ученик',
 body text not null check(char_length(trim(body)) between 1 and 1000),
 created_at timestamptz not null default now()
);
create table if not exists public.school_reels (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 video_url text not null check(char_length(video_url)<=2000 and video_url ~* '^https://[^/@[:space:]]+[^[:space:]]*\.(mp4|webm)(\?[^[:space:]]*)?$'),
 caption text not null default '' check(char_length(caption)<=300),
 created_at timestamptz not null default now()
);
create index if not exists school_polls_school_created on public.school_polls(school_id,created_at desc);
create index if not exists school_messages_school_created on public.school_messages(school_id,created_at desc);
create index if not exists school_reels_school_created on public.school_reels(school_id,created_at desc);
alter table public.school_classes enable row level security;
alter table public.school_polls enable row level security;
alter table public.school_poll_votes enable row level security;
alter table public.school_messages enable row level security;
alter table public.school_reels enable row level security;
drop policy if exists classes_read on public.school_classes;
create policy classes_read on public.school_classes for select using(true);
drop policy if exists classes_create on public.school_classes;
create policy classes_create on public.school_classes for insert to authenticated with check(auth.uid()=created_by);
drop policy if exists polls_read on public.school_polls;
create policy polls_read on public.school_polls for select using(true);
drop policy if exists polls_create on public.school_polls;
create policy polls_create on public.school_polls for insert to authenticated with check(auth.uid()=created_by);
drop policy if exists messages_read on public.school_messages;
create policy messages_read on public.school_messages for select using(true);
drop policy if exists messages_create on public.school_messages;
create policy messages_create on public.school_messages for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists reels_read on public.school_reels;
create policy reels_read on public.school_reels for select using(true);
drop policy if exists reels_create on public.school_reels;
create policy reels_create on public.school_reels for insert to authenticated with check(auth.uid()=user_id);
revoke all on public.school_poll_votes from anon,authenticated;
grant select on public.school_classes,public.school_polls to anon,authenticated;
grant insert on public.school_classes,public.school_polls to authenticated;
-- Public chat/reel responses expose aliases, not account IDs.
revoke all on public.school_messages,public.school_reels from anon,authenticated;
grant select(id,school_id,alias,body,created_at) on public.school_messages to anon,authenticated;
grant select(id,school_id,video_url,caption,created_at) on public.school_reels to anon,authenticated;
grant insert(school_id,user_id,body,alias) on public.school_messages to authenticated;
grant insert(school_id,user_id,video_url,caption) on public.school_reels to authenticated;
create or replace function public.prepare_school_message()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if auth.uid() is null or new.user_id<>auth.uid() then raise exception 'Sign in required'; end if;
 perform pg_advisory_xact_lock(hashtext(new.user_id::text));
 if exists(select 1 from public.school_messages where user_id=new.user_id and created_at>now()-interval '3 seconds') then raise exception 'Please wait before sending another message'; end if;
 new.alias='Ученик '||substr(md5(new.user_id::text||new.school_id::text),1,4);
 new.created_at=now(); return new;
end $$;
drop trigger if exists prepare_school_message on public.school_messages;
create trigger prepare_school_message before insert on public.school_messages for each row execute function public.prepare_school_message();
create or replace function public.cast_school_vote(target_poll uuid,chosen_option integer)
returns void language plpgsql security definer set search_path=pg_catalog as $$
declare poll public.school_polls;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into poll from public.school_polls where id=target_poll for share;
 if not found then raise exception 'Poll not found'; end if;
 if poll.ends_at is not null and poll.ends_at<=now() then raise exception 'Poll is closed'; end if;
 if chosen_option is null or chosen_option<0 or chosen_option>=jsonb_array_length(poll.options) then raise exception 'Invalid option'; end if;
 insert into public.school_poll_votes(poll_id,user_id,option_index) values(target_poll,auth.uid(),chosen_option)
 on conflict(poll_id,user_id) do update set option_index=excluded.option_index;
end $$;
create or replace function public.school_poll_results(target_school uuid)
returns table(poll_id uuid,option_index integer,vote_count bigint,is_mine boolean)
language sql stable security definer set search_path=pg_catalog as $$
 select v.poll_id,v.option_index,count(*),bool_or(v.user_id=auth.uid())
 from public.school_poll_votes v join public.school_polls p on p.id=v.poll_id
 where p.school_id=target_school group by v.poll_id,v.option_index
$$;
revoke all on function public.cast_school_vote(uuid,integer) from public;
grant execute on function public.cast_school_vote(uuid,integer) to authenticated;
revoke all on function public.school_poll_results(uuid) from public;
grant execute on function public.school_poll_results(uuid) to anon,authenticated;
commit;
