begin;
alter table public.catalog_requests add column draft_rating integer check(draft_rating between 1 and 5),add column draft_comment text not null default '' check(length(draft_comment)<=2000),add column rating_result text check(rating_result in('published','existing_preserved','account_unavailable'));
CREATE OR REPLACE FUNCTION public.submit_catalog_entry(p_kind text, p_school_id uuid, p_region text, p_city text, p_school_name text, p_address text, p_person_name text, p_subject text, p_source_url text, p_rating integer, p_comment text)
 RETURNS catalog_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid:=auth.uid();f text;r catalog_requests;rid uuid;s schools;
begin
 if not private.has_verified_account() then raise exception 'Войдите в настоящий аккаунт';end if;
 if p_kind not in('school','teacher') then raise exception 'Неизвестный тип заявки';end if;
 if p_rating is null or p_rating not between 1 and 5 then raise exception 'Выберите оценку от 1 до 5';end if;
 if length(coalesce(p_comment,''))>2000 then raise exception 'Отзыв слишком длинный';end if;
 if p_kind='teacher' and p_school_id is null then raise exception 'Сначала выберите школу из каталога';end if;
 if p_kind='school' and length(trim(coalesce(p_address,'')))<5 then raise exception 'Укажите адрес школы';end if;
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
 insert into catalog_requests(user_id,kind,school_id,region,city,school_name,address,person_name,subject,source_url,fingerprint,status,record_id,verification_method,verification_note,draft_rating,draft_comment)
 values(uid,p_kind,p_school_id,trim(p_region),trim(p_city),trim(p_school_name),nullif(trim(p_address),''),nullif(trim(p_person_name),''),nullif(trim(p_subject),''),nullif(trim(p_source_url),''),f,
 'needs_review',rid,null,'Название, адрес и оценка ожидают модерации',p_rating,trim(coalesce(p_comment,''))) returning * into r;
 return r;
end;$function$
;

revoke all on function public.submit_catalog_entry(text,uuid,text,text,text,text,text,text,text,integer,text) from public,anon;
grant execute on function public.submit_catalog_entry(text,uuid,text,text,text,text,text,text,text,integer,text) to authenticated;
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
 if r.draft_rating is not null and p_outcome='verified' and (p_method<>'manual' or not public.is_catalog_moderator()) then p_outcome:='needs_review';end if;
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
 if p_outcome='verified' and r.status in('published','duplicate') and r.draft_rating is not null and r.rating_result is null then
 if not exists(select 1 from auth.users u where u.id=r.user_id and not coalesce(u.is_anonymous,false) and (u.phone_confirmed_at is not null or u.email_confirmed_at is not null)) then
 update catalog_requests set rating_result='account_unavailable' where id=r.id;
 else
 if r.kind='school' then
 insert into school_reviews(school_id,user_id,rating,comment) values(r.record_id,r.user_id,r.draft_rating,r.draft_comment) on conflict(school_id,user_id) do nothing;
 elsif r.kind='teacher' then
 insert into reviews(teacher_id,user_id,rating,comment,explanation,fairness,atmosphere,engagement,respect,feedback,workload,exam_prep) values(r.record_id,r.user_id,r.draft_rating,r.draft_comment,null,null,null,null,null,null,null,null) on conflict(teacher_id,user_id) do nothing;
 end if;
 if found then update catalog_requests set rating_result='published' where id=r.id;
 else update catalog_requests set rating_result='existing_preserved' where id=r.id;end if;
 end if;
 select * into r from catalog_requests where id=r.id;
 end if;
 return r;
end;$function$
;

commit;
