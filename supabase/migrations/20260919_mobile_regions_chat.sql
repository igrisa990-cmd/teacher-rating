-- Учитель+ — региональные предпочтения, анонимный чат и комментарии школ.
-- Применять после 20260919_verification_decimal_ratings.sql.

-- Повторно закрепляем шаг 0,1 для баз, где предыдущая версия миграции
-- уже успела создать ограничения с шагом 0,5.
alter table public.teacher_requests drop constraint if exists teacher_requests_rating_half_step;
alter table public.teacher_requests drop constraint if exists teacher_requests_rating_tenth_step;
alter table public.teacher_requests alter column rating type numeric(2,1) using rating::numeric(2,1);
alter table public.teacher_requests add constraint teacher_requests_rating_tenth_step
  check (rating between 1 and 5 and mod(rating * 10, 1) = 0);

alter table public.reviews drop constraint if exists reviews_rating_half_step;
alter table public.reviews drop constraint if exists reviews_explanation_half_step;
alter table public.reviews drop constraint if exists reviews_fairness_half_step;
alter table public.reviews drop constraint if exists reviews_atmosphere_half_step;
alter table public.reviews drop constraint if exists reviews_more_criteria_half_step;
alter table public.reviews drop constraint if exists reviews_rating_tenth_step;
alter table public.reviews drop constraint if exists reviews_explanation_tenth_step;
alter table public.reviews drop constraint if exists reviews_fairness_tenth_step;
alter table public.reviews drop constraint if exists reviews_atmosphere_tenth_step;
alter table public.reviews drop constraint if exists reviews_more_criteria_tenth_step;
alter table public.reviews add constraint reviews_rating_tenth_step
  check (rating between 1 and 5 and mod(rating * 10, 1) = 0);
alter table public.reviews add constraint reviews_explanation_tenth_step
  check (explanation between 1 and 5 and mod(explanation * 10, 1) = 0);
alter table public.reviews add constraint reviews_fairness_tenth_step
  check (fairness between 1 and 5 and mod(fairness * 10, 1) = 0);
alter table public.reviews add constraint reviews_atmosphere_tenth_step
  check (atmosphere between 1 and 5 and mod(atmosphere * 10, 1) = 0);
alter table public.reviews add constraint reviews_more_criteria_tenth_step
  check (
    engagement between 1 and 5 and mod(engagement * 10, 1) = 0 and
    respect between 1 and 5 and mod(respect * 10, 1) = 0 and
    feedback between 1 and 5 and mod(feedback * 10, 1) = 0 and
    workload between 1 and 5 and mod(workload * 10, 1) = 0 and
    exam_prep between 1 and 5 and mod(exam_prep * 10, 1) = 0
  );

create table if not exists public.regional_chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  region text not null check (char_length(trim(region)) between 2 and 120),
  alias text not null default '',
  body text not null check (
    char_length(trim(body)) between 2 and 600 and
    body !~* '(https?://|www[.]|t[.]me/|@[a-z0-9_]{3,}|[0-9][0-9 ()+-]{7,}[0-9])'
  ),
  moderation_status text not null default 'published'
    check (moderation_status in ('published','hidden','removed')),
  created_at timestamptz not null default now()
);

create table if not exists public.school_comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  alias text not null default '',
  body text not null check (
    char_length(trim(body)) between 2 and 600 and
    body !~* '(https?://|www[.]|t[.]me/|@[a-z0-9_]{3,}|[0-9][0-9 ()+-]{7,}[0-9])'
  ),
  moderation_status text not null default 'published'
    check (moderation_status in ('published','hidden','removed')),
  created_at timestamptz not null default now()
);

create table if not exists public.message_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  chat_message_id uuid references public.regional_chat_messages(id) on delete cascade,
  school_comment_id uuid references public.school_comments(id) on delete cascade,
  reason text not null check (char_length(trim(reason)) between 3 and 300),
  created_at timestamptz not null default now(),
  check (num_nonnulls(chat_message_id, school_comment_id) = 1)
);

