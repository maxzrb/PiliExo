"""固定 CTA-861.3 输入与参考输出，核验 FFmpeg MediaCodec HDR 静态元数据解析。"""
from pathlib import Path
import argparse
import difflib
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def run(command, **kwargs):
    result = subprocess.run([str(x) for x in command], capture_output=True, timeout=60, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace')[-4000:])
    return result.stdout.decode('utf-8').replace('\r\n', '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg-source', type=Path, required=True)
    parser.add_argument('--prefix', type=Path, required=True)
    parser.add_argument('--ndk', type=Path, required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--output', type=Path, default=ROOT/'tmp/mediacodec-hdr-fate')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    fixture_dir = ROOT/'test/fixtures/mpv_hdr'
    manifest = json.loads((fixture_dir/'mediacodec-hdr-static.json').read_text(encoding='utf-8'))
    sample = (fixture_dir/manifest['file']).read_bytes()
    assert hashlib.sha256(sample).hexdigest() == manifest['sha256']
    ndk = args.ndk/'toolchains/llvm/prebuilt/windows-x86_64'
    program = args.output/'mediacodec-hdr-fate'
    run([ndk/'bin/clang.exe', '--target=aarch64-linux-android28',
         '-I', args.ffmpeg_source, '-I', args.prefix/'include', ROOT/'test/native/mediacodec_hdr_fate.c',
         args.prefix/'lib/libavutil.a', '-lm', '-ldl', '-llog', '-landroid', '-o', program])
    adb = ['adb', '-s', args.serial]
    remote = '/data/local/tmp/piliexo-mediacodec-hdr-fate'
    run([*adb, 'push', program, remote])
    try:
        run([*adb, 'shell', 'chmod', '700', remote])
        actual = run([*adb, 'shell', '-T', remote], input=sample)
        name = 'mediacodec-hdr-static-info'
        (args.output/name).write_text(actual, encoding='utf-8')
        expected = (ROOT/'test/ref/fate'/name).read_text(encoding='utf-8')
        if actual != expected:
            raise AssertionError(''.join(difflib.unified_diff(expected.splitlines(True), actual.splitlines(True))))
        verification = {'passed': True, 'samples': len(manifest['cases']), 'inputSha256': manifest['sha256'],
            'headerSha256': hashlib.sha256((args.ffmpeg_source/'libavcodec/mediacodec_hdr.h').read_bytes()).hexdigest()}
        (args.output/'verification.json').write_text(json.dumps(verification, indent=2)+'\n', encoding='utf-8')
        print(f'PASS {name}: {len(manifest["cases"])} fixed inputs, identical reference output')
    finally:
        run([*adb, 'shell', 'rm', '-f', remote])


if __name__ == '__main__':
    main()
