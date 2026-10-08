-- Requires the existing Russia/catalog migrations. Identity requests do not create ratings.
begin;
create table if not exists public.catalog_moderators (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.catalog_moderators enable row level security;
revoke all on public.catalog_moderators from public,anon,authenticated;
grant select on public.catalog_moderators to authenticated;
drop policy if exists catalog_moderators_self on public.catalog_moderators;
create policy catalog_moderators_self on public.catalog_moderators for select to authenticated using(user_id=auth.uid());
-- Membership can only be assigned by the project owner/service; client profile fields are not trusted.
create or replace function public.is_catalog_moderator() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.catalog_moderators where user_id=auth.uid());
$$;
revoke all on function public.is_catalog_moderator() from public;
grant execute on function public.is_catalog_moderator() to authenticated;

create table if not exists public.school_directors (
 id uuid primary key default gen_random_uuid(), school_id uuid not null unique references public.schools(id) on delete cascade,
 name text not null check(length(trim(name)) between 3 and 200), source_url text, source_type text not null,
 verified_at timestamptz not null default now(),created_at timestamptz not null default now()
);
alter table public.school_directors enable row level security;
revoke all on public.school_directors from anon,authenticated;
grant select on public.school_directors to anon,authenticated;
drop policy if exists school_directors_read on public.school_directors;
create policy school_directors_read on public.school_directors for select using(true);

create table if not exists public.catalog_requests (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in('school','teacher','director')),school_id uuid references public.schools(id) on delete set null,
 region text not null check(length(trim(region)) between 2 and 120),city text not null check(length(trim(city)) between 1 and 160),
 school_name text not null check(length(trim(school_name)) between 2 and 240),address text check(length(address)<=400),
 person_name text check(length(person_name)<=200),subject text check(length(subject)<=120),source_url text check(length(source_url)<=2048),
 status text not null default 'queued' check(status in('queued','needs_review','published','rejected','duplicate')),
 verification_method text,verification_note text,record_id uuid,fingerprint text not null,
 created_at timestamptz not null default now(),checked_at timestamptz,
 unique(user_id,fingerprint),
 check(kind='school' or (person_name is not null and length(trim(person_name))>=3)),check(kind<>'teacher' or (subject is not null and length(trim(subject))>=2))
);
create index if not exists catalog_requests_queue on public.catalog_requests(status,created_at);
alter table public.catalog_requests enable row level security;
revoke all on public.catalog_requests from public,anon,authenticated;
grant select on public.catalog_requests to authenticated;
drop policy if exists catalog_requests_read on public.catalog_requests;
create policy catalog_requests_read on public.catalog_requests for select to authenticated using(user_id=auth.uid() or public.is_catalog_moderator());
create table if not exists public.catalog_decisions (
 id uuid primary key default gen_random_uuid(),request_id uuid not null references public.catalog_requests(id),actor_id uuid,
 action text not null,method text not null,note text not null,evidence jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()
);
alter table public.catalog_decisions enable row level security;
revoke all on public.catalog_decisions from public,anon,authenticated;
grant select on public.catalog_decisions to authenticated;
drop policy if exists catalog_decisions_moderator on public.catalog_decisions;
create policy catalog_decisions_moderator on public.catalog_decisions for select to authenticated using(public.is_catalog_moderator());

create or replace function public.catalog_normalize(value text) returns text language sql immutable as $$
 select trim(regexp_replace(replace(lower(coalesce(value,'')),'ё','е'),'[^[:alnum:]]+',' ','g'));
$$;
create or replace function public.catalog_existing(p_kind text,p_school uuid,p_region text,p_city text,p_school_name text,p_name text,p_subject text)
returns uuid language plpgsql stable security definer set search_path=public as $$
declare sid uuid; rid uuid;
begin
 sid:=p_school;
 if sid is null then select id into sid from schools where catalog_normalize(region)=catalog_normalize(p_region)
 and catalog_normalize(city)=catalog_normalize(p_city) and catalog_normalize(name)=catalog_normalize(p_school_name) limit 1;end if;
 if p_kind='school' then return sid;end if;
 if p_kind='teacher' then select id into rid from teachers where school_id=sid and catalog_normalize(name)=catalog_normalize(p_name) and catalog_normalize(subject)=catalog_normalize(p_subject) limit 1;
 else select id into rid from school_directors where school_id=sid and catalog_normalize(name)=catalog_normalize(p_name);end if;
 return rid;
