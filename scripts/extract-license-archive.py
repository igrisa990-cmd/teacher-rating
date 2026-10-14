"""Stream the whole public license ZIP, keep only current general-education organizations."""
import argparse,collections,json,pathlib,re,zipfile
from lxml import etree
GENERAL=re.compile(r'^(Начальное|Основное|Среднее(?: \(полное\))?) общее образование$',re.I)
def value(node,key):return (node.findtext(key) or '').strip()
def extract(archive,out):
    out=pathlib.Path(out);out.mkdir(parents=True,exist_ok=True);counts=collections.Counter();statuses=collections.Counter();samples=[]
    with zipfile.ZipFile(archive) as z:
        entries=[i for i in z.infolist() if i.filename.lower().endswith('.xml')]
        if len(entries)!=1 or entries[0].file_size>3000000000:raise ValueError('Unexpected archive')
        with z.open(entries[0]) as stream,open(out/'active-general.ndjson','w',encoding='utf-8') as dest:
            for _,e in etree.iterparse(stream,events=('end',),tag='license',load_dtd=False,no_network=True,resolve_entities=False,huge_tree=False):
                counts['licenses']+=1;status=value(e,'statusName');statuses[status]+=1
                if status=='Действует':
                    counts['active']+=1;programs=[];guid=value(e,'schoolGuid');matching_supplements=0
                    for supplement in e.findall('supplements/supplement'):
                        if value(supplement,'statusName')!='Valid' or value(supplement,'schoolGuid')!=guid:continue
                        matching_supplements+=1
                        for program in supplement.findall('licensedPrograms/licensedProgram'):
                            level=value(program,'eduLevelName')
                            if GENERAL.fullmatch(level):programs.append(level)
                    if programs:
                        counts['active_general']+=1
                        d={'id':value(e,'sysGuid'),'schoolGuid':guid,'status':status,'name':value(e,'schoolName'),'shortName':value(e,'shortName'),'ogrn':value(e,'Ogrn'),'address':value(e,'lawAddress'),'license':value(e,'regNum'),'date':value(e,'dateLicDoc'),'dateEnd':value(e,'dateEnd'),'authority':value(e,'orgName'),'programs':sorted(set(programs))}
                        dest.write(json.dumps(d,ensure_ascii=False)+'\n')
                        if len(samples)<3:samples.append(d)
                    else:counts['active_without_current_nonbranch_general']+=1
                if counts['licenses']%25000==0:print(json.dumps(dict(counts)),flush=True)
                e.clear()
                while e.getprevious() is not None:del e.getparent()[0]
    report={'archive':str(archive),'xmlEntry':entries[0].filename,'xmlBytes':entries[0].file_size,'counts':dict(counts),'statuses':dict(statuses),'samples':samples,'coverage':'Every license inspected. Only active licenses with valid non-branch main-organization general programs proceed. No private contacts or staff data.'}
    (out/'extraction-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({'done':True,'counts':dict(counts)}),flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--archive',required=True);p.add_argument('--out',default='work/license-xml');a=p.parse_args();extract(a.archive,a.out)
