import runpy
p=runpy.run_path('scripts/parse-staff-documents.py')
header=['Фамилия, имя, отчество','Занимаемая должность','Преподаваемые учебные предметы']
rows=[header,['Иванова Анна Петровна','Учитель','Физическая культура; Здоровье человека'],['Петрова Елена Игоревна','Воспитатель','Математика'],['Сидорова Ольга Петровна','Учитель-логопед','Русский язык'],['Котова Мария Сергеевна','Учитель','На лечении'],['Орлова Анна Ивановна','Учитель','mail@example.ru']]
m,i=p['header_map'](rows)
found=p['table_people'](rows[i:],m)
assert len(found)==1 and found[0]['name']=='Иванова Анна Петровна'
assert found[0]['subject']=='Физическая культура; Здоровье человека'
assert p['header_map']([['ФИО','Квалификация','Образование']])[0] is None
assert p['header_map']([['Ф.И.О. педагогического работника','Занимаемая должность']])[0]['name']==[0]
combined=[['ФИО','Наименование должности в соответствии со штатным расписанием (преподаваемый предмет)','Квалификационная категория по основной должности'],['Иванова Анна Петровна','Учитель','Высшая']]
m,i=p['header_map'](combined)
assert m['role']==1 and m['subject'] is None
assert len(p['table_people'](combined[i:],m))==1
assert p['header_map']([['ФИО','Квалификационная категория по основной должности']])[0] is None
assert not p['table_people']([['Иванова','Учитель','Математика']],m)
split=[['Фамилия','Имя','Отчество','Должность'],['Иванова','Анна','Петровна','Учитель']]
m,i=p['header_map'](split);assert p['table_people'](split[i:],m)[0]['name']=='Иванова Анна Петровна'
assert not p['current_date_evidence']({'url':'https://school.example/2025-2026.pdf'},'')
assert p['current_date_evidence']({'url':'https://school.example/2026-2027.pdf'},'')
assert not p['current_date_evidence']({'url':'https://school.example/staff.pdf'},'2025-2026 учебный год')
assert p['current_date_evidence']({'url':'https://school.example/2026.pdf'},'Повышение квалификации 2021-2026')
assert not p['current_date_evidence']({'url':'https://school.example/staff.pdf'},'Фамилия имя отчество Иванова Анна Петровна Повышение квалификации 2026')
assert p['current_date_evidence']({'url':'https://school.example/staff.pdf'},'Список работников на 2026-2027 учебный год')
print('PASS: explicit name/role columns, split names, no role borrowing, professional subjects, private-field rejection and academic dates')
joint=[['ФИО, должность','Преподаваемые учебные предметы','Специальность, квалификация по диплому'],['Петрова Анна Ивановна, учитель','Физика','Учитель химии'],['Сидорова Ольга Петровна','Математика','Учитель'],['Орлова Мария Игоревна, воспитатель','Математика','Учитель']]
m,i=p['header_map'](joint);found=p['table_people'](joint[i:],m)
assert len(found)==1 and found[0]['name']=='Петрова Анна Ивановна' and found[0]['subject']=='Физика'
assert p['header_map']([['ФИО, квалификация','Предмет']])[0] is None
assert p['header_map']([['ФИО, должность','ФИО','Преподаваемые предметы']])[0] is None
assert len(p['table_people']([['Петрова Анна Ивановна','Учитель, русский язык','']],{'name':[0],'role':1,'subject':2,'columns':3}))==1
assert not p['table_people']([['Петрова Анна Ивановна','Учительская','']],{'name':[0],'role':1,'subject':2,'columns':3})
print('PASS: owned joint name/position cells and teaching-role punctuation; no qualification, neighboring-row or ambiguous-header borrowing')
import tempfile,hashlib
from pathlib import Path
with tempfile.TemporaryDirectory(dir=Path('work').resolve()) as folder:
    assert Path(folder).resolve().is_relative_to(Path('work').resolve())
    source=Path(folder)/'source.doc';source.write_bytes(b'local verified source fixture')
    xml=Path(folder)/'tables.xml'
    body='<document><title>Список работников на 2026-2027 учебный год</title><table><row><cell>ФИО</cell><cell>Должность</cell><cell>Преподаваемые предметы</cell><cell>Email</cell></row><row><cell>Иванова Анна Петровна</cell><cell>Учитель</cell><cell>Математика</cell><cell>private@example.test</cell></row></table></document>'
    xml.write_text(body,encoding='utf-8')
    meta={'file':str(source),'format':'doc','sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'doc_reader_version':1,'doc_tables_file':str(xml),'doc_tables_sha256':hashlib.sha256(xml.read_bytes()).hexdigest(),'url':'https://school.example/staff.doc','source_url':'https://school.example/staff.doc','identity_url':'https://school.example/common','identity_method':'explicit_ogrn','school_ogrn':'1020300977620','downloadedAt':'2026-10-16T16:00:00Z'}
    result=p['extract_document'](meta);assert result['status']=='prepared' and len(result['rows'])==1;assert 'private@' not in str(result['rows'])
    bad={**meta,'doc_tables_sha256':'0'*64}
    try:p['extract_document'](bad);raise AssertionError('Modified intermediate tables were accepted')
    except ValueError as error:assert str(error)=='legacy_table_hash_mismatch'
    xml.write_text(body.replace('2026-2027','2025-2026'),encoding='utf-8');meta['doc_tables_sha256']=hashlib.sha256(xml.read_bytes()).hexdigest();assert p['extract_document'](meta)['status']=='document_date_requires_review'
print('PASS: legacy table proof, professional-field whitelist, checksum mismatch rejection and old roster hold')
