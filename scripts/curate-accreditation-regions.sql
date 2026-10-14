-- Reviewed physical-address corrections for the 2026-10-13 snapshot.
-- Original source categories remain in the immutable extract and private stage.
-- Match the exact address and source ID; never overwrite subsequent address edits.
begin;
update public.schools set region='Московская область'
where organization_ogrn='1027739877109' and source_type='accreditation'
and accreditation_id='19343ab2-6a4d-6ab3-1169-9b5b774ae518' and region='Москва'
and address='141551, МОСКОВСКАЯ ОБЛАСТЬ, Г СОЛНЕЧНОГОРСК, ПГТ. ГОЛУБОЕ, Д. 14';
update public.schools set region='Луганская Народная Республика'
where organization_ogrn='1249400007185' and source_type='accreditation'
and region='Республика Коми'
and address='291006, ЛУГАНСКАЯ НАРОДНАЯ РЕСПУБЛИКА, Г.О. ГОРОД ЛУГАНСК, Г. ЛУГАНСК, КВ-Л ЮЖНЫЙ, Д. 5В';
commit;
