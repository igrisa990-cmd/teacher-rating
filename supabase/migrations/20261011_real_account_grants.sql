begin;
-- Explicit API grants; public read aggregates remain available without a login.
revoke execute on function public.cast_school_vote(uuid,integer) from public,anon;
revoke execute on function public.submit_catalog_request(text,uuid,text,text,text,text,text,text,text) from public,anon;
revoke execute on function public.director_review_mine(uuid) from public,anon;
grant execute on function public.cast_school_vote(uuid,integer) to authenticated;
grant execute on function public.submit_catalog_request(text,uuid,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.director_review_mine(uuid) to authenticated;
commit;
