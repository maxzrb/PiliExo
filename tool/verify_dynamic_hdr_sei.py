"""编译并在 Android 上运行固定 HEVC 动态 HDR 元数据解析样例。"""
from pathlib import Path
import argparse
import difflib
import os
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def run(command, **kwargs):
    result = subprocess.run([str(x) for x in command], capture_output=True, timeout=90, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace")[-4000:])
    return result.stdout.decode("utf-8").replace("\r\n", "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    compiler = parser.add_mutually_exclusive_group(required=True)
    compiler.add_argument("--ndk", type=Path)
    compiler.add_argument("--cc", type=Path, help="用主机 C 编译器运行同一组输入/参考输出")
    parser.add_argument("--serial")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.ndk and not args.serial:
        parser.error("Android NDK 模式需要 --serial")
    program = args.output.resolve() / ("dynamic-hdr-sei.exe" if args.cc and os.name == "nt" else "dynamic-hdr-sei")
    env = os.environ.copy()
    if args.cc:
        env["PATH"] = str(args.cc.resolve().parent) + os.pathsep + env.get("PATH", "")
        command = [args.cc, "-std=c11", "-Wall", "-Wextra", "-Werror"]
    else:
        ndk = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin"
        command = [ndk / "clang.exe", "--target=aarch64-linux-android28"]
    run([*command, "-I", ROOT / "patches/mpv", ROOT / "test/native/dynamic_hdr_fate.c", "-o", program], env=env)
    adb = ["adb", "-s", args.serial] if args.serial else []
    remote = "/data/local/tmp/piliexo-dynamic-hdr-sei"
    if args.ndk:
        run([*adb, "push", program, remote])
    try:
        if args.ndk:
            run([*adb, "shell", "chmod", "700", remote])
        sample = (ROOT / "test/fixtures/mpv_hdr/dynamic-sei.hex").read_bytes()
        command = [*adb, "shell", "-T", remote] if args.ndk else [program]
        actual = run(command, input=sample, env=env)
        (args.output / "mpv-hdr-dynamic-sei").write_text(actual, encoding="utf-8")
        expected = (ROOT / "test/ref/fate/mpv-hdr-dynamic-sei").read_text(encoding="utf-8")
        if actual != expected:
            raise AssertionError("".join(difflib.unified_diff(expected.splitlines(True), actual.splitlines(True))))
        print(f"PASS mpv-hdr-dynamic-sei: {len(actual.splitlines())} fixed metadata samples")
    finally:
        if args.ndk:
            run([*adb, "shell", "rm", "-f", remote])


if __name__ == "__main__":
    main()
