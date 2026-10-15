-- Run after the migration inside BEGIN ... ROLLBACK. Fixtures never commit.
insert into public.schools(id,name,city,region,country_code,source_type) values
 ('99999999-0000-4000-8000-000000000001','Поисковая школа 12','Тестовый город','Тестовый регион поиска','RU','community'),
 ('99999999-0000-4000-8000-000000000002','Поисковая школа 123','Другой город','Другой регион поиска','RU','community'),
 ('99999999-0000-4000-8000-000000000003','Поисковая архивная школа','Тестовый город','Тестовый регион поиска','RU','community');
update public.schools set archived_at=now() where id='99999999-0000-4000-8000-000000000003';
insert into public.teachers(id,school_id,name,subject,source_type) values
 ('99999999-0000-4000-8000-000000000011','99999999-0000-4000-8000-000000000001','Фадеева Алёна Петровна','Математика','community'),
 ('99999999-0000-4000-8000-000000000012','99999999-0000-4000-8000-000000000002','Фадеева Елена Петровна','Химия','community'),
 ('99999999-0000-4000-8000-000000000013','99999999-0000-4000-8000-000000000003','Фадеева Ирина Петровна','Математика','community'),
 ('99999999-0000-4000-8000-000000000014','99999999-0000-4000-8000-000000000001','Алексеев Евгений Фадеевич','Биология','community');
insert into public.teachers(school_id,name,subject,source_type)
 select '99999999-0000-4000-8000-000000000001','Поискова Мария '||chr(1040+g),'География','community' from generate_series(1,35)g;
set local role anon;
do $$
declare upper_case jsonb;lower_case jsonb;hits jsonb;first_page jsonb;second_page jsonb;
begin
 upper_case:=public.search_catalog('ФАДЕЕВА','teachers','Тестовый регион поиска','',0);
 lower_case:=public.search_catalog('фадеева','teachers','Тестовый регион поиска','',0);
 assert upper_case=lower_case,'Russian search must ignore case';
 assert upper_case->0->'record'->>'id'='99999999-0000-4000-8000-000000000011','Exact match must come first';
 assert public.search_catalog('фад','teachers','Тестовый регион поиска','',0)->0->'record'->>'id'='99999999-0000-4000-8000-000000000011','Surname prefix';
 assert public.search_catalog('  Фадеева,  Алена  ','teachers','Тестовый регион поиска','',0)->0->'record'->>'id'='99999999-0000-4000-8000-000000000011','Whitespace, punctuation and yo';
 hits:=public.search_catalog('фадеевва','teachers','Тестовый регион поиска','',0);
 assert hits->0->'record'->>'id'='99999999-0000-4000-8000-000000000011','Repeated-letter typo';
 assert hits->0->>'match_type'='similar','Approximate match must be identified';
 assert public.search_catalog('фаедеева','teachers','Тестовый регион поиска','',0)->0->'record'->>'id'='99999999-0000-4000-8000-000000000011','Transposed-letter typo';
 assert public.search_catalog('фадеевва математ','teachers','Тестовый регион поиска','',0)->0->'record'->>'id'='99999999-0000-4000-8000-000000000011','Every term must match, including a subject prefix';
 assert jsonb_array_length(public.search_catalog('фадеевва хим','teachers','Тестовый регион поиска','',0))=0,'Do not ignore a non-matching query term';
 assert jsonb_array_length(public.search_catalog('фадеевва','teachers','Тестовый регион поиска','Другой город',0))=0,'City must constrain fuzzy matches';
 assert public.search_catalog('фадеевва','teachers','Другой регион поиска','',0)->0->'record'->>'id'='99999999-0000-4000-8000-000000000012','Region must constrain fuzzy matches';
 assert jsonb_array_length(public.search_catalog('Фадеева Ирина','teachers','Тестовый регион поиска','',0))=0,'Archived school staff must remain hidden';
 hits:=public.search_catalog('школа 12','schools','Тестовый регион поиска','',0);
 assert jsonb_array_length(hits)=1 and hits->0->'record'->>'id'='99999999-0000-4000-8000-000000000001','School numbers must match exactly';
 first_page:=public.search_catalog('Поисковва географ','teachers','Тестовый регион поиска','',0);
 second_page:=public.search_catalog('Поисковва географ','teachers','Тестовый регион поиска','',20);
 assert jsonb_array_length(first_page)=21 and jsonb_array_length(second_page)=15,'Fuzzy pagination must cover the result set';
 assert not exists(select 1 from jsonb_array_elements(first_page)with ordinality a(value,n) join jsonb_array_elements(second_page)b(value) on a.value->'record'->>'id'=b.value->'record'->>'id' where a.n<=20),'Pages must not duplicate records';
 assert public.search_catalog('Поисковва географ','teachers','Тестовый регион поиска','',20)=second_page,'Stable pagination';
end;$$;
reset role;
select 'PASS: anon case, prefix, punctuation, yo, typos, all terms, kind/region/city, archive RLS and pagination' as verification;
