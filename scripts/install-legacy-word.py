"""Install only the pinned Maven artifacts used by the local DOC reader."""
import argparse,hashlib,json,pathlib,re,urllib.request
parser=argparse.ArgumentParser();parser.add_argument('--runtime',default='work/poi-runtime');args=parser.parse_args()
root=pathlib.Path(args.runtime);root.mkdir(parents=True,exist_ok=True)
for dep in json.loads(pathlib.Path(__file__).with_name('legacy-doc-lock.json').read_text()):
    assert dep['url'].startswith('https://repo.maven.apache.org/maven2/')
    assert re.fullmatch(r'[A-Za-z0-9_.-]+',dep['artifact']) and re.fullmatch(r'[A-Za-z0-9_.-]+',dep['version'])
    target=root/f"{dep['artifact']}-{dep['version']}.jar"
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()==dep['sha256']:continue
    data=urllib.request.urlopen(dep['url'],timeout=30).read()
    assert len(data)<=20000000 and hashlib.sha256(data).hexdigest()==dep['sha256'],'Artifact checksum mismatch'
    temporary=target.with_suffix('.tmp');temporary.write_bytes(data);temporary.replace(target)
print('Pinned Apache POI runtime is ready')
