-- TEACHER+ DATABASE RESET v2
-- Используй этот SQL ОДИН РАЗ. Он пересоздаёт ТОЛЬКО таблицы приложения:
-- schools, teachers, reviews. Auth пользователей НЕ удаляется.
-- Это намеренно: старые несовместимые схемы больше не будут мешать.

begin;

drop table if exists public.reviews cascade;
drop table if exists public.teachers cascade;
drop table if exists public.schools cascade;

create table public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text not null default 'Рига',
  address text not null default '',
  created_at timestamptz not null default now()
);

create table public.teachers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  subject text not null,
  category text not null default 'other',
  initials text not null default '',
  rating numeric(2,1) not null default 0,
  review_count integer not null default 0,
  recommend_percent integer not null default 0,
  school_id uuid not null references public.schools(id) on delete cascade,
  bio text not null default '',
  created_at timestamptz not null default now()
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text not null default '',
  created_at timestamptz not null default now(),
  constraint reviews_teacher_user_unique unique (teacher_id,user_id)
);

-- Data API grants. Supabase changed new-project defaults in 2026,
-- so we make exposure explicit.
grant usage on schema public to anon, authenticated;
grant select on public.schools to anon, authenticated;
grant select on public.teachers to anon, authenticated;
grant select on public.reviews to anon, authenticated;
grant insert,update,delete on public.reviews to authenticated;
grant usage,select on all sequences in schema public to anon, authenticated;

alter table public.schools enable row level security;
alter table public.teachers enable row level security;
alter table public.reviews enable row level security;

create policy schools_public_read on public.schools
for select to anon, authenticated using (true);

create policy teachers_public_read on public.teachers
for select to anon, authenticated using (true);

create policy reviews_public_read on public.reviews
for select to anon, authenticated using (true);

create policy reviews_insert_own on public.reviews
for insert to authenticated
with check (auth.uid() = user_id);

create policy reviews_update_own on public.reviews
for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy reviews_delete_own on public.reviews
for delete to authenticated
using (auth.uid() = user_id);

insert into public.schools(name,city,address) values
('Лицей №1','Рига','ул. Центральная, 1'),
('Гимназия «Новая волна»','Рига','ул. Школьная, 12'),
('Школа №8','Юрмала','ул. Морская, 8'),
('Гимназия №3','Рига','ул. Академическая, 20'),
('Школа технологий','Рига','ул. Научная, 5'),
('Гимназия «Балтика»','Рига','ул. Балтийская, 18');

insert into public.teachers(name,subject,category,initials,rating,review_count,recommend_percent,school_id,bio)
select x.name,x.subject,x.category,x.initials,x.rating,x.review_count,x.recommend_percent,s.id,x.bio
from (values
('Анна Кузнецова','Математика','math','АК',4.9,126,98,'Лицей №1','Преподаёт математику через понятные объяснения, практику и задачи из реальной жизни.'),
('Дмитрий Смирнов','Информатика','science','ДС',4.8,98,96,'Лицей №1','Помогает разобраться в программировании и цифровых технологиях.'),
('Елена Петрова','Русский язык','languages','ЕП',4.7,143,94,'Гимназия «Новая волна»','Специализируется на грамотности, литературе и подготовке к экзаменам.'),
('Максим Иванов','Физика','science','МИ',4.6,87,92,'Гимназия «Новая волна»','Объясняет физику на экспериментах и наглядных примерах.'),
('Ольга Волкова','История','humanities','ОВ',4.5,76,90,'Школа №8','Делает акцент на понимании исторических причин и связей.'),
('Сергей Никитин','Английский язык','languages','СН',4.4,112,88,'Школа №8','Практикует разговорный английский и подготовку к экзаменам.'),
('Мария Орлова','Биология','science','МО',4.8,91,95,'Гимназия №3','Совмещает теорию с лабораторными работами.'),
('Алексей Морозов','География','humanities','АМ',4.3,64,86,'Гимназия №3','Показывает связь географии с экономикой и природой.'),
('Ирина Белова','Химия','science','ИБ',4.7,83,93,'Школа технологий','Объясняет химию через эксперименты и задачи.'),
('Роман Лебедев','Физика','science','РЛ',4.6,72,91,'Школа технологий','Фокусируется на понимании физических принципов.')
) x(name,subject,category,initials,rating,review_count,recommend_percent,school_name,bio)
join public.schools s on s.name=x.school_name;

create or replace function public.refresh_teacher_rating()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare tid uuid;
begin
  tid := coalesce(new.teacher_id,old.teacher_id);
  update public.teachers t
  set rating=coalesce((select round(avg(r.rating)::numeric,1) from public.reviews r where r.teacher_id=tid),0),
      review_count=(select count(*) from public.reviews r where r.teacher_id=tid),
      recommend_percent=coalesce((select round(100.0*count(*) filter(where r.rating>=4)/nullif(count(*),0))::int from public.reviews r where r.teacher_id=tid),0)
  where t.id=tid;
  return coalesce(new,old);
end;
$$;

create trigger refresh_teacher_rating_trigger
after insert or update or delete on public.reviews
for each row execute function public.refresh_teacher_rating();

notify pgrst,'reload schema';

commit;

-- Диагностика: результат ДОЛЖЕН быть 6 / 10 / 0.
select
  (select count(*) from public.schools) as schools,
  (select count(*) from public.teachers) as teachers,
  (select count(*) from public.reviews) as reviews;

-- Проверка связей: ДОЛЖНО вернуть 10 строк, у каждой teacher_name есть school_name.
select t.name as teacher_name, s.name as school_name
from public.teachers t
join public.schools s on s.id=t.school_id
order by s.name,t.name;