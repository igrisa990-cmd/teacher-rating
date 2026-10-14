"""Stream the official ZIP/XML. Never extract paths, entities, contacts or biographies."""
import argparse,collections,json,pathlib,re,zipfile
from lxml import etree

def value(node,key):
    return (node.findtext(key) or '').strip()
def yes(s):
    return s.strip().lower() in ('1','true','да','yes')
def extract(archive,out):
    counts=collections.Counter();statuses=collections.Counter();out=pathlib.Path(out);out.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        entries=[i for i in z.infolist() if i.filename.lower().endswith('.xml')]
        if len(entries)!=1 or entries[0].file_size>3000000000:raise ValueError('Unexpected archive contents')
        with z.open(entries[0]) as source,open(out/'active-general.ndjson','w',encoding='utf-8') as dest:
            for event,e in etree.iterparse(source,events=('end',),tag='Certificate',load_dtd=False,no_network=True,resolve_entities=False,huge_tree=False):
                counts['certificates']+=1;status=value(e,'StatusName');statuses[status]+=1
                if status=='Действующее':
                    counts['active_certificates']+=1;programs=[]
                    for supplement in e.findall('Supplements/Supplement'):
                        if value(supplement,'StatusName')!='Действующее' or yes(value(supplement,'IsForBranch')):continue
                        for p in supplement.findall('EducationalPrograms/EducationalProgram'):
                            level=value(p,'EduLevelName');program=value(p,'ProgrammName')
                            if yes(value(p,'IsCanceled')) or yes(value(p,'IsSuspended')):continue
                            # Old schema can place a general level in ProgrammName under a broad level.
                            if not re.fullmatch(r'(Начальное|Основное|Среднее(?: \(полное\))?) общее образование',level,re.I):level=program
                            if re.fullmatch(r'(Начальное|Основное|Среднее(?: \(полное\))?) общее образование',level,re.I):programs.append({'educationLevel':level,'suspended':'Нет','canceled':'Нет'})
                    if programs:
                        counts['active_general_certificates']+=1;actual=e.find('ActualEducationOrganization');get=lambda k:value(actual,k) if actual is not None else ''
                        ogrn=value(e,'EduOrgOGRN');current_ogrn=get('OGRN')
                        if current_ogrn and ogrn and current_ogrn!=ogrn:counts['organization_identity_conflicts']+=1
                        else:
                            d={'id':value(e,'Id'),'status':status,'region':value(e,'RegionName') or get('RegionName'),'regionCode':value(e,'RegionCode'),'registerNumber':value(e,'RegNumber'),'date':value(e,'IssueDate'),'dateEnd':value(e,'EndDate'),'isOrganization':bool(ogrn),'gosRegisterNumber':ogrn,'organizationName':get('FullName') or value(e,'EduOrgFullName'),'organizationShortName':get('ShortName') or value(e,'EduOrgShortName'),'address':get('PostAddress') or value(e,'PostAddress'),'website':get('WebSite'),'headName':get('HeadName'),'headPost':get('HeadPost'),'supplements':[{'status':'Действующее','branch':False,'programs':programs}]}
                            dest.write(json.dumps(d,ensure_ascii=False)+'\n');counts['prepared_details']+=1
                    else:counts['active_without_current_general_program']+=1
                if counts['certificates']%10000==0:print(json.dumps(dict(counts)),flush=True)
                e.clear()
                while e.getprevious() is not None:del e.getparent()[0]
    report={'archive':str(archive),'xmlEntry':entries[0].filename,'xmlBytes':entries[0].file_size,'counts':dict(counts),'statuses':dict(statuses),'contactsImported':False,'coverage':'Every certificate in the official XML is inspected. Only active, non-branch, non-suspended and non-cancelled general education programs proceed to identity/address checks.'}
    (out/'extraction-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({'done':True,'counts':dict(counts)}),flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--archive',required=True);p.add_argument('--out',default='work/accreditation-xml');a=p.parse_args();extract(a.archive,a.out)
