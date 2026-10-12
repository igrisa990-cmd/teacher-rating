-- Reversible archive: original rows and user data are retained.
begin;
alter table public.schools add column archived_at timestamptz;
alter table public.schools add column archive_reason text;
update public.schools set archived_at=now(),archive_reason=case when name ilike '%демо%' then 'explicit_demo_seed' else 'legacy_unverified_seed' end where registry_ogrn is null and verified_at is null and source_url is null and (name ilike '%демо%' or (country_code='LV' and source_type='official'));
create policy schools_active_catalog on public.schools as restrictive for all to anon,authenticated using (archived_at is null) with check (archived_at is null);
create policy active_school_catalog on public.teachers as restrictive for all to anon,authenticated using (exists(select 1 from public.schools s where s.id=teachers.school_id and s.archived_at is null)) with check (exists(select 1 from public.schools s where s.id=teachers.school_id and s.archived_at is null));
create policy active_school_catalog on public.school_directors as restrictive for all to anon,authenticated using (exists(select 1 from public.schools s where s.id=school_directors.school_id and s.archived_at is null)) with check (exists(select 1 from public.schools s where s.id=school_directors.school_id and s.archived_at is null));
create policy active_school_catalog on public.school_reviews as restrictive for all to anon,authenticated using (exists(select 1 from public.schools s where s.id=school_reviews.school_id and s.archived_at is null)) with check (exists(select 1 from public.schools s where s.id=school_reviews.school_id and s.archived_at is null));
create policy active_school_catalog on public.director_reviews as restrictive for all to anon,authenticated using (exists(select 1 from public.schools s where s.id=director_reviews.school_id and s.archived_at is null)) with check (exists(select 1 from public.schools s where s.id=director_reviews.school_id and s.archived_at is null));
create policy active_school_catalog on public.school_comments as restrictive for all to anon,authenticated using (exists(select 1 from public.schools s where s.id=school_comments.school_id and s.archived_at is null)) with check (exists(select 1 from public.schools s where s.id=school_comments.school_id and s.archived_at is null));
create policy active_school_catalog on public.school_classes as restrictive for all to anon,authenticated using (exists(select 1 from public.schools s where s.id=school_classes.school_id and s.archived_at is null)) with check (exists(select 1 from public.schools s where s.id=school_classes.school_id and s.archived_at is null));
create policy active_school_catalog on public.school_polls as restrictive for all to anon,authenticated using (exists(select 1 from public.schools s where s.id=school_polls.school_id and s.archived_at is null)) with check (exists(select 1 from public.schools s where s.id=school_polls.school_id and s.archived_at is null));
create policy active_school_catalog on public.school_messages as restrictive for all to anon,authenticated using (exists(select 1 from public.schools s where s.id=school_messages.school_id and s.archived_at is null)) with check (exists(select 1 from public.schools s where s.id=school_messages.school_id and s.archived_at is null));
create policy active_school_catalog on public.school_reels as restrictive for all to anon,authenticated using (exists(select 1 from public.schools s where s.id=school_reels.school_id and s.archived_at is null)) with check (exists(select 1 from public.schools s where s.id=school_reels.school_id and s.archived_at is null));
create policy active_parent_catalog on public.reviews as restrictive for all to anon,authenticated using (exists(select 1 from public.teachers p where p.id=reviews.teacher_id)) with check (exists(select 1 from public.teachers p where p.id=reviews.teacher_id));
create policy active_parent_catalog on public.favorites as restrictive for all to anon,authenticated using (exists(select 1 from public.teachers p where p.id=favorites.teacher_id)) with check (exists(select 1 from public.teachers p where p.id=favorites.teacher_id));
create policy active_parent_catalog on public.review_votes as restrictive for all to anon,authenticated using (exists(select 1 from public.reviews p where p.id=review_votes.review_id)) with check (exists(select 1 from public.reviews p where p.id=review_votes.review_id));
create policy active_parent_catalog on public.school_poll_votes as restrictive for all to anon,authenticated using (exists(select 1 from public.school_polls p where p.id=school_poll_votes.poll_id)) with check (exists(select 1 from public.school_polls p where p.id=school_poll_votes.poll_id));
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
create function private.has_verified_account() returns boolean language sql stable security definer set search_path=pg_catalog as $$ select exists(select 1 from auth.users u where u.id=(select auth.uid()) and not coalesce(u.is_anonymous,false) and ((u.phone is not null and u.phone_confirmed_at is not null) or (u.email is not null and u.email_confirmed_at is not null))); $$;
revoke all on function private.has_verified_account() from public,anon;
grant execute on function private.has_verified_account() to authenticated,service_role;
create policy verified_account_insert on public.reviews as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.reviews as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.review_votes as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.review_votes as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.school_reviews as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.school_reviews as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.director_reviews as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.director_reviews as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.school_comments as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.school_comments as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.school_messages as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.school_messages as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.school_reels as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.school_reels as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.school_classes as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.school_classes as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.school_polls as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.school_polls as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.regional_chat_messages as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.regional_chat_messages as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.teacher_requests as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.teacher_requests as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.catalog_requests as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.catalog_requests as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
create policy verified_account_insert on public.favorites as restrictive for insert to authenticated with check ((select private.has_verified_account()));
create policy verified_account_update on public.favorites as restrictive for update to authenticated using ((select private.has_verified_account())) with check ((select private.has_verified_account()));
CREATE OR REPLACE FUNCTION public.cast_school_vote(target_poll uuid, chosen_option integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare poll public.school_polls;
begin
 if not private.has_verified_account() then raise exception 'Sign in required'; end if;
 select * into poll from public.school_polls where id=target_poll and exists(select 1 from public.schools s where s.id=school_id and s.archived_at is null) for share;
 if not found then raise exception 'Poll not found'; end if;
 if poll.ends_at is not null and poll.ends_at<=now() then raise exception 'Poll is closed'; end if;
 if chosen_option is null or chosen_option<0 or chosen_option>=jsonb_array_length(poll.options) then raise exception 'Invalid option'; end if;
 insert into public.school_poll_votes(poll_id,user_id,option_index) values(target_poll,auth.uid(),chosen_option)
 on conflict(poll_id,user_id) do update set option_index=excluded.option_index;
end $function$
;
CREATE OR REPLACE FUNCTION public.catalog_existing(p_kind text, p_school uuid, p_region text, p_city text, p_school_name text, p_name text, p_subject text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid uuid; rid uuid;
begin
 sid:=p_school;
 if sid is not null and not exists(select 1 from schools where id=sid and archived_at is null) then return null;end if;
 if sid is null then select id into sid from schools where archived_at is null and catalog_normalize(region)=catalog_normalize(p_region)
 and catalog_normalize(city)=catalog_normalize(p_city) and catalog_normalize(name)=catalog_normalize(p_school_name) limit 1;end if;
 if p_kind='school' then return sid;end if;
 if p_kind='teacher' then select id into rid from teachers where school_id=sid and catalog_normalize(name)=catalog_normalize(p_name) and catalog_normalize(subject)=catalog_normalize(p_subject) limit 1;
 else select id into rid from school_directors where school_id=sid and catalog_normalize(name)=catalog_normalize(p_name);end if;
 return rid;
end;$function$
;
CREATE OR REPLACE FUNCTION public.catalog_finish(p_request_id uuid, p_outcome text, p_method text, p_note text, p_evidence jsonb DEFAULT '{}'::jsonb)
 RETURNS catalog_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 if sid is not null and not exists(select 1 from schools where id=sid and archived_at is null) then raise exception 'Школа архивирована';end if;
 if sid is null then select id into sid from schools where archived_at is null and catalog_normalize(region)=catalog_normalize(r.region) and catalog_normalize(city)=catalog_normalize(r.city) and catalog_normalize(name)=catalog_normalize(r.school_name) limit 1;end if;
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
end;$function$
;
CREATE OR REPLACE FUNCTION public.director_review_mine(target_school uuid)
 RETURNS TABLE(director_name text, rating numeric, leadership numeric, fairness numeric, communication numeric, safety numeric, comment text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
select r.director_name,r.rating,r.leadership,r.fairness,r.communication,r.safety,r.comment from public.director_reviews r where r.school_id=target_school and exists(select 1 from public.schools s where s.id=r.school_id and s.archived_at is null) and r.user_id=auth.uid();
$function$
;
CREATE OR REPLACE FUNCTION public.school_poll_results(target_school uuid)
 RETURNS TABLE(poll_id uuid, option_index integer, vote_count bigint, is_mine boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 select v.poll_id,v.option_index,count(*),bool_or(v.user_id=auth.uid())
 from public.school_poll_votes v join public.school_polls p on p.id=v.poll_id
 where p.school_id=target_school and exists(select 1 from public.schools s where s.id=p.school_id and s.archived_at is null) group by v.poll_id,v.option_index
$function$
;
CREATE OR REPLACE FUNCTION public.submit_catalog_request(p_kind text, p_school_id uuid, p_region text, p_city text, p_school_name text, p_address text, p_person_name text, p_subject text, p_source_url text)
 RETURNS catalog_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid:=auth.uid();f text;r catalog_requests;rid uuid;s schools;
begin
 if not private.has_verified_account() then raise exception 'Войдите в настоящий аккаунт';end if;
 if p_kind not in('school','teacher','director') then raise exception 'Неизвестный тип заявки';end if;
 if p_school_id is not null then
 select * into s from schools where id=p_school_id and archived_at is null;if not found then raise exception 'Школа не найдена';end if;
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
end;$function$
;
commit;
