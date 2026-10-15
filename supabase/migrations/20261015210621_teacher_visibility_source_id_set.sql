-- Same restrictive source-school visibility for reads and writes. Both IDs are
-- non-null foreign/primary keys, so IN and the previous EXISTS are equivalent.
-- The visible-school set still uses the caller's source-school RLS policies.
alter policy active_school_catalog on public.teachers
using(school_id in(select s.id from public.schools s where s.archived_at is null));
