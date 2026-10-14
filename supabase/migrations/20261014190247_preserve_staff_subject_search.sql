-- Recompute only a generated vector; user data and source evidence stay intact.
drop index public.teachers_staff_search_idx;
alter table public.teachers drop column staff_search_document;
alter table public.teachers add column staff_search_document tsvector generated always as(to_tsvector('simple'::regconfig,replace(lower(coalesce(name,'')||' '||coalesce(subject,'')||' '||coalesce(staff_subject,'')),'ё','е'))) stored;
create index teachers_staff_search_idx on public.teachers using gin(staff_search_document);
