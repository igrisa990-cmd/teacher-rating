-- Учитель+ — минимальная схема и демонстрационный каталог России.
-- Вставьте файл целиком в Supabase SQL Editor и нажмите Run.
-- Скрипт идемпотентен: повторный запуск обновляет демо-записи.

create extension if not exists pgcrypto;

create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text,
  address text,
  region text,
  country_code text not null default 'RU',
  municipality text,
  source_type text not null default 'community',
  source_url text,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.schools add column if not exists region text;
alter table public.schools add column if not exists city text;
alter table public.schools add column if not exists address text;
alter table public.schools add column if not exists country_code text not null default 'RU';
alter table public.schools add column if not exists municipality text;
alter table public.schools add column if not exists source_type text not null default 'community';
alter table public.schools add column if not exists source_url text;
alter table public.schools add column if not exists verified_at timestamptz;

create table if not exists public.teachers (
  id uuid primary key default gen_random_uuid(),
  school_id uuid references public.schools(id) on delete set null,
  name text not null,
  subject text not null,
  category text,
  initials text,
  bio text,
  rating numeric(2,1) not null default 0 check (rating between 0 and 5),
  review_count integer not null default 0,
  recommend_percent integer not null default 0,
  source_type text not null default 'community',
  source_url text,
  verification_status text not null default 'community',
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.teachers add column if not exists source_type text not null default 'community';
alter table public.teachers add column if not exists source_url text;
alter table public.teachers add column if not exists verification_status text not null default 'community';
alter table public.teachers add column if not exists verified_at timestamptz;
alter table public.teachers add column if not exists category text;
alter table public.teachers add column if not exists initials text;
alter table public.teachers add column if not exists bio text;
alter table public.teachers add column if not exists rating numeric(2,1) not null default 0;
alter table public.teachers add column if not exists review_count integer not null default 0;
alter table public.teachers add column if not exists recommend_percent integer not null default 0;

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  user_id uuid not null,
  rating numeric(2,1) not null check (rating between 1 and 5),
  explanation numeric(2,1),
  fairness numeric(2,1),
  atmosphere numeric(2,1),
  engagement numeric(2,1),
  respect numeric(2,1),
  feedback numeric(2,1),
  workload numeric(2,1),
  exam_prep numeric(2,1),
  comment text,
  created_at timestamptz not null default now(),
  unique (teacher_id, user_id)
);

create table if not exists public.review_votes (
  review_id uuid not null references public.reviews(id) on delete cascade,
  user_id uuid not null,
  is_helpful boolean not null,
  created_at timestamptz not null default now(),
  primary key (review_id, user_id)
);

-- Эти команды также исправляют прежнюю ошибку "column explanation does not exist".
alter table public.reviews add column if not exists explanation numeric(2,1);
alter table public.reviews add column if not exists fairness numeric(2,1);
alter table public.reviews add column if not exists atmosphere numeric(2,1);
alter table public.reviews add column if not exists engagement numeric(2,1);
alter table public.reviews add column if not exists respect numeric(2,1);
alter table public.reviews add column if not exists feedback numeric(2,1);
alter table public.reviews add column if not exists workload numeric(2,1);
alter table public.reviews add column if not exists exam_prep numeric(2,1);

create index if not exists schools_region_city_idx on public.schools(region, city);
create index if not exists teachers_school_idx on public.teachers(school_id);
create index if not exists teachers_name_idx on public.teachers(name);
create index if not exists reviews_teacher_idx on public.reviews(teacher_id, created_at desc);

alter table public.schools enable row level security;
alter table public.teachers enable row level security;
alter table public.reviews enable row level security;
alter table public.review_votes enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='schools' and policyname='schools_public_read') then
    create policy schools_public_read on public.schools for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='teachers' and policyname='teachers_public_read') then
    create policy teachers_public_read on public.teachers for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='reviews' and policyname='reviews_public_read') then
    create policy reviews_public_read on public.reviews for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='review_votes' and policyname='review_votes_public_read') then
    create policy review_votes_public_read on public.review_votes for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='reviews' and policyname='reviews_owner_write') then
    create policy reviews_owner_write on public.reviews for all to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='review_votes' and policyname='review_votes_owner_write') then
    create policy review_votes_owner_write on public.review_votes for all to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
  end if;
end $$;

