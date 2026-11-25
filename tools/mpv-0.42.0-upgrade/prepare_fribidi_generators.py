from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent
build = root / 'build/fribidi-arm64-final'
source = root / 'sources/fribidi-1.0.16'
compatibility = root / 'build/windows-headers'
compatibility.mkdir(exist_ok=True)
(compatibility / 'strings.h').write_text('#pragma once\n#include <string.h>\n', encoding='ascii')
programs = ['gen-unicode-version']
programs += ['gen-' + name + '-tab' for name in (
    'bidi-type', 'joining-type', 'arabic-shaping', 'mirroring', 'brackets', 'brackets-type')]
unicode_version = build / 'gen.tab' / 'fribidi-unicode-version.h'
version_result = subprocess.run(
    [str(build / 'gen.tab/gen-unicode-version.exe'),
     str(source / 'gen.tab/unidata/ReadMe.txt'),
     str(source / 'gen.tab/unidata/BidiMirroring.txt')],
    capture_output=True, check=True,
)
unicode_version.write_bytes(version_result.stdout)
for program in programs:
    output = build / 'gen.tab' / (program + '.exe')
    sources = [source / 'gen.tab' / (program + '.c')]
    if program != 'gen-unicode-version':
        sources.append(source / 'gen.tab' / 'packtab.c')
    if program == 'gen-unicode-version' and unicode_version.exists():
        print('Unicode 版本表已生成', flush=True)
        continue
    command = [
        'cl', '/nologo', '/MD', '/O2', '/I', str(source), '/I', str(source / 'lib'),
        '/I', str(compatibility), '/I', str(build), '/I', str(build / 'gen.tab'),
        '/DHAVE_STRINGIZE', '/DDONT_HAVE_FRIBIDI_CONFIG_H', '/DHAVE_STDLIB_H',
        '/DHAVE_STRING_H', '/DHAVE_STRINGS_H', '/DSTDC_HEADERS=1',
        '/Fe:' + str(output), *map(str, sources),
    ]
    print(program, flush=True)
    subprocess.run(command, check=True, cwd=build)
