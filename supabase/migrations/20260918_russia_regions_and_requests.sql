-- Учитель+ — регионы России, происхождение данных и народное добавление учителей.
-- Идемпотентная миграция: безопасно выполнять повторно в Supabase SQL Editor.

alter table public.schools add column if not exists country_code text not null default 'LV';
alter table public.schools add column if not exists region text;
alter table public.schools add column if not exists municipality text;
alter table public.schools add column if not exists source_type text not null default 'official';
alter table public.schools add column if not exists source_url text;
alter table public.schools add column if not exists verified_at timestamptz;

alter table public.teachers add column if not exists source_type text not null default 'official';
alter table public.teachers add column if not exists source_url text;
alter table public.teachers add column if not exists verified_at timestamptz;

create index if not exists schools_country_region_city_idx on public.schools(country_code, region, city);
create index if not exists teachers_school_id_idx on public.teachers(school_id);

create table if not exists public.teacher_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  school_id uuid references public.schools(id) on delete set null,
  region text not null check (char_length(trim(region)) between 2 and 120),
  city text not null check (char_length(trim(city)) between 1 and 160),
  school_name text not null check (char_length(trim(school_name)) between 2 and 240),
  teacher_name text not null check (char_length(trim(teacher_name)) between 3 and 200),
  subject text not null check (char_length(trim(subject)) between 2 and 120),
  teacher_bio text check (teacher_bio is null or char_length(teacher_bio) <= 500),
  source_url text,
  rating integer not null check (rating between 1 and 5),
  status text not null default 'pending' check (status in ('pending','published','rejected')),
  published_teacher_id uuid references public.teachers(id) on delete set null,
  candidate_key text generated always as (
    md5(lower(trim(region)) || '|' || lower(trim(city)) || '|' || lower(trim(school_name)) || '|' || lower(trim(teacher_name)) || '|' || lower(trim(subject)))
  ) stored,
  created_at timestamptz not null default now(),
  unique(user_id, candidate_key)
);

create index if not exists teacher_requests_candidate_status_idx on public.teacher_requests(candidate_key, status);
create index if not exists teacher_requests_region_city_idx on public.teacher_requests(region, city);

alter table public.teacher_requests enable row level security;
drop policy if exists teacher_requests_public_read on public.teacher_requests;
create policy teacher_requests_public_read on public.teacher_requests for select using (true);
drop policy if exists teacher_requests_self_insert on public.teacher_requests;
create policy teacher_requests_self_insert on public.teacher_requests for insert with check (auth.uid() = user_id);

revoke all on public.teacher_requests from anon, authenticated;
grant select (id, school_id, region, city, school_name, teacher_name, subject, status, published_teacher_id, candidate_key, created_at)
  on public.teacher_requests to anon, authenticated;
grant insert (user_id, school_id, region, city, school_name, teacher_name, subject, teacher_bio, source_url, rating)
  on public.teacher_requests to authenticated;

-- Разрешаем автору изменять свою существующую оценку через upsert.
drop policy if exists reviews_self_update on public.reviews;
create policy reviews_self_update on public.reviews for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant update on public.reviews to authenticated;

create or replace function public.publish_teacher_after_five_requests()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  confirmations integer;
  target_school_id uuid;
  target_teacher_id uuid;
  average_rating numeric(3,2);
  recommendation integer;
begin
  select count(distinct user_id), round(avg(rating)::numeric, 2),
         round(100.0 * avg(case when rating >= 4 then 1 else 0 end))::integer
    into confirmations, average_rating, recommendation
  from public.teacher_requests
  where candidate_key = new.candidate_key and status = 'pending';

  if confirmations < 5 then return new; end if;

  target_school_id := new.school_id;
  if target_school_id is null then
    select id into target_school_id from public.schools
    where lower(trim(name)) = lower(trim(new.school_name))
      and lower(trim(coalesce(region, ''))) = lower(trim(new.region))
      and lower(trim(city)) = lower(trim(new.city))
    limit 1;
  end if;

  if target_school_id is null then
    insert into public.schools(name, city, region, country_code, source_type, source_url)
    values (trim(new.school_name), trim(new.city), trim(new.region), 'RU', 'community', new.source_url)
    returning id into target_school_id;
  end if;

  select id into target_teacher_id from public.teachers
  where school_id = target_school_id
    and lower(trim(name)) = lower(trim(new.teacher_name))
    and lower(trim(subject)) = lower(trim(new.subject))
  limit 1;

  if target_teacher_id is null then
    insert into public.teachers(school_id, name, subject, category, initials, bio, rating, review_count, recommend_percent, source_type, source_url)
    values (target_school_id, trim(new.teacher_name), trim(new.subject), 'community', upper(left(trim(new.teacher_name), 1)),
      coalesce(nullif(trim(new.teacher_bio), ''), 'Профиль подтверждён сообществом учеников.'),
      average_rating, confirmations, recommendation, 'community', new.source_url)
    returning id into target_teacher_id;
  end if;

  update public.teacher_requests set status = 'published', published_teacher_id = target_teacher_id
  where candidate_key = new.candidate_key and status = 'pending';
  return new;
end;
$$;

drop trigger if exists publish_teacher_after_five_requests on public.teacher_requests;
create trigger publish_teacher_after_five_requests after insert on public.teacher_requests
for each row execute function public.publish_teacher_after_five_requests();
