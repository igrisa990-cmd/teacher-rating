create or replace function public.director_review_mine(target_school uuid)
returns table(director_name text,rating numeric,leadership numeric,fairness numeric,communication numeric,safety numeric,comment text)
language sql stable security definer set search_path=pg_catalog as $$
select r.director_name,r.rating,r.leadership,r.fairness,r.communication,r.safety,r.comment from public.director_reviews r where r.school_id=target_school and r.user_id=auth.uid();
$$;
revoke all on function public.director_review_mine(uuid) from public;
grant execute on function public.director_review_mine(uuid) to authenticated;
