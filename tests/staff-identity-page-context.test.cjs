const assert=require('assert/strict'),{parsePublicStaff}=require('../scripts/parse-school-staff.cjs');
const table='<h1>Устав школы. Отчёт о повышении квалификации за 2016 год</h1><table><tr><th>ФИО</th><th>Должность</th><th>Повышение квалификации</th></tr><tr><td>Иванова Анна Петровна</td><td>Учитель математики</td><td>Курсы 2013–2016</td></tr></table>',options={schoolOgrn:'1020300977620',sourceUrl:'https://school.example/common',allowPlainTables:false};
assert.equal(parsePublicStaff(table,options).rows.length,0,'Legal identity evidence alone cannot promote incidental report tables to a current roster');
const card='<article class="gw-person-info-card"><h3 class="gw-person-info-card__name">Иванова Анна Петровна</h3><p class="gw-person-info-card__position">Учитель математики</p></article>';
assert.equal(parsePublicStaff(table+card,options).rows.length,1,'An explicit owned person card remains valid homepage evidence');
assert.equal(parsePublicStaff(table,{...options,allowPlainTables:true}).rows.length,1,'A dedicated roster collector retains its explicit table support');
assert.equal(require('../scripts/parse-school-staff.cjs').subjectFromRole('Учитель музыки и технологии преподаваемые учебные предметы: музыка, технология уровень (уровни) профессионального образования с указанием специальности: архитектура'),'Музыка и Технология','Labeled education fields cannot leak into a teaching-position subject');
console.log('PASS: identity pages require owned staff cards/microdata; incidental legal/archive tables cannot become current staff rosters');
