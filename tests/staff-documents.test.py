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
