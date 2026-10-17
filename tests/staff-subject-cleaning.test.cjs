const assert=require('assert/strict'),{cleanPublishedSubject,subjectFromRole}=require('../scripts/parse-school-staff.cjs');
assert.equal(cleanPublishedSubject('Начальные классы высшей квалификационной категории'),'Начальные классы');assert.equal(cleanPublishedSubject('Музыка/категория высшая'),'Музыка');assert.equal(cleanPublishedSubject('Химия, выс. квалиф. категория'),'Химия');assert.equal(cleanPublishedSubject('Биология, высшая категория; Биология; География, первая категория'),'Биология; География');
assert.equal(cleanPublishedSubject('Начальные классы. (персональные данные, в том числе фотография, размещены с согласия субъекта персональных данных)'),'Начальные классы');
for(const subject of ['Первая помощь','Теория категорий','Защита персональных данных'])assert.equal(cleanPublishedSubject(subject),subject);
assert.equal(subjectFromRole('Учитель математики высшей категории'),'Математика');
console.log('PASS: explicit qualification/consent suffixes removed, published subjects and legitimate discipline names retained');
