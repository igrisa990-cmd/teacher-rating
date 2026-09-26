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

-- Полный тестовый охват: по одной школе и два преподавателя для каждого
-- из 85 регионов, которые используются в интерфейсе. Это синтетические
-- записи, а не сведения из официального реестра.
with region_seed(region, city, n) as (
  values
    ('Белгородская область','Белгород',1),
    ('Брянская область','Брянск',2),
    ('Владимирская область','Владимир',3),
    ('Воронежская область','Воронеж',4),
    ('Ивановская область','Иваново',5),
    ('Калужская область','Калуга',6),
    ('Костромская область','Кострома',7),
    ('Курская область','Курск',8),
    ('Липецкая область','Липецк',9),
    ('Москва','Москва',10),
    ('Московская область','Красногорск',11),
    ('Орловская область','Орёл',12),
    ('Рязанская область','Рязань',13),
    ('Смоленская область','Смоленск',14),
    ('Тамбовская область','Тамбов',15),
    ('Тверская область','Тверь',16),
    ('Тульская область','Тула',17),
    ('Ярославская область','Ярославль',18),
    ('Республика Карелия','Петрозаводск',19),
    ('Республика Коми','Сыктывкар',20),
    ('Архангельская область','Архангельск',21),
    ('Вологодская область','Вологда',22),
    ('Калининградская область','Калининград',23),
    ('Ленинградская область','Гатчина',24),
    ('Мурманская область','Мурманск',25),
    ('Новгородская область','Великий Новгород',26),
    ('Псковская область','Псков',27),
    ('Санкт-Петербург','Санкт-Петербург',28),
    ('Ненецкий автономный округ','Нарьян-Мар',29),
    ('Республика Адыгея','Майкоп',30),
    ('Республика Калмыкия','Элиста',31),
    ('Республика Крым','Симферополь',32),
    ('Краснодарский край','Краснодар',33),
    ('Астраханская область','Астрахань',34),
    ('Волгоградская область','Волгоград',35),
    ('Ростовская область','Ростов-на-Дону',36),
    ('Севастополь','Севастополь',37),
    ('Республика Дагестан','Махачкала',38),
    ('Республика Ингушетия','Магас',39),
    ('Кабардино-Балкарская Республика','Нальчик',40),
    ('Карачаево-Черкесская Республика','Черкесск',41),
    ('Республика Северная Осетия — Алания','Владикавказ',42),
    ('Чеченская Республика','Грозный',43),
    ('Ставропольский край','Ставрополь',44),
    ('Республика Башкортостан','Уфа',45),
    ('Республика Марий Эл','Йошкар-Ола',46),
    ('Республика Мордовия','Саранск',47),
    ('Республика Татарстан','Казань',48),
    ('Удмуртская Республика','Ижевск',49),
    ('Чувашская Республика','Чебоксары',50),
    ('Пермский край','Пермь',51),
    ('Кировская область','Киров',52),
    ('Нижегородская область','Нижний Новгород',53),
    ('Оренбургская область','Оренбург',54),
    ('Пензенская область','Пенза',55),
    ('Самарская область','Самара',56),
    ('Саратовская область','Саратов',57),
    ('Ульяновская область','Ульяновск',58),
    ('Курганская область','Курган',59),
    ('Свердловская область','Екатеринбург',60),
    ('Тюменская область','Тюмень',61),
    ('Челябинская область','Челябинск',62),
    ('Ханты-Мансийский автономный округ — Югра','Ханты-Мансийск',63),
    ('Ямало-Ненецкий автономный округ','Салехард',64),
    ('Республика Алтай','Горно-Алтайск',65),
    ('Республика Тыва','Кызыл',66),
    ('Республика Хакасия','Абакан',67),
    ('Алтайский край','Барнаул',68),
    ('Красноярский край','Красноярск',69),
    ('Иркутская область','Иркутск',70),
    ('Кемеровская область — Кузбасс','Кемерово',71),
    ('Новосибирская область','Новосибирск',72),
    ('Омская область','Омск',73),
    ('Томская область','Томск',74),
    ('Республика Бурятия','Улан-Удэ',75),
    ('Республика Саха (Якутия)','Якутск',76),
    ('Забайкальский край','Чита',77),
    ('Камчатский край','Петропавловск-Камчатский',78),
    ('Приморский край','Владивосток',79),
    ('Хабаровский край','Хабаровск',80),
    ('Амурская область','Благовещенск',81),
    ('Магаданская область','Магадан',82),
    ('Сахалинская область','Южно-Сахалинск',83),
    ('Еврейская автономная область','Биробиджан',84),
    ('Чукотский автономный округ','Анадырь',85)
)
insert into public.schools(id,name,city,address,region,country_code,source_type)
select
  md5('teacher-plus:demo-school:' || region)::uuid,
  'Школа № ' || (100 + n) || ' · демо',
  city,
  'ул. Учебная, ' || (1 + (n % 40)),
  region,
  'RU',
  'community'
