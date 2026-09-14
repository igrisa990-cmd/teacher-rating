-- Учитель+ — окончательная починка Supabase DB
-- Запусти ОДИН РАЗ в Supabase -> SQL Editor -> Run.
-- Этот файл НЕ удаляет существующие данные.

create extension if not exists pgcrypto;

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
  comment text not null default '',
  created_at timestamptz not null default now()
);

-- ВАЖНО: Data API должен иметь SQL grants, иначе publishable key получит 403/permission denied.
grant usage on schema public to anon, authenticated;
grant select on public.schools to anon, authenticated;
grant select on public.teachers to anon, authenticated;
grant select on public.reviews to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;
grant insert on public.reviews to authenticated;
grant update on public.reviews to authenticated;
grant delete on public.reviews to authenticated;

alter table public.schools enable row level security;
alter table public.teachers enable row level security;
alter table public.reviews enable row level security;

drop policy if exists "public read schools" on public.schools;
create policy "public read schools" on public.schools for select to anon, authenticated using (true);

drop policy if exists "public read teachers" on public.teachers;
create policy "public read teachers" on public.teachers for select to anon, authenticated using (true);

drop policy if exists "public read reviews" on public.reviews;
create policy "public read reviews" on public.reviews for select to anon, authenticated using (true);

drop policy if exists "authenticated insert own review" on public.reviews;
create policy "authenticated insert own review" on public.reviews
for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "authenticated update own review" on public.reviews;
create policy "authenticated update own review" on public.reviews
for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "authenticated delete own review" on public.reviews;
create policy "authenticated delete own review" on public.reviews
for delete to authenticated
using (auth.uid() = user_id);

create unique index if not exists reviews_teacher_user_unique
on public.reviews(teacher_id,user_id);

-- Заполняем каталог, только если таких записей ещё нет.
insert into public.schools(name,city,address)
select v.name,v.city,v.address
from (values
 ('Лицей №1','Рига','ул. Центральная, 1'),
 ('Гимназия «Новая волна»','Рига','ул. Школьная, 12'),
 ('Школа №8','Юрмала','ул. Морская, 8'),
 ('Гимназия №3','Рига','ул. Академическая, 20'),
 ('Школа технологий','Рига','ул. Научная, 5'),
 ('Гимназия «Балтика»','Рига','ул. Балтийская, 18')
) v(name,city,address)
where not exists (
 select 1 from public.schools s where lower(s.name)=lower(v.name) and lower(s.city)=lower(v.city)
);

insert into public.teachers(name,subject,category,initials,rating,review_count,recommend_percent,school_id,bio)
select v.name,v.subject,v.category,v.initials,v.rating,v.review_count,v.recommend_percent,s.id,v.bio
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
) v(name,subject,category,initials,rating,review_count,recommend_percent,school_name,bio)
join public.schools s on s.name=v.school_name
where not exists (
 select 1 from public.teachers t where t.name=v.name and t.school_id=s.id
);

-- После реальных отзывов статистика учителя пересчитывается автоматически.
create or replace function public.refresh_teacher_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare tid uuid;
begin
 tid := coalesce(new.teacher_id, old.teacher_id);
 update public.teachers t
 set rating = coalesce((select round(avg(r.rating)::numeric,1) from public.reviews r where r.teacher_id=tid),0),
     review_count = (select count(*) from public.reviews r where r.teacher_id=tid),
     recommend_percent = coalesce(
       (select round(100.0 * count(*) filter(where r.rating >= 4) / nullif(count(*),0))::int
        from public.reviews r where r.teacher_id=tid),0)
 where t.id=tid;
 return coalesce(new,old);
end;
$$;

drop trigger if exists refresh_teacher_rating_trigger on public.reviews;
create trigger refresh_teacher_rating_trigger
after insert or update or delete on public.reviews
for each row execute function public.refresh_teacher_rating();

grant execute on function public.refresh_teacher_rating() to authenticated;

-- Синхронизируем существующую статистику с отзывами.
update public.teachers t
set rating = coalesce((select round(avg(r.rating)::numeric,1) from public.reviews r where r.teacher_id=t.id),0),
    review_count = (select count(*) from public.reviews r where r.teacher_id=t.id),
    recommend_percent = coalesce(
      (select round(100.0 * count(*) filter(where r.rating >= 4) / nullif(count(*),0))::int
       from public.reviews r where r.teacher_id=t.id),0);

-- Проверка после запуска:
select 'schools' as table_name, count(*) as rows from public.schools
union all select 'teachers', count(*) from public.teachers
union all select 'reviews', count(*) from public.reviews;


-- Data API / PostgREST cache refresh.
notify pgrst, 'reload schema';

-- Diagnostics: these return counts and confirm the objects are queryable.
select count(*) as schools_count from public.schools;
select count(*) as teachers_count from public.teachers;
