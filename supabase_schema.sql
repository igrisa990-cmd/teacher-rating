-- Учитель+: база данных
create table if not exists public.teachers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  subject text not null,
  category text not null default 'all',
  initials text,
  rating numeric(2,1) not null default 0,
  review_count integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique(teacher_id,user_id)
);

alter table public.teachers enable row level security;
alter table public.reviews enable row level security;

create policy "teachers_read" on public.teachers for select using (true);
create policy "reviews_read" on public.reviews for select using (true);
create policy "reviews_insert_own" on public.reviews for insert with check (auth.uid() = user_id);
create policy "reviews_update_own" on public.reviews for update using (auth.uid() = user_id);
create policy "reviews_delete_own" on public.reviews for delete using (auth.uid() = user_id);

create or replace function public.refresh_teacher_rating()
returns trigger language plpgsql security definer as $$
declare tid uuid;
begin
  tid := coalesce(new.teacher_id, old.teacher_id);
  update public.teachers t set
    rating = coalesce((select round(avg(r.rating)::numeric,1) from public.reviews r where r.teacher_id=tid),0),
    review_count = (select count(*) from public.reviews r where r.teacher_id=tid)
  where t.id=tid;
  return coalesce(new,old);
end $$;

drop trigger if exists reviews_refresh_rating on public.reviews;
create trigger reviews_refresh_rating
after insert or update or delete on public.reviews
for each row execute function public.refresh_teacher_rating();

insert into public.teachers(name,subject,category,initials)
select * from (values
('Анна Кузнецова','Математика','math','АК'),
('Дмитрий Смирнов','Информатика','science','ДС'),
('Елена Петрова','Русский язык','languages','ЕП'),
('Максим Иванов','Физика','science','МИ'),
('Ольга Волкова','История','humanities','ОВ'),
('Сергей Никитин','Английский язык','languages','СН')
) v(name,subject,category,initials)
where not exists (select 1 from public.teachers);
