begin;
alter function public.catalog_normalize(text) set search_path=pg_catalog;
revoke execute on function public.is_catalog_moderator(), public.moderate_catalog_request(uuid,text,text),public.queue_catalog_review(uuid) from public,anon;
grant execute on function public.is_catalog_moderator(), public.moderate_catalog_request(uuid,text,text),public.queue_catalog_review(uuid) to authenticated;
commit;
