-- The helper has a hard LIMIT 21; avoid planning full-table joins for 1,000 rows.
alter function catalog_search_internal.candidates(text,text,text,text,integer) rows 21;
