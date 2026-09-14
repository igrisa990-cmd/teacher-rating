-- Учитель+ · seed / repair migration
-- Запусти этот файл ОДИН РАЗ в Supabase SQL Editor.
-- Он не удаляет существующие школы/учителей и добавляет недостающие записи.
create extension if not exists pgcrypto;

-- Базовые таблицы создаются только если их ещё нет.
create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text not null default 'Рига',
  address text default '',
  created_at timestamptz not null default now()
);

create table if not exists public.teachers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  subject text not null,
  category text default 'other',
  initials text default '',
  rating numeric(2,1) not null default 0,
  review_count integer not null default 0,
  recommend_percent integer not null default 0,
  school_id uuid references public.schools(id) on delete set null,
  bio text default '',
  created_at timestamptz not null default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text default '',
  created_at timestamptz not null default now()
);

alter table public.schools enable row level security;
alter table public.teachers enable row level security;
alter table public.reviews enable row level security;

drop policy if exists "public read schools" on public.schools;
create policy "public read schools" on public.schools for select using (true);

drop policy if exists "public read teachers" on public.teachers;
create policy "public read teachers" on public.teachers for select using (true);

drop policy if exists "users read reviews" on public.reviews;
create policy "users read reviews" on public.reviews for select using (true);

drop policy if exists "users insert own reviews" on public.reviews;
create policy "users insert own reviews" on public.reviews for insert to authenticated with check (auth.uid() = user_id);

-- Уникальная оценка одного учителя одним аккаунтом.
create unique index if not exists reviews_teacher_user_unique on public.reviews(teacher_id,user_id);

insert into public.schools(name,city,address) values
('Лицей №1','Рига','ул. Центральная, 1'),
('Гимназия «Новая волна»','Рига','ул. Школьная, 12'),
('Школа №8','Юрмала','ул. Морская, 8'),
('Гимназия №3','Рига','ул. Академическая, 20'),
('Школа технологий','Рига','ул. Научная, 5'),
('Гимназия «Балтика»','Рига','ул. Балтийская, 18')
on conflict do nothing;

with s as (select id,name from public.schools)
insert into public.teachers(name,subject,category,initials,rating,review_count,recommend_percent,school_id,bio)
select v.name,v.subject,v.category,v.initials,v.rating,v.review_count,v.recommend_percent,s.id,v.bio
from (values
('Анна Кузнецова','Математика','math','АК',4.9,126,98,'Лицей №1','Преподаёт математику через понятные объяснения, практику и задачи из реальной жизни.'),
('Дмитрий Смирнов','Информатика','science','ДС',4.8,98,96,'Лицей №1','Помогает разобраться в программировании и цифровых технологиях, уделяет внимание практике.'),
('Елена Петрова','Русский язык','languages','ЕП',4.7,143,94,'Гимназия «Новая волна»','Специализируется на грамотности, литературе и подготовке к экзаменам.'),
('Максим Иванов','Физика','science','МИ',4.6,87,92,'Гимназия «Новая волна»','Объясняет физику на экспериментах и наглядных примерах.'),
('Ольга Волкова','История','humanities','ОВ',4.5,76,90,'Школа №8','Делает акцент на понимании исторических причин и связей между событиями.'),
('Сергей Никитин','Английский язык','languages','СН',4.4,112,88,'Школа №8','Практикует разговорный английский и помогает уверенно готовиться к экзаменам.'),
('Мария Орлова','Биология','science','МО',4.8,91,95,'Гимназия №3','Совмещает теорию с лабораторными работами и современными научными примерами.'),
('Алексей Морозов','География','humanities','АМ',4.3,64,86,'Гимназия №3','Помогает увидеть связь географии с экономикой, природой и повседневной жизнью.'),
('Ирина Белова','Химия','science','ИБ',4.7,83,93,'Школа технологий','Объясняет химию через эксперименты, схемы и задачи.'),
('Роман Лебедев','Физика','science','РЛ',4.6,72,91,'Школа технологий','Фокусируется на понимании физических принципов, а не на механическом заучивании.')
) v(name,subject,category,initials,rating,review_count,recommend_percent,school_name,bio)
join s on s.name=v.school_name
where not exists (select 1 from public.teachers t where t.name=v.name and t.school_id=s.id);

-- Автоматически пересчитываем статистику после реальных отзывов.
create or replace function public.refresh_teacher_rating()
returns trigger language plpgsql security definer set search_path=public as $$
declare tid uuid;
begin
 tid:=coalesce(new.teacher_id,old.teacher_id);
 update public.teachers t
 set rating=coalesce((select round(avg(r.rating)::numeric,1) from public.reviews r where r.teacher_id=tid),0),
     review_count=(select count(*) from public.reviews r where r.teacher_id=tid),
     recommend_percent=coalesce((select round(100.0*count(*) filter(where r.rating>=4)/nullif(count(*),0))::int from public.reviews r where r.teacher_id=tid),0)
 where t.id=tid;
 return coalesce(new,old);
end $$;

drop trigger if exists refresh_teacher_rating_trigger on public.reviews;
create trigger refresh_teacher_rating_trigger after insert or update or delete on public.reviews
for each row execute function public.refresh_teacher_rating();

-- Если Supabase отключает подтверждение email, регистрация войдёт сразу.
-- Если подтверждение включено, после регистрации пользователь должен подтвердить email.


-- Profile table: имя и фамилия пользователя живут отдельно от auth.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null default '',
  last_name text not null default '',
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "profiles own read" on public.profiles;
create policy "profiles own read" on public.profiles for select to authenticated using (auth.uid()=id);
drop policy if exists "profiles own insert" on public.profiles;
create policy "profiles own insert" on public.profiles for insert to authenticated with check (auth.uid()=id);
drop policy if exists "profiles own update" on public.profiles;
create policy "profiles own update" on public.profiles for update to authenticated using (auth.uid()=id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,first_name,last_name)
 values(new.id,coalesce(new.raw_user_meta_data->>'first_name',''),coalesce(new.raw_user_meta_data->>'last_name',''))
 on conflict(id) do update set first_name=excluded.first_name,last_name=excluded.last_name;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
