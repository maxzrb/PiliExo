"""打包同一ABI的定制mpv库，校验原签名、文件一致性、架构与16KB对齐。"""
from pathlib import Path
import zipfile, subprocess, os, hashlib, json

root = Path(__file__).parent
import argparse
parser=argparse.ArgumentParser()
parser.add_argument('--base',type=Path,required=True)
parser.add_argument('--native',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
parser.add_argument('--abi',choices=['arm64-v8a','armeabi-v7a'],required=True)
parser.add_argument('--tools',type=Path,required=True)
parser.add_argument('--key-properties',type=Path,default=root.parent.parent/'android/key.properties')
parser.add_argument('--expected-native-sha256',required=True)
args=parser.parse_args()
native=args.native
base=args.base
tools=args.tools
out=args.out
out.parent.mkdir(parents=True,exist_ok=True)
unsigned=out.with_suffix('.unsigned.apk')
aligned=out.with_suffix('.aligned.apk')
assert hashlib.sha256(native.read_bytes()).hexdigest()==args.expected_native_sha256
# 在签名前校验ELF架构，避免误将64位库放入32位安装包。
import struct
header=native.read_bytes()[:64]
assert header[:4]==b'\x7fELF'
expected=(2,183) if args.abi=='arm64-v8a' else (1,40)
assert (header[4],struct.unpack_from('<H',header,18)[0])==expected
out=args.out
entry = 'lib/'+args.abi+'/libmpv.so'
removed=[]
with zipfile.ZipFile(base) as src, zipfile.ZipFile(unsigned, 'w') as dst:
    assert entry in src.namelist(), 'Base APK is missing requested mpv ABI'
    assert 'lib/'+args.abi+'/libapp.so' in src.namelist(), 'Base APK is missing requested Dart AOT ABI'
    for item in src.infolist():
        if item.filename.startswith('lib/') and not item.filename.startswith('lib/'+args.abi+'/'):
            removed.append(item.filename)
            continue
        if item.filename.startswith('META-INF/') and item.filename.upper().endswith(('.SF', '.RSA', '.DSA', '.EC', 'MANIFEST.MF')):
            continue
        dst.writestr(item, native.read_bytes() if item.filename == entry else src.read(item))
subprocess.run([str(tools/'zipalign.exe'), '-P', '16', '-f', '4', str(unsigned), str(aligned)], check=True)
keyfile = args.key_properties
props = dict(line.split('=', 1) for line in keyfile.read_text(encoding='utf-8').splitlines() if '=' in line and not line.startswith('#'))
store = Path(props['storeFile'].replace('\\\\', '\\').replace('\\:', ':'))
if not store.is_absolute():
    store = (keyfile.parent/'app'/store).resolve()
assert store.exists()
# 密码只经子进程环境传递，不输出、不写入实验记录。
env = os.environ.copy()
env.update(PILIEXO_STORE_PASS=props['storePassword'], PILIEXO_KEY_PASS=props['keyPassword'])
subprocess.run([str(tools/'apksigner.bat'), 'sign', '--ks', str(store), '--ks-key-alias', props['keyAlias'], '--ks-pass', 'env:PILIEXO_STORE_PASS', '--key-pass', 'env:PILIEXO_KEY_PASS', '--v1-signing-enabled', 'false', '--v2-signing-enabled', 'true', '--v3-signing-enabled', 'false', '--v4-signing-enabled', 'false', '--out', str(out), str(aligned)], env=env, check=True, capture_output=True)
certs = []
for apk in [base, out]:
    result = subprocess.run([str(tools/'apksigner.bat'), 'verify', '--print-certs', str(apk)], capture_output=True, text=True, check=True)
    certs.append(next(line.split('digest: ')[1] for line in result.stdout.splitlines() if 'certificate SHA-256 digest:' in line))
assert certs[0] == certs[1]
with zipfile.ZipFile(base) as src, zipfile.ZipFile(out) as dst:
    unchanged = [i.filename for i in src.infolist() if i.filename != entry and not i.filename.startswith('META-INF/') and i.filename not in removed]
    assert all(src.read(n) == dst.read(n) for n in unchanged)
    assert dst.read(entry) == native.read_bytes()
subprocess.run([str(tools/'zipalign.exe'), '-c', '-P', '16', '4', str(out)], check=True)
meta = {'apk': str(out), 'sha256': hashlib.sha256(out.read_bytes()).hexdigest(), 'bytes': out.stat().st_size, 'nativeSha256': hashlib.sha256(native.read_bytes()).hexdigest(), 'unchangedEntries': len(unchanged), 'sameSigningCertificate': True, 'removedOtherAbiEntries': removed}
out.with_suffix('.artifact.json').write_text(json.dumps(meta, indent=2), encoding='utf-8')
print(json.dumps(meta))
