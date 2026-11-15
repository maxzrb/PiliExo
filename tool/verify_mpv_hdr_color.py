"""FATE 风格固定输入/参考输出：在 Android 离屏 EGL 中核验实际 libplacebo 颜色映射。"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import subprocess

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / 'test/fixtures/mpv_hdr'
REFS = ROOT / 'test/ref/fate'


def run(command, **kwargs):
    result = subprocess.run([str(x) for x in command], capture_output=True, timeout=90, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace')[-4000:])
    return result.stdout.decode('utf-8').replace('\r\n', '\n')


def rows(text):
    return [[float(x) for x in line.split()] for line in text.strip().splitlines()]


def compare(actual, reference, tolerance):
    left, right = rows(actual), rows(reference)
    assert len(left) == len(right), (len(left), len(right))
    maximum = 0.0
    for a, b in zip(left, right):
        assert len(a) == len(b) and a[0] == b[0], (a, b)
        assert all(math.isfinite(x) for x in a), a
        error = max(abs(x-y) for x, y in zip(a[1:], b[1:]))
        assert error <= tolerance, (a, b, error, tolerance)
        maximum = max(maximum, error)
    return maximum


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, required=True, help='候选 mpv 使用的 arm64 libplacebo 静态依赖前缀')
    parser.add_argument('--mpv-source', type=Path, required=True, help='已应用仓库 EGL 补丁的 mpv 源码目录')
    parser.add_argument('--ndk', type=Path, required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--output', type=Path, default=ROOT/'tmp/mpv-hdr-color-fate')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((FIXTURES/'color-samples.json').read_text(encoding='utf-8'))
    for name, expected in manifest['files'].items():
        assert hashlib.sha256((FIXTURES/name).read_bytes()).hexdigest() == expected, name
    ndk = args.ndk/'toolchains/llvm/prebuilt/windows-x86_64'
    runtime = ndk/'sysroot/usr/lib/aarch64-linux-android'
    binary = args.output/'hdr-color-fate'
    run([ndk/'bin/clang.exe', '--target=aarch64-linux-android28', '-DPL_STATIC',
         '-I', args.prefix/'include', '-I', args.mpv_source,
         ROOT/'test/native/mpv_hdr_color_fate.c', args.prefix/'lib/libplacebo.a',
         runtime/'libc++_static.a', runtime/'libc++abi.a',
         '-lEGL', '-lGLESv3', '-llog', '-landroid', '-lm', '-ldl', '-o', binary])
    adb = ['adb', '-s', args.serial]
    remote = '/data/local/tmp/piliexo-hdr-color-fate'
    results = {'libplaceboSha256': hashlib.sha256((args.prefix/'lib/libplacebo.a').read_bytes()).hexdigest(),
               'hdrHeaderSha256': hashlib.sha256((args.mpv_source/'video/out/opengl/android_hdr.h').read_bytes()).hexdigest(),
               'device': args.serial, 'tests': {}}
    run([*adb, 'push', binary, remote])
    try:
        run([*adb, 'shell', 'chmod', '700', remote])
        for name, fixture, options, tolerance in [
            ('mpv-hdr-pq-color', 'pq-color-input.txt', ['10000', 'clip'], manifest['rgbTolerance']),
            ('mpv-hdr-hlg-color', 'hlg-color-input.txt', ['1000', 'clip', 'hlg'], manifest['rgbTolerance']),
            ('mpv-hdr-egl-metadata', 'hdr-metadata-input.txt', ['--metadata'], 0),
        ]:
            actual = run([*adb, 'shell', '-T', remote, *options], input=(FIXTURES/fixture).read_bytes())
            (args.output/name).write_text(actual, encoding='utf-8')
            maximum = compare(actual, (REFS/name).read_text(encoding='utf-8'), tolerance)
            results['tests'][name] = {'passed': True, 'maxError': maximum, 'tolerance': tolerance}
            print(f'PASS {name}: maxError={maximum:.9f}, tolerance={tolerance:.9f}')
        # 旧策略只作差异证据；不把它的输出写入固定参考。
        old = run([*adb, 'shell', '-T', remote, '460', 'auto'], input=(FIXTURES/'pq-color-input.txt').read_bytes())
        (args.output/'old-460-auto').write_text(old, encoding='utf-8')
        old_rows = rows(old)
        def nits(code):
            x = max(code, 0)**(32/2523)
            return 10000*(max(x-3424/4096, 0)/(2413/128-(2392/128)*x))**(16384/2610)
        results['oldPolicyGrayNits'] = {str(level): round(nits(old_rows[i][1]), 3)
            for i, level in enumerate(manifest['pqNits']) if level in [100, 203, 460, 1000]}
        assert abs(old_rows[8][1]-rows((REFS/'mpv-hdr-pq-color').read_text(encoding='utf-8'))[8][1]) > 0.01
    finally:
        run([*adb, 'shell', 'rm', '-f', remote])
    (args.output/'verification.json').write_text(json.dumps(results, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(results['oldPolicyGrayNits'], ensure_ascii=False))
    print('离屏数值核验通过；不替代候选 App 的 EGL 元数据提交和屏幕观感验收。')


if __name__ == '__main__':
    main()