insert into public.schools(id,name,city,address,region,country_code,source_type) values
('31000000-0000-4000-8000-000000000001','Школа № 101 · демо','Москва','ул. Учебная, 10','Москва','RU','community'),
('31000000-0000-4000-8000-000000000002','Гимназия «Север» · демо','Санкт-Петербург','Северный проспект, 14','Санкт-Петербург','RU','community'),
('31000000-0000-4000-8000-000000000003','Лицей цифровых наук · демо','Казань','ул. Академическая, 7','Республика Татарстан','RU','community'),
('31000000-0000-4000-8000-000000000004','Инженерная школа · демо','Новосибирск','проспект Науки, 22','Новосибирская область','RU','community'),
('31000000-0000-4000-8000-000000000005','Гуманитарная гимназия · демо','Екатеринбург','ул. Мира, 31','Свердловская область','RU','community'),
('31000000-0000-4000-8000-000000000006','Школа естественных наук · демо','Краснодар','ул. Солнечная, 18','Краснодарский край','RU','community'),
('31000000-0000-4000-8000-000000000007','Лицей «Волга» · демо','Самара','Волжская набережная, 9','Самарская область','RU','community'),
('31000000-0000-4000-8000-000000000008','Школа новых технологий · демо','Владивосток','Океанский проспект, 40','Приморский край','RU','community')
on conflict(id) do update set name=excluded.name,city=excluded.city,address=excluded.address,region=excluded.region,country_code='RU',source_type='community';

insert into public.teachers(id,school_id,name,subject,category,initials,bio,rating,review_count,recommend_percent,source_type,verification_status) values
('32000000-0000-4000-8000-000000000001','31000000-0000-4000-8000-000000000001','Анна Морозова','Математика','math','АМ','Демонстрационный профиль преподавателя.',4.8,42,96,'community','community'),
('32000000-0000-4000-8000-000000000002','31000000-0000-4000-8000-000000000001','Илья Соколов','Русский язык','humanities','ИС','Демонстрационный профиль преподавателя.',4.6,35,92,'community','community'),
('32000000-0000-4000-8000-000000000003','31000000-0000-4000-8000-000000000002','Мария Белова','Английский язык','languages','МБ','Демонстрационный профиль преподавателя.',4.9,57,98,'community','community'),
('32000000-0000-4000-8000-000000000004','31000000-0000-4000-8000-000000000002','Павел Орлов','История','humanities','ПО','Демонстрационный профиль преподавателя.',4.5,28,90,'community','community'),
('32000000-0000-4000-8000-000000000005','31000000-0000-4000-8000-000000000003','Лейсан Каримова','Информатика','science','ЛК','Демонстрационный профиль преподавателя.',4.9,61,99,'community','community'),
('32000000-0000-4000-8000-000000000006','31000000-0000-4000-8000-000000000003','Ринат Сафиуллин','Физика','science','РС','Демонстрационный профиль преподавателя.',4.7,39,94,'community','community'),
('32000000-0000-4000-8000-000000000007','31000000-0000-4000-8000-000000000004','Елена Крылова','Химия','science','ЕК','Демонстрационный профиль преподавателя.',4.8,45,96,'community','community'),
('32000000-0000-4000-8000-000000000008','31000000-0000-4000-8000-000000000004','Алексей Волков','Робототехника','science','АВ','Демонстрационный профиль преподавателя.',4.9,50,98,'community','community'),
('32000000-0000-4000-8000-000000000009','31000000-0000-4000-8000-000000000005','Ольга Миронова','Литература','humanities','ОМ','Демонстрационный профиль преподавателя.',4.7,33,95,'community','community'),
('32000000-0000-4000-8000-000000000010','31000000-0000-4000-8000-000000000005','Сергей Лебедев','Обществознание','humanities','СЛ','Демонстрационный профиль преподавателя.',4.6,30,91,'community','community'),
('32000000-0000-4000-8000-000000000011','31000000-0000-4000-8000-000000000006','Наталья Романова','Биология','science','НР','Демонстрационный профиль преподавателя.',4.8,48,97,'community','community'),
('32000000-0000-4000-8000-000000000012','31000000-0000-4000-8000-000000000006','Дмитрий Егоров','География','science','ДЕ','Демонстрационный профиль преподавателя.',4.5,24,89,'community','community'),
('32000000-0000-4000-8000-000000000013','31000000-0000-4000-8000-000000000007','Виктория Павлова','Алгебра','math','ВП','Демонстрационный профиль преподавателя.',4.9,54,98,'community','community'),
('32000000-0000-4000-8000-000000000014','31000000-0000-4000-8000-000000000007','Максим Фёдоров','Физическая культура','creative','МФ','Демонстрационный профиль преподавателя.',4.6,29,92,'community','community'),
('32000000-0000-4000-8000-000000000015','31000000-0000-4000-8000-000000000008','Софья Ким','Программирование','science','СК','Демонстрационный профиль преподавателя.',4.9,64,99,'community','community'),
('32000000-0000-4000-8000-000000000016','31000000-0000-4000-8000-000000000008','Артём Зайцев','Английский язык','languages','АЗ','Демонстрационный профиль преподавателя.',4.7,37,95,'community','community')
on conflict(id) do update set school_id=excluded.school_id,name=excluded.name,subject=excluded.subject,category=excluded.category,initials=excluded.initials,bio=excluded.bio,rating=excluded.rating,review_count=excluded.review_count,recommend_percent=excluded.recommend_percent,source_type='community',verification_status='community';

grant usage on schema public to anon, authenticated;
grant select on public.schools, public.teachers, public.reviews, public.review_votes to anon, authenticated;
grant insert, update on public.reviews, public.review_votes to authenticated;
