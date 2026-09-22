-- Учитель+ — отдельные оценки школ.
-- Идемпотентная миграция: безопасно выполнять повторно в Supabase SQL Editor.

create table if not exists public.school_reviews (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating numeric(2,1) not null check (rating between 1 and 5),
  comment text not null default '' check (
    char_length(comment) <= 800 and
    comment !~* '(https?://|www[.]|t[.]me/|@[a-z0-9_]{3,}|[0-9][0-9 ()+-]{7,}[0-9])'
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_id, user_id)
);

create index if not exists school_reviews_school_created_idx
  on public.school_reviews(school_id, created_at desc);

alter table public.school_reviews enable row level security;

drop policy if exists school_reviews_public_read on public.school_reviews;
create policy school_reviews_public_read
  on public.school_reviews for select
  using (true);

drop policy if exists school_reviews_self_insert on public.school_reviews;
create policy school_reviews_self_insert
  on public.school_reviews for insert
  with check (auth.uid() = user_id);

drop policy if exists school_reviews_self_update on public.school_reviews;
create policy school_reviews_self_update
  on public.school_reviews for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on public.school_reviews from anon, authenticated;
grant select (id, school_id, rating, comment, created_at, updated_at)
  on public.school_reviews to anon, authenticated;
grant insert (school_id, user_id, rating, comment),
  update (school_id, user_id, rating, comment, updated_at)
  on public.school_reviews to authenticated;
