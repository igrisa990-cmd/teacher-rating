-- Учитель+ — автоматическая проверка учителей и расширенная оценка с шагом 0,5.
-- Применять после 20260918_russia_regions_and_requests.sql.

alter table public.teachers add column if not exists verification_status text not null default 'pending';
alter table public.teachers add column if not exists verification_method text;
alter table public.teachers add column if not exists verification_confidence numeric(4,3);
alter table public.teachers add column if not exists verification_checked_at timestamptz;

alter table public.teacher_requests add column if not exists verification_status text not null default 'queued';
alter table public.teacher_requests add column if not exists verification_method text;
alter table public.teacher_requests add column if not exists verification_confidence numeric(4,3);
alter table public.teacher_requests add column if not exists verification_checked_at timestamptz;
alter table public.teacher_requests drop constraint if exists teacher_requests_rating_check;
alter table public.teacher_requests drop constraint if exists teacher_requests_rating_half_step;
alter table public.teacher_requests alter column rating type numeric(2,1) using rating::numeric(2,1);
alter table public.teacher_requests add constraint teacher_requests_rating_half_step
  check (rating between 1 and 5 and mod(rating * 10, 5) = 0);
grant select (verification_status, verification_method, verification_confidence, verification_checked_at)
  on public.teacher_requests to anon, authenticated;

alter table public.reviews drop constraint if exists reviews_rating_check;
alter table public.reviews drop constraint if exists reviews_explanation_check;
alter table public.reviews drop constraint if exists reviews_fairness_check;
alter table public.reviews drop constraint if exists reviews_atmosphere_check;
alter table public.reviews alter column rating type numeric(2,1) using rating::numeric(2,1);
alter table public.reviews alter column explanation type numeric(2,1) using explanation::numeric(2,1);
alter table public.reviews alter column fairness type numeric(2,1) using fairness::numeric(2,1);
alter table public.reviews alter column atmosphere type numeric(2,1) using atmosphere::numeric(2,1);
alter table public.reviews add column if not exists engagement numeric(2,1) default 5;
alter table public.reviews add column if not exists respect numeric(2,1) default 5;
alter table public.reviews add column if not exists feedback numeric(2,1) default 5;
alter table public.reviews add column if not exists workload numeric(2,1) default 5;
alter table public.reviews add column if not exists exam_prep numeric(2,1) default 5;

alter table public.reviews drop constraint if exists reviews_rating_half_step;
alter table public.reviews drop constraint if exists reviews_explanation_half_step;
alter table public.reviews drop constraint if exists reviews_fairness_half_step;
alter table public.reviews drop constraint if exists reviews_atmosphere_half_step;
alter table public.reviews drop constraint if exists reviews_more_criteria_half_step;
alter table public.reviews add constraint reviews_rating_half_step
  check (rating between 1 and 5 and mod(rating * 10, 5) = 0);
alter table public.reviews add constraint reviews_explanation_half_step
  check (explanation between 1 and 5 and mod(explanation * 10, 5) = 0);
alter table public.reviews add constraint reviews_fairness_half_step
  check (fairness between 1 and 5 and mod(fairness * 10, 5) = 0);
alter table public.reviews add constraint reviews_atmosphere_half_step
  check (atmosphere between 1 and 5 and mod(atmosphere * 10, 5) = 0);
alter table public.reviews add constraint reviews_more_criteria_half_step
  check (
    engagement between 1 and 5 and mod(engagement * 10, 5) = 0 and
    respect between 1 and 5 and mod(respect * 10, 5) = 0 and
    feedback between 1 and 5 and mod(feedback * 10, 5) = 0 and
    workload between 1 and 5 and mod(workload * 10, 5) = 0 and
    exam_prep between 1 and 5 and mod(exam_prep * 10, 5) = 0
  );

create table if not exists public.teacher_verification_checks (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.teacher_requests(id) on delete cascade,
  outcome text not null check (outcome in ('verified','rejected','needs_review')),
  method text not null check (method in ('internal_database','official_school_page','external_registry','community','manual')),
  confidence numeric(4,3) not null check (confidence between 0 and 1),
  evidence jsonb not null default '{}'::jsonb,
  checked_at timestamptz not null default now()
);

create index if not exists teacher_verification_checks_request_idx
  on public.teacher_verification_checks(request_id, checked_at desc);

alter table public.teacher_verification_checks enable row level security;
drop policy if exists teacher_verification_checks_public_read on public.teacher_verification_checks;
create policy teacher_verification_checks_public_read
  on public.teacher_verification_checks for select using (true);
