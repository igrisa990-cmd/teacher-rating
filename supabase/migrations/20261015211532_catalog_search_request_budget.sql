-- Bound slow cold/full-country requests without changing role-wide timeouts.
alter function public.search_catalog(text,text,text,text,integer) set statement_timeout='8s';
