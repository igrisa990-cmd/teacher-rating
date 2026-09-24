-- Учитель+ — отдельные оценки директоров школ.
-- Идемпотентная миграция: безопасно выполнять повторно в Supabase SQL Editor.

create table if not exists public.director_reviews (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  director_name text check (director_name is null or char_length(trim(director_name)) between 2 and 160),
  rating numeric(2,1) not null check (rating between 1 and 5 and mod(rating * 10, 1) = 0),
  leadership numeric(2,1) not null check (leadership between 1 and 5 and mod(leadership * 10, 1) = 0),
  fairness numeric(2,1) not null check (fairness between 1 and 5 and mod(fairness * 10, 1) = 0),
  communication numeric(2,1) not null check (communication between 1 and 5 and mod(communication * 10, 1) = 0),
  safety numeric(2,1) not null check (safety between 1 and 5 and mod(safety * 10, 1) = 0),
  comment text not null default '' check (
    char_length(comment) <= 800 and
    comment !~* '(https?://|www[.]|t[.]me/|@[a-z0-9_]{3,}|[0-9][0-9 ()+-]{7,}[0-9])'
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_id, user_id)
);

create index if not exists director_reviews_school_created_idx
  on public.director_reviews(school_id, created_at desc);

alter table public.director_reviews enable row level security;

drop policy if exists director_reviews_public_read on public.director_reviews;
create policy director_reviews_public_read
  on public.director_reviews for select
  using (true);

drop policy if exists director_reviews_self_insert on public.director_reviews;
create policy director_reviews_self_insert
  on public.director_reviews for insert
  with check (auth.uid() = user_id);

drop policy if exists director_reviews_self_update on public.director_reviews;
create policy director_reviews_self_update
  on public.director_reviews for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on public.director_reviews from anon, authenticated;
grant select (id, school_id, director_name, rating, leadership, fairness, communication, safety, comment, created_at, updated_at)
  on public.director_reviews to anon, authenticated;
grant insert (school_id, user_id, director_name, rating, leadership, fairness, communication, safety, comment),
  update (school_id, user_id, director_name, rating, leadership, fairness, communication, safety, comment, updated_at)
  on public.director_reviews to authenticated;