revoke all on public.teacher_verification_checks from anon, authenticated;
grant select (request_id, outcome, method, confidence, checked_at)
  on public.teacher_verification_checks to anon, authenticated;

-- Вызывается только Edge Function под service_role.
create or replace function public.finalize_teacher_verification(
  p_request_id uuid,
  p_outcome text,
  p_method text,
  p_confidence numeric,
  p_evidence jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  req public.teacher_requests%rowtype;
  target_school_id uuid;
  target_teacher_id uuid;
begin
  if p_outcome not in ('verified','rejected','needs_review') then
    raise exception 'invalid verification outcome';
  end if;

  select * into req from public.teacher_requests where id = p_request_id for update;
  if not found then raise exception 'teacher request not found'; end if;

  insert into public.teacher_verification_checks(request_id,outcome,method,confidence,evidence)
  values (p_request_id,p_outcome,p_method,least(1,greatest(0,p_confidence)),coalesce(p_evidence,'{}'::jsonb));

  update public.teacher_requests
  set verification_status=p_outcome, verification_method=p_method,
      verification_confidence=least(1,greatest(0,p_confidence)), verification_checked_at=now()
  where id=p_request_id;

  if p_outcome = 'rejected' then
    update public.teacher_requests set status='rejected' where id=p_request_id;
    return null;
  elsif p_outcome = 'needs_review' then
    return null;
  end if;

  target_school_id := req.school_id;
  if target_school_id is null then
    select id into target_school_id from public.schools
    where lower(trim(name))=lower(trim(req.school_name))
      and lower(trim(city))=lower(trim(req.city))
      and lower(trim(coalesce(region,'')))=lower(trim(req.region)) limit 1;
  end if;
  if target_school_id is null then
    insert into public.schools(name,city,region,country_code,source_type,source_url,verified_at)
    values(trim(req.school_name),trim(req.city),trim(req.region),'RU','official',req.source_url,now())
    returning id into target_school_id;
  end if;

  select id into target_teacher_id from public.teachers
  where school_id=target_school_id and lower(trim(name))=lower(trim(req.teacher_name))
    and lower(trim(subject))=lower(trim(req.subject)) limit 1;
  if target_teacher_id is null then
    insert into public.teachers(
      school_id,name,subject,category,initials,bio,rating,review_count,recommend_percent,
      source_type,source_url,verified_at,verification_status,verification_method,
      verification_confidence,verification_checked_at
    ) values (
      target_school_id,trim(req.teacher_name),trim(req.subject),'community',upper(left(trim(req.teacher_name),1)),
      coalesce(nullif(trim(req.teacher_bio),''),'Профиль подтверждён автоматической проверкой.'),
      req.rating,1,case when req.rating>=4 then 100 else 0 end,
      'official',req.source_url,now(),'verified',p_method,p_confidence,now()
    ) returning id into target_teacher_id;
  else
    update public.teachers set verification_status='verified',verification_method=p_method,
      verification_confidence=p_confidence,verification_checked_at=now(),verified_at=now()
    where id=target_teacher_id;
  end if;

  update public.teacher_requests set status='published',published_teacher_id=target_teacher_id
  where candidate_key=req.candidate_key and status='pending';
  return target_teacher_id;
end;
$$;

revoke all on function public.finalize_teacher_verification(uuid,text,text,numeric,jsonb) from public, anon, authenticated;
grant execute on function public.finalize_teacher_verification(uuid,text,text,numeric,jsonb) to service_role;

-- Пять независимых заявок остаются резервным способом для мест без цифровых источников.
create or replace function public.mark_community_verified_teacher()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='published' and old.status is distinct from new.status and new.published_teacher_id is not null then
    update public.teachers set
      verification_status=case when verification_status='verified' then verification_status else 'community_verified' end,
      verification_method=coalesce(verification_method,'community'),
      verification_confidence=coalesce(verification_confidence,0.700),
      verification_checked_at=coalesce(verification_checked_at,now())
    where id=new.published_teacher_id;
    update public.teacher_requests set verification_status='verified',verification_method='community',
      verification_confidence=0.700,verification_checked_at=now()
    where id=new.id and verification_status='queued';
  end if;
  return new;
end;
$$;

drop trigger if exists mark_community_verified_teacher on public.teacher_requests;
create trigger mark_community_verified_teacher after update of status on public.teacher_requests
for each row execute function public.mark_community_verified_teacher();
