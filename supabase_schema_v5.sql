create extension if not exists pgcrypto;

create table if not exists public.schools (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 city text,
 address text,
 created_at timestamptz not null default now()
);

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null default 'Ученик',
 role text not null default 'student' check (role in ('student','teacher','admin')),
 class_name text,
 school_id uuid references public.schools(id) on delete set null,
 created_at timestamptz not null default now()
);

create table if not exists public.teachers (
 id uuid primary key default gen_random_uuid(),
 school_id uuid references public.schools(id) on delete set null,
 name text not null,
 subject text not null,
 category text not null default 'all',
 initials text,
 bio text,
 rating numeric(2,1) not null default 0,
 review_count integer not null default 0,
 recommend_percent integer not null default 0,
 created_at timestamptz not null default now()
);

create table if not exists public.reviews (
 id uuid primary key default gen_random_uuid(),
 teacher_id uuid not null references public.teachers(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 rating integer not null check (rating between 1 and 5),
 explanation integer not null check (explanation between 1 and 5),
 fairness integer not null check (fairness between 1 and 5),
 atmosphere integer not null check (atmosphere between 1 and 5),
 comment text,
 created_at timestamptz not null default now(),
 unique(teacher_id,user_id)
);

alter table public.schools enable row level security;
alter table public.profiles enable row level security;
alter table public.teachers enable row level security;
alter table public.reviews enable row level security;

drop policy if exists schools_read on public.schools;
create policy schools_read on public.schools for select using (true);

drop policy if exists profiles_read_own on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_read_own on public.profiles for select using (auth.uid() = id);
create policy profiles_insert_own on public.profiles for insert with check (auth.uid() = id);
create policy profiles_update_own on public.profiles for update using (auth.uid() = id);

drop policy if exists teachers_read on public.teachers;
create policy teachers_read on public.teachers for select using (true);

drop policy if exists reviews_read on public.reviews;
drop policy if exists reviews_insert_own on public.reviews;
create policy reviews_read on public.reviews for select using (true);
create policy reviews_insert_own on public.reviews for insert with check (auth.uid() = user_id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.profiles(id,name,class_name,school_id)
 values(new.id,
        coalesce(new.raw_user_meta_data->>'name','Ученик'),
        new.raw_user_meta_data->>'class_name',
        nullif(new.raw_user_meta_data->>'school_id','')::uuid)
 on conflict (id) do nothing;
 return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.refresh_teacher_rating()
returns trigger language plpgsql security definer set search_path=public
as $$
declare tid uuid;
begin
 tid := coalesce(new.teacher_id,old.teacher_id);
 update public.teachers t set
   rating = coalesce((select round(avg(r.rating)::numeric,1) from public.reviews r where r.teacher_id=tid),0),
   review_count = (select count(*) from public.reviews r where r.teacher_id=tid),
   recommend_percent = coalesce((select round(100.0*avg(case when r.rating>=4 then 1 else 0 end))::integer from public.reviews r where r.teacher_id=tid),0)
 where t.id=tid;
 return coalesce(new,old);
end $$;

drop trigger if exists reviews_refresh_rating on public.reviews;
create trigger reviews_refresh_rating after insert or update or delete on public.reviews
for each row execute function public.refresh_teacher_rating();

insert into public.schools(name,city,address)
select * from (values
('Лицей №1','Рига','ул. Центральная, 1'),
('Гимназия «Новая волна»','Рига','ул. Школьная, 12'),
('Школа №8','Юрмала','ул. Морская, 8'),
('Гимназия №3','Рига','ул. Академическая, 20')
) v(name,city,address)
where not exists(select 1 from public.schools);
