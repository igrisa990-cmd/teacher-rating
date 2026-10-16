"""Read bounded public roster tables; retain only names, teacher roles and subjects."""
import argparse, concurrent.futures, hashlib, json, re, unicodedata, zipfile
from pathlib import Path

def clean(value):
    value=unicodedata.normalize('NFKC',str(value or '')).replace('\u00ad','')
    value=re.sub(r'(?<=[А-Яа-яЁё])-\s*\n\s*(?=[А-Яа-яЁё])','',value)
    return re.sub(r'\s+',' ',value).strip()

def normalized(value):
    return re.sub(r'[^а-яa-z0-9]+',' ',clean(value).lower().replace('ё','е')).strip()

def header_map(rows):
    for index in range(min(15,len(rows))):
        for depth in (1,2,3):
            block=rows[index:index+depth]
            if len(block)!=depth: continue
            count=max((len(r) for r in block),default=0)
            cells=[normalized(' '.join(str(r[c] or '') for r in block if c<len(r))) for c in range(count)]
            full=[i for i,c in enumerate(cells) if re.search(r'(?:^| )(?:фио|ф и о)(?: |$)',c) or ('фамили' in c and 'имя' in c)]
            split=[next((i for i,c in enumerate(cells) if c==word),None) for word in ('фамилия','имя','отчество')]
            names=full[:1] if len(full)==1 else split if all(i is not None for i in split) and len(set(split))==3 else []
            roles=[i for i,c in enumerate(cells) if re.match(r'^(?:занимаемая |наименование )?должност',c)]
            subjects=[i for i,c in enumerate(cells) if i not in roles and ('преподава' in c and ('предмет' in c or 'дисциплин' in c))]
            if names and len(roles)==1 and roles[0] not in names:
                return {'name':names,'role':roles[0],'subject':subjects[0] if len(subjects)==1 else None,'columns':count},index+depth
    return None,0

def table_people(rows,mapping):
    result=[]
    for row in rows:
        if len(row)!=mapping['columns']: continue
        name=clean(' '.join(str(row[i] or '') for i in mapping['name']))
        role=clean(row[mapping['role']]);subject=clean(row[mapping['subject']]) if mapping['subject'] is not None else ''
        if not re.fullmatch(r"[А-ЯЁа-яё][А-ЯЁа-яё’'\-]+(?: [А-ЯЁа-яё][А-ЯЁа-яё’'\-]+){1,3}",name): continue
        if re.search(r'фамилия|отчество|учитель|директор|педагог|образование',name,re.I): continue
        if not re.search(r'(?:^|[,;]\s*)учитель(?:\s|[-(]|$)',role,re.I): continue
        if re.search(r'дефектолог|логопед|воспитател|психолог|декрет|беременн|на лечении|по состоянию здоров',role+' '+subject,re.I): continue
        if len(role)>250 or len(subject)>1000 or re.search(r'@|https?://|\+\d[\d ()-]{7,}',subject): continue
        result.append({'name':name,'role':'Учитель','subject':subject,'subject_evidence':'explicit_document_column' if subject else 'not_published'})
    return result

def current_date_evidence(meta,title):
    from urllib.parse import unquote,urlparse
    label=meta.get('label','')+' '+unquote(urlparse(meta['url']).path.split('/')[-1])
    # An academic year ending in 2026 is already over in October 2026.
    years=re.findall(r'(20\d{2})\s*[-–—/]\s*(20\d{2})',label)
    years+=re.findall(r'(20\d{2})\s*[-–—/]\s*(20\d{2})\s*(?:гг?\.?\s*)?учебн',title,re.I)
    if years and max(int(a) for a,b in years)<2026: return False
    if re.search(r'(?<!\d)2026(?!\d)',label):return True
    heading=re.split(r'фамилия|ф\.?\s*и\.?\s*о\.?|занимаемая\s+должност',title,flags=re.I)[0][:1200]
    return bool(re.search(r'2026\s*[-–—/]\s*2027|по состоянию на[^\n]{0,40}2026|(?:педагогическ[а-я ]*состав|список[^\n]{0,40}работник)[^\n]{0,80}2026',heading,re.I))

def checked_zip(file):
    with zipfile.ZipFile(file) as z:
        if len(z.infolist())>5000 or sum(i.file_size for i in z.infolist())>30000000: raise ValueError('zip_expansion_limit')

