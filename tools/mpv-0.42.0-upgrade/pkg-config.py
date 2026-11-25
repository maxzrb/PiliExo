import ctypes
import os
from pathlib import Path
import re
import shlex
import sys

root = Path(__file__).resolve().parent
sysroot = os.environ.get('PKG_CONFIG_SYSROOT_DIR')
# 保留环境变量中的 Windows 短路径，避免 Path.resolve() 展开成含空格的目录。
prefix = Path(sysroot) if sysroot else (root / 'prefix').resolve()
if os.name == 'nt':
    short_path = ctypes.create_unicode_buffer(32768)
    length = ctypes.windll.kernel32.GetShortPathNameW(
        str(prefix),
        short_path,
        len(short_path),
    )
    if length:
        prefix = Path(short_path.value)
search = [Path(value) for value in os.environ.get('PKG_CONFIG_LIBDIR', '').split(os.pathsep) if value]
if not search:
    search = [prefix / 'lib/pkgconfig']
variables = {
    'prefix': str(prefix).replace('\\', '/'),
    'exec_prefix': '${prefix}',
    'libdir': '${prefix}/lib',
    'includedir': '${prefix}/include',
}

comparisons = ('>=', '<=', '!=', '=', '<', '>')


def load(name):
    for directory in search:
        path = directory / (name + '.pc')
        if not path.exists():
            continue
        values = dict(variables)
        entries = {}
        for line in path.read_text(encoding='utf-8').splitlines():
            stripped = line.lstrip()
            if not stripped or stripped.startswith('#'):
                continue
            if ':' in line:
                key, value = line.split(':', 1)
                entries[key.strip()] = value.strip()
            elif '=' in line:
                key, value = line.split('=', 1)
                if key.strip() in ('Name', 'Description', 'URL'):
                    continue
                values[key.strip()] = value.strip()
        # 当前前缀来自项目内的临时安装目录，原 pc 文件中的构建前缀不可复用。
        values['prefix'] = str(prefix).replace('\\', '/')
        return values, entries
    raise SystemExit(1)


def expand(value, values):
    for _ in range(20):
        expanded = re.sub(r'\$\{([^}]+)\}', lambda match: values.get(match[1], ''), value)
        if expanded == value:
            return expanded
        value = expanded
    return value


def version_key(value):
    parts = re.findall(r'\d+', value)
    return tuple(int(part) for part in parts)


def version_matches(current, operator, expected):
    left = version_key(current)
    right = version_key(expected)
    return {
        '>=': left >= right,
        '<=': left <= right,
        '>': left > right,
        '<': left < right,
        '=': left == right,
        '!=': left != right,
    }[operator]


def dependency_names(value):
    result = []
    tokens = shlex.split(value)
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in comparisons:
            index += 2
            continue
        if not token.startswith('-'):
            result.append(token)
        index += 1
    return result


def package_requirements(tokens):
    result = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in comparisons:
            index += 2
            continue
        if not token.startswith('-'):
            name = token
            operator = None
            expected = None
            if index + 2 < len(tokens) and tokens[index + 1] in comparisons:
                operator = tokens[index + 1]
                expected = tokens[index + 2]
                index += 2
            result.append((name, operator, expected))
        index += 1
    return result


def transitive_packages(name, static):
    result = []
    seen = set()

    def visit(package):
        if package in seen:
            return
        seen.add(package)
        values, entries = load(package)
        result.append((values, entries))
        for dependency in dependency_names(entries.get('Requires', '')):
            visit(dependency)
        if static:
            for dependency in dependency_names(entries.get('Requires.private', '')):
                visit(dependency)

    visit(name)
    return result


tokens = []
for argument in sys.argv[1:]:
    tokens.extend(shlex.split(argument))

if '--version' in tokens:
    print('1.8.0')
    raise SystemExit(0)

requirements = package_requirements(tokens)
if '--exists' in tokens:
    for name, operator, expected in requirements:
        _, entries = load(name)
        if operator and not version_matches(entries.get('Version', ''), operator, expected):
            raise SystemExit(1)
    raise SystemExit(0)

if not requirements:
    raise SystemExit(1)

name = requirements[-1][0]
values, entries = load(name)
if '--modversion' in tokens:
    print(entries.get('Version', ''))
    raise SystemExit(0)
variable = next((token for token in tokens if token.startswith('--variable=')), None)
if variable:
    key = variable.split('=', 1)[1]
    print(expand(values.get(key, ''), values))
    raise SystemExit(0)

static = '--static' in tokens
packages = transitive_packages(name, static)
parts = []
if '--libs' in tokens:
    for package_values, package_entries in packages:
        parts.append(expand(package_entries.get('Libs', ''), package_values))
        if static:
            parts.append(expand(package_entries.get('Libs.private', ''), package_values))
else:
    for package_values, package_entries in packages:
        parts.append(expand(package_entries.get('Cflags', ''), package_values))

result = ' '.join(part for part in parts if part)
# 项目统一使用不含空格的 8.3 前缀；去掉 pc 文件里的展示用引号，
# 避免命令替换后把引号原样传给 Clang。
result = result.replace('"', '')
if '--cflags-only-I' in tokens:
    result = ' '.join(token for token in shlex.split(result) if token.startswith('-I'))
elif '--libs-only-l' in tokens:
    result = ' '.join(token for token in shlex.split(result) if token.startswith('-l'))
print(result)
