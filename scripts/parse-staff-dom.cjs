/* A standards-based fallback for explicitly associated microdata fields. */
const {parse}=require('./staff-parser/node_modules/parse5');
function extract(html){
 if(Buffer.byteLength(html)>5000000)throw Error('page_too_large');
 const root=parse(html),nodes=[],stack=[root];while(stack.length){const node=stack.pop();nodes.push(node);if(nodes.length>150000)throw Error('html_node_limit');stack.push(...(node.childNodes||[]).slice().reverse())}
 const prop=node=>(node.attrs?.find(a=>a.name==='itemprop')?.value||'').toLowerCase().split(/\s+/);
 const plain=node=>{const content=node.attrs?.find(a=>a.name==='content')?.value;if(content!==undefined)return content;const values=[],pending=[node];while(pending.length){const n=pending.pop();if(['script','style','template'].includes(n.tagName))continue;if(n.nodeName==='#text')values.push(n.value);else pending.push(...(n.childNodes||[]).slice().reverse())}return values.join(' ').replace(/\s+/g,' ').trim()};
 const cache=new Map();function fields(node){if(cache.has(node))return cache.get(node);const result={fio:[],post:[],discipline:[]},pending=[node];while(pending.length){const n=pending.pop(),p=prop(n);if(p.includes('fio'))result.fio.push(n);if(p.includes('post')||p.includes('position'))result.post.push(n);if(p.includes('teachingdiscipline'))result.discipline.push(n);if(result.fio.length>1)break;pending.push(...(n.childNodes||[]))}cache.set(node,result);return result}
 function associated(node){if(node.tagName==='tr')return true;for(let p=node,depth=0;p&&depth<18;p=p.parentNode,depth++)if(prop(p).includes('teachingstaff'))return true;return false}
 const records=[];for(const fio of nodes.filter(n=>prop(n).includes('fio'))){let node=fio.parentNode;for(let depth=0;node&&depth<18;depth++,node=node.parentNode){const f=fields(node);if(f.fio.length>1)break;if(f.fio.length!==1||f.post.length!==1||f.discipline.length>1||!associated(node))continue;const name=plain(fio),role=plain(f.post[0]),subject=f.discipline.length?plain(f.discipline[0]):'';if(!/^[\p{L}’'-]+(?:\s+[\p{L}’'-]+){1,3}$/u.test(name)||!/(?:^|[,;]\s*)учитель(?:\s|[-(]|$)/i.test(role)||/дефектолог|логопед|воспитател|психолог|декрет|беременн|на лечении|по состоянию здоров/i.test(role+' '+subject)||role.length>250||subject.length>1000||/@|https?:\/\/|\+\d[\d ()-]{7,}/i.test(role+' '+subject))break;records.push({name,role,subject});break}}
 // Read the logical table grid. Explicit row/column spans retain their source association.
 const normalize=value=>String(value||'').normalize('NFKC').toLowerCase().replaceAll('ё','е').replace(/[^\p{L}\p{N}]+/gu,' ').trim();
 function belongs(row,table){for(let p=row.parentNode;p;p=p.parentNode)if(p.tagName==='table')return p===table;return false}
 function add(name,role,subject){if(!/^[\p{L}’'-]+(?:\s+[\p{L}’'-]+){1,3}$/u.test(name)||!/(?:^|[,;]\s*)учитель(?:\s|[-(]|$)/i.test(role)||/дефектолог|логопед|воспитател|психолог|декрет|беременн|на лечении|по состоянию здоров/i.test(role+' '+subject)||role.length>250||subject.length>1000||/@|https?:\/\/|\+\d[\d ()-]{7,}/i.test(role+' '+subject))return;records.push({name,role,subject})}
 const hasClass=(node,value)=>(node.attrs?.find(a=>a.name==='class')?.value||'').split(/\s+/).includes(value);
 function within(node,value){const out=[],pending=[node];while(pending.length){const current=pending.pop();if(hasClass(current,value))out.push(current);pending.push(...(current.childNodes||[]))}return out}
 // Only explicit fields in the same published staff card are read; biographies and contacts are ignored.
 for(const card of nodes.filter(n=>hasClass(n,'personnel__item'))){const names=within(card,'personnel__name'),roles=[],subjects=[];if(names.length!==1)continue;for(const item of within(card,'description__item')){const titles=within(item,'description__title'),values=within(item,'description__text');if(titles.length!==1||values.length!==1)continue;const label=normalize(plain(titles[0]));if(/^(?:занимаемая |наименование )?должност/.test(label))roles.push(plain(values[0]));if(/^преподаваемые (?:учебные )?(?:предметы|дисциплины)/.test(label))subjects.push(plain(values[0]))}if(roles.length===1&&subjects.length<=1)add(plain(names[0]),roles[0],subjects[0]||'')}
 for(const [component,nameField,roleField] of [['gw-employee-info','gw-employee-info__title','gw-employee-info__position'],['gw-slide-vertical-full-info','gw-slide-vertical-full-info__surname','gw-slide-vertical-full-info__position'],['teacher-card','teacher-card__name','teacher-card__position']]){for(const card of nodes.filter(n=>hasClass(n,component))){const names=within(card,nameField),roles=within(card,roleField);if(names.length===1&&roles.length===1)add(plain(names[0]),plain(roles[0]),'')}}
 // Netcat/Gosweb's published staff-list template has separate name, position and discipline fields.
 // The generic object-item class alone is insufficient: require its staff component and one owned info block.
 for(const card of nodes.filter(n=>hasClass(n,'object-item'))){
  let staff=false;for(let p=card.parentNode;p;p=p.parentNode){if(hasClass(p,'object-item'))break;if(hasClass(p,'tpl-component-gw-staff')){staff=true;break}}if(!staff)continue;
  const owned=(node,cls)=>within(node,cls).filter(field=>{for(let p=field.parentNode;p&&p!==card;p=p.parentNode)if(hasClass(p,'object-item'))return false;return true});
  const info=owned(card,'object-info');if(info.length!==1)continue;
  const fields=owned(info[0],'contacts-object-info'),names=fields.filter(n=>hasClass(n,'tpl-text-header3')),roles=fields.filter(n=>hasClass(n,'contacts-object-info-subname')),subjects=fields.filter(n=>hasClass(n,'tpl-text-paragraph'));
  if(names.length!==1||roles.length!==1||subjects.length>1||new Set([...names,...roles,...subjects]).size!==names.length+roles.length+subjects.length)continue;
  add(plain(names[0]),plain(roles[0]),subjects.length?plain(subjects[0]):'');
 }
 // Read only the dedicated name/position fields of these published roster templates.
 // Education, qualifications, biographies and contact paragraphs cannot supply a teaching role.
 function owned(card,node,isCard){for(let p=node.parentNode;p&&p!==card;p=p.parentNode)if(isCard(p))return false;return true}
 for(const card of nodes.filter(n=>hasClass(n,'staff-card'))){
  const children=card.childNodes||[],names=children.filter(n=>n.tagName==='h3'),roles=children.filter(n=>n.tagName==='p');
  if(names.length===1&&roles.length===1&&!within(card,'staff-card').some(n=>n!==card))add(plain(names[0]),plain(roles[0]),'');
 }
 for(const card of nodes.filter(n=>hasClass(n,'row')&&hasClass(n,'my-4'))){
  const isCard=n=>hasClass(n,'row')&&hasClass(n,'my-4'),headings=within(card,'my-3').filter(n=>n.tagName==='h5'&&owned(card,n,isCard));
  if(headings.length!==1)continue;const head=headings[0],names=within(head,'text-accent').filter(n=>n.tagName==='a'),roles=within(head,'text-muted').filter(n=>n.tagName==='span'&&hasClass(n,'small'));
  if(names.length===1&&roles.length===1)add(plain(names[0]),plain(roles[0]),'');
 }
 for(const [kind,nameField,roleField] of [['position-photo-about-area','fio_blk','position-area'],['gs_team_popup_details','gs-member-name','gs-member-desig']]){
  for(const card of nodes.filter(n=>hasClass(n,kind))){
   const own=n=>owned(card,n,n=>hasClass(n,kind)),names=within(card,nameField).filter(own),roles=within(card,roleField).filter(own);
   if(names.length!==1||roles.length!==1)continue;
   let subject='';if(kind==='gs_team_popup_details'){
    const fields=nodes.filter(n=>prop(n).includes('teachingdiscipline')&&own(n)&&(()=>{for(let p=n.parentNode;p;p=p.parentNode)if(p===card)return true;return false})());
    if(fields.length>1)continue;if(fields.length===1)subject=plain(fields[0]).replace(/^(?:препода[её]т учебные предметы|преподаваемые (?:учебные )?(?:предметы|дисциплины))\s*:\s*/iu,'');
   }
   add(plain(names[0]),plain(roles[0]),subject);
  }
 }
 // Labeled roster cards keep the published position grid separate from the biography.
 const labeledCard=n=>hasClass(n,'@container')&&hasClass(n,'m-4')&&hasClass(n,'@2xl:flex-row');
 for(const card of nodes.filter(labeledCard)){
  const children=n=>(n.childNodes||[]).filter(c=>!!c.tagName),bodies=children(card).filter(n=>hasClass(n,'gap-y-4')&&hasClass(n,'w-full'));
  if(bodies.length!==1)continue;const body=bodies[0],headers=children(body).filter(n=>hasClass(n,'@sm:mx-auto')&&hasClass(n,'@2xl:mx-0')),grids=children(body).filter(n=>hasClass(n,'grid')&&hasClass(n,'@5xl:grid-cols-3'));
  if(headers.length!==1||grids.length!==1)continue;
  const names=children(headers[0]).filter(n=>n.tagName==='h3'&&hasClass(n,'font-medium')&&hasClass(n,'w-fit'));
  if(names.length!==1||!owned(card,names[0],labeledCard))continue;const roles=[],subjects=[];
  for(const row of children(grids[0])){
   if(!hasClass(row,'items-start')||!owned(card,row,labeledCard))continue;
   const pairs=children(row).filter(n=>hasClass(n,'flex-col')&&hasClass(n,'gap-y-1'));if(pairs.length!==1)continue;
   const values=children(pairs[0]);if(values.length!==2||values.some(n=>n.tagName!=='span')||!hasClass(values[0],'font-medium'))continue;
   const label=normalize(plain(values[0]));if(label==='должность')roles.push(plain(values[1]));
   if(/^(?:преподаваемые )?(?:учебные )?(?:предметы|дисциплины)$/.test(label))subjects.push(plain(values[1]));
  }
  if(roles.length===1&&subjects.length<=1){const role=roles[0].replace(/^((?:директор|заместитель директора|зам[.]\s*директора)[^/]{0,100})\s*\/\s*(?=учитель(?:\s|[-(]|$))/iu,'$1, ');add(plain(names[0]),role,subjects[0]||'')}
 }
 // The portal's main profile job precedes its training and career sections.
 // A training "Предмет" or diploma specialization cannot become a taught subject.
 for(const card of nodes.filter(n=>(n.attrs||[]).some(a=>a.name==='id'&&a.value==='school_data'))){
  const children=(card.childNodes||[]).filter(n=>n.tagName),names=children.filter(n=>n.tagName==='h1');if(names.length!==1)continue;
  const roles=[],subjects=[];for(const field of children){if(/^h[2-6]$/.test(field.tagName))break;if(field.tagName!=='div')continue;
   const cells=(field.childNodes||[]).filter(n=>n.tagName);if(cells.length!==2||cells[0].tagName!=='strong'||cells[1].tagName!=='p')continue;
   const label=normalize(plain(cells[0]));if(label==='должность')roles.push(plain(cells[1]));
   if(/^(?:преподаваемые учебные предметы|преподаваемые предметы|преподаваемые дисциплины)$/.test(label))subjects.push(plain(cells[1]));
  }
  if(roles.length===1&&subjects.length<=1)add(plain(names[0]),roles[0],subjects[0]||'');
 }
 // Responsive Gosweb profiles publish two dedicated headers for the same person.
 // Accept only one top/content pair whose owned names and positions agree.
 for(const card of nodes.filter(n=>hasClass(n,'gw-employee-info'))){
  const own=n=>owned(card,n,n=>hasClass(n,'gw-employee-info'));
  const headers=within(card,'gw-employee-info__header').filter(own);
  if(headers.length!==2||headers.filter(n=>hasClass(n,'gw-employee-info__header_top')).length!==1||headers.filter(n=>hasClass(n,'gw-employee-info__header_content')).length!==1)continue;
  const pairs=headers.map(header=>{const names=within(header,'gw-employee-info__title').filter(own),roles=within(header,'gw-employee-info__position').filter(own);return names.length===1&&roles.length===1?{name:plain(names[0]),role:plain(roles[0])}:null});
  if(pairs.some(p=>!p)||normalize(pairs[0].name)!==normalize(pairs[1].name)||normalize(pairs[0].role)!==normalize(pairs[1].role))continue;
  const subjects=[];let ambiguous=false;
  for(const label of within(card,'gw-employee-info__content-subtitle').filter(own)){
   if(normalize(plain(label))!=='преподаваемые учебные предметы курсы дисциплины модули')continue;
   const cells=(label.parentNode?.childNodes||[]).filter(n=>n.tagName);
   if(cells.length!==2||cells[0]!==label||!['p','ul'].includes(cells[1].tagName)){ambiguous=true;break}
   const value=cells[1];if(value.tagName==='ul'){
    const items=(value.childNodes||[]).filter(n=>n.tagName);if(items.some(n=>n.tagName!=='li')){ambiguous=true;break}subjects.push(items.map(plain).filter(Boolean).join('; '));
   }else subjects.push(plain(value));
  }
  if(!ambiguous&&subjects.length<=1)add(pairs[0].name,pairs[0].role,subjects[0]||'');
 }
 // A vertical profile table must own exactly one explicitly labeled person and job.
 // Qualifications, contacts and neighboring tables cannot provide these fields.
 for(const table of nodes.filter(n=>n.tagName==='table')){
  const nested=nodes.some(n=>n.tagName==='table'&&n!==table&&(()=>{for(let p=n.parentNode;p;p=p.parentNode)if(p===table)return true;return false})());if(nested)continue;
  const fields={names:[],roles:[],subjects:[]};
  for(const row of nodes.filter(n=>n.tagName==='tr'&&belongs(n,table))){
   const cells=(row.childNodes||[]).filter(n=>['td','th'].includes(n.tagName));if(cells.length!==2||cells.some(n=>(n.attrs||[]).some(a=>['rowspan','colspan'].includes(a.name)&&a.value!=='1')))continue;
   const label=normalize(plain(cells[0])),value=plain(cells[1]);
   if(/^(?:фио|ф и о|фамилия имя отчество)$/.test(label))fields.names.push(value);
   if(/^(?:(?:занимаемая|наименование) )?должность$/.test(label))fields.roles.push(value);
   if(/^(?:перечень )?преподаваем(?:ые|ых) (?:учебн(?:ые|ых) )?(?:дисциплин(?:ы)?|предмет(?:ы|ов))$/.test(label)||label==='преподаваемые учебные предметы курсы дисциплины модули')fields.subjects.push(value);
  }
  if(fields.names.length===1&&fields.roles.length===1&&fields.subjects.length<=1)add(fields.names[0],fields.roles[0],fields.subjects[0]||'');
 }
 for(const table of nodes.filter(n=>n.tagName==='table')){const lines=nodes.filter(n=>n.tagName==='tr'&&belongs(n,table));if(lines.length>1500)continue;const grid=[];let invalid=false;
  for(let r=0;r<lines.length;r++){grid[r]||=[];let col=0;for(const cell of(lines[r].childNodes||[]).filter(n=>['td','th'].includes(n.tagName))){while(grid[r][col]!==undefined)col++;const attrs=Object.fromEntries((cell.attrs||[]).map(a=>[a.name,a.value])),height=Number(attrs.rowspan||1),width=Number(attrs.colspan||1);if(!Number.isInteger(height)||!Number.isInteger(width)||height<1||height>100||width<1||col+width>60){invalid=true;break}const value=plain(cell);for(let y=r;y<Math.min(lines.length,r+height);y++){grid[y]||=[];for(let x=col;x<col+width;x++){if(grid[y][x]!==undefined){invalid=true;break}grid[y][x]=value}}col+=width}if(invalid)break}if(invalid)continue;
  let mapping,start;for(let r=0;r<Math.min(15,grid.length)&&!mapping;r++)for(const depth of[1,2,3]){const block=grid.slice(r,r+depth);if(block.length!==depth)continue;const count=Math.max(...block.map(row=>row.length)),headers=Array.from({length:count},(_,i)=>normalize(block.map(row=>row[i]||'').join(' '))),full=headers.map((h,i)=>(/(?:^| )(?:фио|ф и о)(?: |$)/.test(h)||h.includes('фамили')&&h.includes('имя'))?i:-1).filter(i=>i>=0),split=['фамилия','имя','отчество'].map(word=>headers.indexOf(word)),names=full.length===1?full:split.every(i=>i>=0)&&new Set(split).size===3?split:[],roles=headers.map((h,i)=>/^(?:занимаемая |наименование )?должност/.test(h)?i:-1).filter(i=>i>=0),subjects=headers.map((h,i)=>!roles.includes(i)&&/преподава/.test(h)&&/предмет|дисциплин/.test(h)?i:-1).filter(i=>i>=0);if(names.length&&roles.length===1&&!names.includes(roles[0])){if(depth<3&&!subjects.length&&headers.some(h=>/преподава/.test(h))&&normalize(grid[r+depth]?.[names[0]])===normalize(grid[r]?.[names[0]]))continue;mapping={names,role:roles[0],subject:subjects.length===1?subjects[0]:null,count};start=r+depth;break}}
  // Some published teaching-discipline cells literally contain the teaching job.
  // Use that literal position only after the full normal-header search failed.
  if(!mapping)for(let r=0;r<Math.min(15,grid.length)&&!mapping;r++)for(const depth of[1,2,3]){
   const block=grid.slice(r,r+depth);if(block.length!==depth)continue;const count=Math.max(...block.map(row=>row.length)),headers=Array.from({length:count},(_,i)=>normalize(block.map(row=>row[i]||'').join(' ')));
   const full=headers.map((h,i)=>(/(?:^| )(?:фио|ф и о)(?: |$)/.test(h)||h.includes('фамили')&&h.includes('имя'))?i:-1).filter(i=>i>=0),split=['фамилия','имя','отчество'].map(word=>headers.indexOf(word)),names=full.length===1?full:split.every(i=>i>=0)&&new Set(split).size===3?split:[];
   const roles=headers.filter(h=>/^(?:занимаемая |наименование )?должност/.test(h)),teaching=headers.map((h,i)=>/^преподава/.test(h)&&/предмет|дисциплин/.test(h)&&!/квалификац|образован|подготовк|специальност|диплом/.test(h)?i:-1).filter(i=>i>=0);
   if(names.length&&!roles.length&&teaching.length===1&&!names.includes(teaching[0])){mapping={names,role:teaching[0],subject:null,count};start=r+depth;break}
  }
  if(!mapping)continue;for(const row of grid.slice(start)){if(row.length!==mapping.count)continue;add(mapping.names.map(i=>row[i]||'').join(' ').replace(/\s+/g,' ').trim(),row[mapping.role]||'',mapping.subject===null?'':row[mapping.subject]||'')}
 }
 return records;
}
module.exports={extract};