create index if not exists regional_chat_region_created_idx
  on public.regional_chat_messages(region, created_at desc)
  where moderation_status = 'published';
create index if not exists school_comments_school_created_idx
  on public.school_comments(school_id, created_at desc)
  where moderation_status = 'published';
create unique index if not exists message_reports_chat_once_idx
  on public.message_reports(user_id, chat_message_id) where chat_message_id is not null;
create unique index if not exists message_reports_school_once_idx
  on public.message_reports(user_id, school_comment_id) where school_comment_id is not null;

create or replace function public.assign_anonymous_student_alias()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  scope_key text;
begin
  scope_key := coalesce(to_jsonb(new)->>'region', to_jsonb(new)->>'school_id', 'community');
  new.alias := 'Ученик-' || upper(substr(md5(new.user_id::text || '|' || scope_key), 1, 4));
  new.body := trim(new.body);
  return new;
end;
$$;

create or replace function public.enforce_community_cooldown()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_table_name = 'regional_chat_messages' and exists (
    select 1 from public.regional_chat_messages
    where user_id=new.user_id and created_at > now() - interval '15 seconds'
  ) then
    raise exception 'cooldown';
  end if;
  if tg_table_name = 'school_comments' and exists (
    select 1 from public.school_comments
    where user_id=new.user_id and created_at > now() - interval '30 seconds'
  ) then
    raise exception 'cooldown';
  end if;
  return new;
end;
$$;

drop trigger if exists regional_chat_alias on public.regional_chat_messages;
create trigger regional_chat_alias before insert on public.regional_chat_messages
for each row execute function public.assign_anonymous_student_alias();
drop trigger if exists regional_chat_cooldown on public.regional_chat_messages;
create trigger regional_chat_cooldown before insert on public.regional_chat_messages
for each row execute function public.enforce_community_cooldown();
drop trigger if exists school_comment_alias on public.school_comments;
create trigger school_comment_alias before insert on public.school_comments
for each row execute function public.assign_anonymous_student_alias();
drop trigger if exists school_comment_cooldown on public.school_comments;
create trigger school_comment_cooldown before insert on public.school_comments
for each row execute function public.enforce_community_cooldown();

alter table public.regional_chat_messages enable row level security;
alter table public.school_comments enable row level security;
alter table public.message_reports enable row level security;

drop policy if exists regional_chat_public_read on public.regional_chat_messages;
create policy regional_chat_public_read on public.regional_chat_messages for select
  using (moderation_status = 'published');
drop policy if exists regional_chat_self_insert on public.regional_chat_messages;
create policy regional_chat_self_insert on public.regional_chat_messages for insert
  with check (auth.uid() = user_id);

drop policy if exists school_comments_public_read on public.school_comments;
create policy school_comments_public_read on public.school_comments for select
  using (moderation_status = 'published');
drop policy if exists school_comments_self_insert on public.school_comments;
create policy school_comments_self_insert on public.school_comments for insert
  with check (auth.uid() = user_id);

drop policy if exists message_reports_self_insert on public.message_reports;
create policy message_reports_self_insert on public.message_reports for insert
  with check (auth.uid() = user_id);

revoke all on public.regional_chat_messages from anon, authenticated;
revoke all on public.school_comments from anon, authenticated;
revoke all on public.message_reports from anon, authenticated;
grant select (id, region, alias, body, created_at)
  on public.regional_chat_messages to anon, authenticated;
grant insert (user_id, region, body)
  on public.regional_chat_messages to authenticated;
grant select (id, school_id, alias, body, created_at)
  on public.school_comments to anon, authenticated;
grant insert (user_id, school_id, body)
  on public.school_comments to authenticated;
grant insert (user_id, chat_message_id, school_comment_id, reason)
  on public.message_reports to authenticated;

