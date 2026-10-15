-- Both IDs are non-null primary keys. IN and correlated EXISTS select the same
-- source-visible school IDs; the source query still runs with caller RLS.
alter policy source_school_visibility on catalog_spelling.school_documents
 using(id in(select s.id from public.schools s where s.archived_at is null));
