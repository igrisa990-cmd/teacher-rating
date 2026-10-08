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

