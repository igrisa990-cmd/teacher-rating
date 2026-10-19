const assert=require('assert/strict'),{withinSchoolSource}=require('../scripts/collect-national-staff.cjs');
for(const [home,allowed,other]of[
 ['http://edu.mari.ru/mouo-kugener/sh9/default.aspx','http://edu.mari.ru/mouo-kugener/sh9/DocLib150/staff.pdf','http://edu.mari.ru/mouo-kugener/sh90/staff'],
 ['http://portal.iv-edu.ru/dep/mouoivrn/school/default.aspx','http://portal.iv-edu.ru/dep/mouoivrn/school/staff','http://portal.iv-edu.ru/dep/mouoivrn/other/staff'],
 ['http://www.schoolrm.ru/schools_koch/sckoch','http://www.schoolrm.ru/schools_koch/sckoch/staff','http://www.schoolrm.ru/schools_koch/other/staff'],
 ['https://school.tver.ru/school/49','https://school.tver.ru/school/49/staff','https://school.tver.ru/school/490/staff'],
 ['http://www.kirov.spb.ru/sc/244','http://www.kirov.spb.ru/sc/244/staff','http://www.kirov.spb.ru/sc/249/staff'],
 ['https://sites.google.com/site/my-school/home','https://sites.google.com/site/my-school/staff','https://sites.google.com/site/another-school/staff'],
 ['https://nsportal.ru/site/224472','https://nsportal.ru/site/224472/staff','https://nsportal.ru/site/2244721/staff'],
 ['https://schools.dnevnik.ru/school.aspx?school=46510','https://schools.dnevnik.ru/staff.aspx?school=46510','https://schools.dnevnik.ru/staff.aspx?school=46511']
]){assert(withinSchoolSource(allowed,home));assert(!withinSchoolSource(other,home))}
assert(!withinSchoolSource('http://www.dagschool.com/staff','http://www.dagschool.com/'),'A shared root cannot own every organization in a regional portal');
assert(!withinSchoolSource('http://edu.mari.ru/mouo-a/sh1%2F..%2Fsh2/staff','http://edu.mari.ru/mouo-a/sh1'));
assert(withinSchoolSource('https://school.example/staff','https://school.example/'));
console.log('PASS: known shared platforms require an exact school namespace or explicit school ID; sibling schools, encoded boundaries and ambiguous portal roots remain held');
