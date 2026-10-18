const assert=require('assert/strict'),{parsePublicStaff}=require('../scripts/parse-school-staff.cjs');
const opts={schoolOgrn:'1020300977620',sourceUrl:'https://school.example/staff',checkedAt:'2026-10-18T17:00:00Z'},table=(header,value,extra='')=>`<table><tr><th>ФИО</th><th>${header}</th><th>Квалификация</th></tr><tr><td>Петрова Анна Ивановна</td><td>${value}</td><td>учитель химии</td></tr>${extra}</table>`,read=h=>parsePublicStaff(h,opts).rows;
let rows=read(table('Преподаваемые дисциплины (модули), предметы, курсы','учитель математики'));assert.equal(rows.length,1);assert.equal(rows[0].subject,'Математика');assert.equal(rows[0].subject_evidence,'published_teaching_position');
assert.equal(read(table('Преподаваемые дисциплины','Математика')).length,0,'Bare discipline is not a published job');
assert.equal(read(table('Специализация (по диплому)','учитель математики')).length,0);
assert.equal(read(table('Преподаваемые дисциплины и квалификация','учитель математики')).length,0,'Ambiguous mixed column is held');
assert.equal(read(table('Преподаваемые дисциплины','Педагог-психолог')).length,0);
rows=read('<table><tr><th>ФИО</th><th>Должность</th><th>Преподаваемые дисциплины</th></tr><tr><td>Петрова Анна Ивановна</td><td>Учитель</td><td>Физика</td></tr></table>');assert.equal(rows[0].subject,'Физика');assert.equal(rows[0].subject_evidence,'explicit_discipline');
console.log('PASS: literal teaching jobs in dedicated teaching-discipline column, normal job columns preferred, no bare-subject or qualification inference');
