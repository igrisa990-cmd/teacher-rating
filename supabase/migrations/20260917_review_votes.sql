-- Учитель+ — полезность отзывов.
-- Идемпотентная миграция: безопасно выполнять повторно в Supabase SQL Editor.

create table if not exists public.review_votes (
  review_id uuid not null references public.reviews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_helpful boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (review_id, user_id)
);

create index if not exists review_votes_review_id_idx
  on public.review_votes(review_id);

alter table public.review_votes enable row level security;

drop policy if exists review_votes_public_read on public.review_votes;
create policy review_votes_public_read
  on public.review_votes for select
  using (true);

drop policy if exists review_votes_self_insert on public.review_votes;
create policy review_votes_self_insert
  on public.review_votes for insert
  with check (
    auth.uid() = user_id
    and not exists (
      select 1 from public.reviews r
      where r.id = review_id and r.user_id = auth.uid()
    )
  );

drop policy if exists review_votes_self_update on public.review_votes;
create policy review_votes_self_update
  on public.review_votes for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and not exists (
      select 1 from public.reviews r
      where r.id = review_id and r.user_id = auth.uid()
    )
  );

drop policy if exists review_votes_self_delete on public.review_votes;
create policy review_votes_self_delete
  on public.review_votes for delete
  using (auth.uid() = user_id);

grant select on public.review_votes to anon, authenticated;
grant insert, update, delete on public.review_votes to authenticated;

