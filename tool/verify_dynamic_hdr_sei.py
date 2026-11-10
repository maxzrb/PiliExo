"""编译并在 Android 上运行固定 HEVC 动态 HDR 元数据解析样例。"""
from pathlib import Path
import argparse
import difflib
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def run(command, **kwargs):
    result = subprocess.run([str(x) for x in command], capture_output=True, timeout=90, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace")[-4000:])
    return result.stdout.decode("utf-8").replace("\r\n", "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    ndk = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin"
    program = args.output / "dynamic-hdr-sei"
    run([
        ndk / "clang.exe",
        "--target=aarch64-linux-android28",
        "-I", ROOT / "patches/mpv",
        ROOT / "test/native/dynamic_hdr_fate.c",
        "-o", program,
    ])
    adb = ["adb", "-s", args.serial]
    remote = "/data/local/tmp/piliexo-dynamic-hdr-sei"
    run([*adb, "push", program, remote])
    try:
        run([*adb, "shell", "chmod", "700", remote])
        sample = (ROOT / "test/fixtures/mpv_hdr/dynamic-sei.hex").read_bytes()
        actual = run([*adb, "shell", "-T", remote], input=sample)
        (args.output / "mpv-hdr-dynamic-sei").write_text(actual, encoding="utf-8")
        expected = (ROOT / "test/ref/fate/mpv-hdr-dynamic-sei").read_text(encoding="utf-8")
        if actual != expected:
            raise AssertionError("".join(difflib.unified_diff(expected.splitlines(True), actual.splitlines(True))))
        print(f"PASS mpv-hdr-dynamic-sei: {len(actual.splitlines())} fixed metadata samples")
    finally:
        run([*adb, "shell", "rm", "-f", remote])


if __name__ == "__main__":
    main()
