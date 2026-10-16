"""Extract table structure with a pinned, read-only Apache POI process."""
import argparse,concurrent.futures,hashlib,json,pathlib,shutil,subprocess,os
def digest(data):return hashlib.sha256(data).hexdigest()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',required=True);parser.add_argument('--runtime',default='work/poi-runtime');args=parser.parse_args()
    runtime=pathlib.Path(args.runtime).resolve();java=shutil.which('java');assert java,'Java runtime required'
    for dep in json.loads(pathlib.Path('scripts/legacy-doc-lock.json').read_text()):
        assert digest((runtime/f"{dep['artifact']}-{dep['version']}.jar").read_bytes())==dep['sha256'],'Runtime checksum mismatch'
    source=pathlib.Path('scripts/ReadLegacyWord.java');reader_hash=digest(source.read_bytes())
    javac=str(pathlib.Path(java).with_name('javac.exe' if pathlib.Path(java).suffix=='.exe' else 'javac'))
    subprocess.run([javac,'-encoding','UTF-8','-cp',str(runtime/'*'),'-d',str(runtime),str(source)],check=True,timeout=30,capture_output=True)
    files=[]
    for file in (pathlib.Path(args.root)/'documents').glob('*.json'):
        meta=json.loads(file.read_text(encoding='utf-8'))
        if meta['format']=='doc' and meta['status']=='downloaded':files.append((file,meta))
    def one(item):
        file,meta=item;raw=pathlib.Path(meta['file']);output=pathlib.Path(str(raw)+'.tables.xml')
        try:
            assert digest(raw.read_bytes())==meta['sha256'],'Source checksum mismatch'
            result=subprocess.run([java,'-Xmx256m','-Djava.awt.headless=true','-cp',str(runtime)+os.pathsep+str(runtime/'*'),'ReadLegacyWord',str(raw.resolve()),str(output.resolve())],capture_output=True,timeout=20)
            if result.returncode:raise ValueError('legacy_reader_rejected_document')
            xml=output.read_bytes()
            if len(xml)>24000000 or not xml.startswith(b'<?xml'):raise ValueError('legacy_output_limit_or_format')
            meta.update(doc_tables_file=str(output),doc_tables_sha256=digest(xml),doc_reader_sha256=reader_hash,doc_reader_version=1)
            temporary=file.with_suffix('.tmp');temporary.write_text(json.dumps(meta,ensure_ascii=False),encoding='utf-8');temporary.replace(file)
            return 'tables_extracted'
        except Exception as error:return type(error).__name__+': '+str(error)[:80]
    outcomes={}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(one,files):outcomes[result]=outcomes.get(result,0)+1
    report={'documents':len(files),'outcomes':outcomes,'reader':'Apache POI HWPF 5.5.1; bounded read-only processes, no Office automation or macro execution','reader_sha256':reader_hash}
    (pathlib.Path(args.root)/'legacy-read-report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
if __name__=='__main__':main()