end;$$;
revoke all on function public.catalog_existing(text,uuid,text,text,text,text,text) from public,anon,authenticated;

create or replace function public.submit_catalog_request(p_kind text,p_school_id uuid,p_region text,p_city text,p_school_name text,p_address text,p_person_name text,p_subject text,p_source_url text)
returns public.catalog_requests language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();f text;r catalog_requests;rid uuid;s schools;
begin
 if uid is null then raise exception 'Войдите в настоящий аккаунт';end if;
 if p_kind not in('school','teacher','director') then raise exception 'Неизвестный тип заявки';end if;
 if p_school_id is not null then
 select * into s from schools where id=p_school_id;if not found then raise exception 'Школа не найдена';end if;
 p_region:=s.region;p_city:=s.city;p_school_name:=s.name;
 end if;
 if p_kind<>'school' and (p_person_name is null or trim(p_person_name)!~'^[[:alpha:]][[:alpha:] .''-]+[[:space:]][[:alpha:]][[:alpha:] .''-]+$') then raise exception 'Укажите полное имя и фамилию';end if;
 if p_source_url is not null and p_source_url !~'^https://[^[:space:]]+$' then raise exception 'Укажите HTTPS-ссылку';end if;
 f:=md5(concat_ws('|',p_kind,coalesce(p_school_id::text,catalog_normalize(p_region)||'|'||catalog_normalize(p_city)||'|'||catalog_normalize(p_school_name)),catalog_normalize(p_person_name),catalog_normalize(p_subject)));
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 select * into r from catalog_requests where user_id=uid and fingerprint=f;if found then return r;end if;
 if (select count(*) from catalog_requests where user_id=uid and created_at>now()-interval '1 day')>=10 then raise exception 'Лимит: 10 заявок в сутки';end if;
 rid:=catalog_existing(p_kind,p_school_id,p_region,p_city,p_school_name,p_person_name,p_subject);
 insert into catalog_requests(user_id,kind,school_id,region,city,school_name,address,person_name,subject,source_url,fingerprint,status,record_id,verification_method,verification_note)
 values(uid,p_kind,p_school_id,trim(p_region),trim(p_city),trim(p_school_name),nullif(trim(p_address),''),nullif(trim(p_person_name),''),nullif(trim(p_subject),''),nullif(trim(p_source_url),''),f,
 case when rid is null then 'queued' else 'duplicate' end,rid,case when rid is null then null else 'internal_catalog' end,
 case when rid is null then 'Ожидает проверки источника' else 'Профиль уже существует' end) returning * into r;
 return r;
end;$$;
revoke all on function public.submit_catalog_request(text,uuid,text,text,text,text,text,text,text) from public;
grant execute on function public.submit_catalog_request(text,uuid,text,text,text,text,text,text,text) to authenticated;