from region_seed
on conflict(id) do update set
  name=excluded.name,
  city=excluded.city,
  address=excluded.address,
  region=excluded.region,
  country_code='RU',
  source_type='community';

with region_seed(region, n) as (
  values
    ('Белгородская область',1),('Брянская область',2),('Владимирская область',3),('Воронежская область',4),
    ('Ивановская область',5),('Калужская область',6),('Костромская область',7),('Курская область',8),
    ('Липецкая область',9),('Москва',10),('Московская область',11),('Орловская область',12),
    ('Рязанская область',13),('Смоленская область',14),('Тамбовская область',15),('Тверская область',16),
    ('Тульская область',17),('Ярославская область',18),('Республика Карелия',19),('Республика Коми',20),
    ('Архангельская область',21),('Вологодская область',22),('Калининградская область',23),('Ленинградская область',24),
    ('Мурманская область',25),('Новгородская область',26),('Псковская область',27),('Санкт-Петербург',28),
    ('Ненецкий автономный округ',29),('Республика Адыгея',30),('Республика Калмыкия',31),('Республика Крым',32),
    ('Краснодарский край',33),('Астраханская область',34),('Волгоградская область',35),('Ростовская область',36),
    ('Севастополь',37),('Республика Дагестан',38),('Республика Ингушетия',39),('Кабардино-Балкарская Республика',40),
    ('Карачаево-Черкесская Республика',41),('Республика Северная Осетия — Алания',42),('Чеченская Республика',43),('Ставропольский край',44),
    ('Республика Башкортостан',45),('Республика Марий Эл',46),('Республика Мордовия',47),('Республика Татарстан',48),
    ('Удмуртская Республика',49),('Чувашская Республика',50),('Пермский край',51),('Кировская область',52),
    ('Нижегородская область',53),('Оренбургская область',54),('Пензенская область',55),('Самарская область',56),
    ('Саратовская область',57),('Ульяновская область',58),('Курганская область',59),('Свердловская область',60),
    ('Тюменская область',61),('Челябинская область',62),('Ханты-Мансийский автономный округ — Югра',63),('Ямало-Ненецкий автономный округ',64),
    ('Республика Алтай',65),('Республика Тыва',66),('Республика Хакасия',67),('Алтайский край',68),
    ('Красноярский край',69),('Иркутская область',70),('Кемеровская область — Кузбасс',71),('Новосибирская область',72),
    ('Омская область',73),('Томская область',74),('Республика Бурятия',75),('Республика Саха (Якутия)',76),
    ('Забайкальский край',77),('Камчатский край',78),('Приморский край',79),('Хабаровский край',80),
    ('Амурская область',81),('Магаданская область',82),('Сахалинская область',83),('Еврейская автономная область',84),
    ('Чукотский автономный округ',85)
), teacher_seed(slot, name_shift) as (values (1, 0), (2, 5)), prepared as (
  select
    region,
    n,
    slot,
    (array['Анна Морозова','Илья Соколов','Мария Белова','Павел Орлов','Лейсан Каримова','Ринат Сафиуллин','Елена Крылова','Алексей Волков','Ольга Миронова','Сергей Лебедев'])[((n + name_shift - 1) % 10) + 1] as teacher_name,
    (array['Математика','Русский язык','Английский язык','История','Информатика','Физика','Химия','Биология','Литература','География'])[((n + slot - 2) % 10) + 1] as subject,
    (array['math','humanities','languages','humanities','science','science','science','science','humanities','science'])[((n + slot - 2) % 10) + 1] as category
  from region_seed cross join teacher_seed
)
insert into public.teachers(id,school_id,name,subject,category,initials,bio,rating,review_count,recommend_percent,source_type,verification_status)
select
  md5('teacher-plus:demo-teacher:' || region || ':' || slot)::uuid,
  md5('teacher-plus:demo-school:' || region)::uuid,
  teacher_name,
  subject,
  category,
  left(split_part(teacher_name,' ',1),1) || left(split_part(teacher_name,' ',2),1),
  'Демонстрационный профиль для проверки каталога ' || region || '.',
  (4.1 + ((n + slot) % 9) / 10.0)::numeric(2,1),
  8 + ((n * (slot + 2)) % 53),
  82 + ((n + slot * 3) % 18),
  'community',
  'community'
from prepared
on conflict(id) do update set
  school_id=excluded.school_id,
  name=excluded.name,
  subject=excluded.subject,
  category=excluded.category,
  initials=excluded.initials,
  bio=excluded.bio,
  rating=excluded.rating,
  review_count=excluded.review_count,
  recommend_percent=excluded.recommend_percent,
  source_type='community',
  verification_status='community';

grant usage on schema public to anon, authenticated;
grant select on public.schools, public.teachers, public.reviews, public.review_votes to anon, authenticated;
grant insert, update on public.reviews, public.review_votes to authenticated;