def extract_document(meta):
    file=Path(meta['file']);tables=[];title='';partial=False
    if hashlib.sha256(file.read_bytes()).hexdigest()!=meta['sha256']: raise ValueError('source_hash_mismatch')
    if meta['format']=='pdf':
        import pdfplumber
        with pdfplumber.open(file) as pdf:
            if len(pdf.pages)>60: raise ValueError('document_page_limit')
            prior=None;prior_grid=None
            for page_index,page in enumerate(pdf.pages):
                if any((i['x1']-i['x0'])*(i['bottom']-i['top'])>0.65*page.width*page.height for i in page.images):
                    raise ValueError('scanned_document_requires_review')
                if page_index<2: title+=(page.extract_text() or '')[:1500]+'\n'
                for table in page.find_tables():
                    rows=table.extract();mapping,start=header_map(rows)
                    grid=tuple(sorted(set(round(c[0],1) for c in table.cells if c)))
                    if mapping: prior=mapping;prior_grid=grid
                    elif prior and grid==prior_grid and all(len(r)==prior['columns'] for r in rows): mapping=prior;start=0
                    else: partial=True;continue
                    tables.extend(table_people(rows[start:],mapping))
                page.close()
    elif meta['format']=='docx':
        checked_zip(file)
        from docx import Document
        doc=Document(file);title=' '.join(p.text for p in doc.paragraphs[:12])[:2000]
        for table in doc.tables:
            rows=[[c.text for c in row.cells] for row in table.rows]
            if len(rows)>3000: raise ValueError('table_row_limit')
            mapping,start=header_map(rows)
            if mapping: tables.extend(table_people(rows[start:],mapping))
            else: partial=True
    elif meta['format']=='xlsx':
        checked_zip(file)
        import openpyxl
        workbook=openpyxl.load_workbook(file,read_only=True,data_only=True,keep_links=False)
        if len(workbook.worksheets)>10: raise ValueError('worksheet_limit')
        for sheet in workbook.worksheets:
            if sheet.max_row>3000 or sheet.max_column>60: raise ValueError('worksheet_size_limit')
            rows=[[clean(v) for v in r] for r in sheet.iter_rows(values_only=True)]
            title+=' '.join(' '.join(r) for r in rows[:4])[:1000]
            mapping,start=header_map(rows)
            if mapping: tables.extend(table_people(rows[start:],mapping))
            else: partial=True
        workbook.close()
    elif meta['format']=='xls':
        import xlrd
        # Parse cell values only. No Excel automation, formulas, links or macros execute.
        workbook=xlrd.open_workbook(str(file),on_demand=True)
        try:
            if workbook.nsheets>10: raise ValueError('worksheet_limit')
            for index in range(workbook.nsheets):
                sheet=workbook.sheet_by_index(index)
                if sheet.nrows>3000 or sheet.ncols>60: raise ValueError('worksheet_size_limit')
                rows=[[clean(v) for v in sheet.row_values(i)] for i in range(sheet.nrows)]
                title+=' '.join(' '.join(r) for r in rows[:4])[:1000]
                mapping,start=header_map(rows)
                if mapping: tables.extend(table_people(rows[start:],mapping))
                else: partial=True
                workbook.unload_sheet(index)
        finally: workbook.release_resources()
    elif meta['format']=='doc':
        import xml.etree.ElementTree as ET
        if meta.get('doc_reader_version')!=1: raise ValueError('legacy_reader_required')
        xml=Path(meta['doc_tables_file']).read_bytes()
        if len(xml)>24000000 or hashlib.sha256(xml).hexdigest()!=meta['doc_tables_sha256']: raise ValueError('legacy_table_hash_mismatch')
        document=ET.fromstring(xml);title=document.findtext('title','')[:2000]
        for table in document.findall('table'):
            rows=[[clean(cell.text) for cell in row.findall('cell')] for row in table.findall('row')]
            if len(rows)>3000 or any(len(row)>60 for row in rows):raise ValueError('legacy_table_size_limit')
            if not title:title=' '.join(' '.join(row) for row in rows[:4])[:2000]
            mapping,start=header_map(rows)
            if mapping:tables.extend(table_people(rows[start:],mapping))
            else:partial=True
    if not current_date_evidence(meta,title[:2000]): return {'status':'document_date_requires_review','rows':[]}
    unique={}
    for person in tables:
        key=normalized(person['name']);old=unique.get(key)
        if old:
            old['subject']='; '.join(dict.fromkeys(s for s in (old['subject'],person['subject']) if s))
        else: unique[key]=person
    rows=[dict(p,school_ogrn=meta['school_ogrn'],source_url=meta['source_url'],identity_url=meta['identity_url'],identity_method=meta['identity_method'],source_sha256=meta['sha256'],checked_at=meta['downloadedAt']) for p in unique.values()]
    return {'status':'prepared_partial' if rows and partial else 'prepared' if rows else 'table_format_requires_review','rows':rows,'partial_tables':partial}

def process_one(args):
    meta_file,output=args;meta=json.loads(meta_file.read_text(encoding='utf-8'));target=output/meta_file.name
    if target.exists():
        saved=json.loads(target.read_text(encoding='utf-8'))
        if saved.get('documentParserVersion',0)>=5 or meta['format']!='doc' and (saved.get('documentParserVersion',0)>=4 or saved.get('documentParserVersion',0)>=2 and saved['status']!='table_format_requires_review'):return saved
    try: parsed=extract_document(meta)
    except Exception as e: parsed={'status':type(e).__name__+': '+str(e)[:160],'rows':[]}
    result={**meta,**parsed,'documentParserVersion':5};target.write_text(json.dumps(result,ensure_ascii=False),encoding='utf-8');return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',default='work/staff-documents-20261016');parser.add_argument('--workers',type=int,default=3);args=parser.parse_args()
    root=Path(args.root);output=root/'parsed';output.mkdir(exist_ok=True);files=[p for p in (root/'documents').glob('*.json') if json.loads(p.read_text(encoding='utf-8'))['status']=='downloaded']
    report={'documents':len(files),'processed':0,'teachers':0,'outcomes':{}}
    with concurrent.futures.ProcessPoolExecutor(max_workers=min(4,max(1,args.workers))) as pool:
        for result in pool.map(process_one,[(p,output) for p in files]):
            report['processed']+=1;report['teachers']+=len(result['rows']);status=result['status'];report['outcomes'][status]=report['outcomes'].get(status,0)+1
            if report['processed']%20==0: print(json.dumps({'processed':report['processed'],'documents':len(files),'rows':report['teachers']}),flush=True)
    (root/'parse-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report),flush=True)

if __name__=='__main__': main()