-- Internal publisher: only checked service outcomes or an authorized moderator may call it.
create or replace function public.catalog_finish(p_request_id uuid,p_outcome text,p_method text,p_note text,p_evidence jsonb default '{}'::jsonb)
returns public.catalog_requests language plpgsql security definer set search_path=public as $$
declare r catalog_requests;sid uuid;rid uuid;origin_type text;
begin
 select * into r from catalog_requests where id=p_request_id for update;if not found then raise exception 'Заявка не найдена';end if;
 if r.status in('published','duplicate','rejected') then return r;end if;
 if p_outcome not in('verified','needs_review','rejected') then raise exception 'Неизвестный результат';end if;
 if p_outcome='verified' then
 if p_method<>'manual' and p_evidence->>'url' is not null then r.source_url:=p_evidence->>'url';end if;
 perform pg_advisory_xact_lock(hashtextextended(catalog_normalize(r.region)||'|'||catalog_normalize(r.city)||'|'||catalog_normalize(r.school_name),0));
 rid:=catalog_existing(r.kind,r.school_id,r.region,r.city,r.school_name,r.person_name,r.subject);
 if rid is not null then r.status:='duplicate';r.record_id:=rid;
 else
 sid:=r.school_id;
 if sid is null then select id into sid from schools where catalog_normalize(region)=catalog_normalize(r.region) and catalog_normalize(city)=catalog_normalize(r.city) and catalog_normalize(name)=catalog_normalize(r.school_name) limit 1;end if;
 origin_type:=case when p_method='manual' then 'moderated' else 'official' end;
 -- A teacher/director cannot implicitly publish a new school via machine verification.
 if sid is null and r.kind<>'school' and p_method<>'manual' then raise exception 'Сначала подтвердите школу';end if;
 if sid is null then insert into schools(name,city,region,address,country_code,source_type,source_url,verified_at) values(r.school_name,r.city,r.region,r.address,'RU',origin_type,r.source_url,now()) returning id into sid;end if;
 if r.kind='school' then rid:=sid;
 elsif r.kind='teacher' then
 insert into teachers(school_id,name,subject,category,initials,bio,rating,review_count,recommend_percent,source_type,source_url,verified_at,verification_status,verification_method,verification_confidence,verification_checked_at)
 values(sid,r.person_name,r.subject,'community',upper(left(r.person_name,1)),'Профессиональные сведения проверены.',0,0,0,origin_type,r.source_url,now(),'verified',p_method,case when p_method='manual' then null else .95 end,now()) returning id into rid;
 else
 if exists(select 1 from school_directors where school_id=sid) then
 if p_method<>'manual' then raise exception 'Смена директора требует модерации';end if;
 update school_directors set name=r.person_name,source_url=r.source_url,source_type=origin_type,verified_at=now() where school_id=sid returning id into rid;
 else insert into school_directors(school_id,name,source_url,source_type) values(sid,r.person_name,r.source_url,origin_type) returning id into rid;end if;
 end if;
 r.status:='published';r.record_id:=rid;r.school_id:=sid;
 end if;
 else r.status:=p_outcome;end if;
 update catalog_requests set status=r.status,school_id=r.school_id,record_id=r.record_id,source_url=r.source_url,verification_method=p_method,verification_note=left(p_note,500),checked_at=now() where id=r.id returning * into r;
 insert into catalog_decisions(request_id,actor_id,action,method,note,evidence) values(r.id,auth.uid(),r.status,p_method,left(p_note,500),coalesce(p_evidence,'{}'::jsonb));
 return r;
end;$$;
revoke all on function public.catalog_finish(uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.catalog_finish(uuid,text,text,text,jsonb) to service_role;

create or replace function public.queue_catalog_review(p_request_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 update catalog_requests set status='needs_review',verification_method='manual',verification_note='Автоматическая проверка недоступна. Ожидает модератора.' where id=p_request_id and user_id=auth.uid() and status='queued';
end;$$;
revoke all on function public.queue_catalog_review(uuid) from public;
grant execute on function public.queue_catalog_review(uuid) to authenticated;
create or replace function public.moderate_catalog_request(p_request_id uuid,p_action text,p_note text) returns public.catalog_requests language plpgsql security definer set search_path=public as $$
begin
 if not is_catalog_moderator() then raise exception 'Доступ только для модератора';end if;
 if p_action not in('verified','rejected') or length(trim(coalesce(p_note,'')))<10 then raise exception 'Укажите решение и основание, минимум 10 символов';end if;
 return catalog_finish(p_request_id,p_action,'manual',trim(p_note),'{}'::jsonb);
end;$$;
revoke all on function public.moderate_catalog_request(uuid,text,text) from public;
grant execute on function public.moderate_catalog_request(uuid,text,text) to authenticated;

-- Five matching submissions are evidence for the queue, not permission to publish a person.
drop trigger if exists publish_teacher_after_five_requests on public.teacher_requests;
revoke execute on function public.finalize_teacher_verification(uuid,text,text,numeric,jsonb) from service_role;
insert into catalog_requests(id,user_id,kind,school_id,region,city,school_name,person_name,subject,source_url,status,fingerprint,verification_method,verification_note,created_at)
select id,user_id,'teacher',school_id,region,city,school_name,teacher_name,subject,source_url,'needs_review',
 md5('legacy|'||candidate_key),'manual','Перенесено из прежней очереди. Требуется проверка.',created_at from teacher_requests where status='pending' on conflict do nothing;
commit;
