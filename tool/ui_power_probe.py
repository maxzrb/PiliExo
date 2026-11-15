"""在日常 Release 包上采集界面 CPU 与 Surface 提交，不修改显示设置。"""

import argparse
import json
import pathlib
import re
import shlex
import subprocess
import time


def parse_stat(text):
    match = re.match(r"^(\d+) \((.*)\) (.*)$", text.strip())
    if not match:
        return None
    fields = match[3].split()
    return {"tid": int(match[1]), "name": match[2],
            "ticks": int(fields[11]) + int(fields[12])}


def present_times(text):
    # 第二列为实际呈现时间；排除空槽和仍未完成的占位值。
    values = set()
    for line in text.splitlines()[1:]:
        fields = line.split()
        if len(fields) == 3 and all(field.isdigit() for field in fields):
            value = int(fields[1])
            if 0 < value < 2**63 - 1:
                values.add(value)
    return values


def foreground_errors(context):
    errors = []
    if not re.search(r"mScreenState=ON\b", context["display"]):
        errors.append("屏幕并非亮屏")
    if "mIsShowing=false" not in context["policy"]:
        errors.append("设备未解锁")
    if not re.search(r"ResumedActivity:.*com\.maxzrb\.piliexo/.*mVisible=true", context["activity"]):
        errors.append("应用未在可见前台")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--seconds", type=int, default=30)
    parser.add_argument("--scroll", action="store_true")
    parser.add_argument("--scroll-pairs", type=int, default=7)
    parser.add_argument("--x", type=int, default=540)
    parser.add_argument("--top", type=int, default=800)
    parser.add_argument("--bottom", type=int, default=1600)
    args = parser.parse_args()
    if not 5 <= args.seconds <= 90:
        parser.error("单窗口时长限定为5至90秒；静置实验应先确认自动息屏时间")
    if args.scroll_pairs < 1:
        parser.error("滑动往返次数必须为正数")
    root = pathlib.Path(args.output)
    root.mkdir(parents=True, exist_ok=False)
    command = ["adb", "-s", args.serial]

    def adb(*values, partial=False):
        result = subprocess.run(command + list(values), capture_output=True,
                                encoding="utf-8", errors="replace", timeout=20)
        if result.returncode and not partial:
            raise RuntimeError(result.stderr or result.stdout)
        return result.stdout

    def context():
        result = {name: adb("shell", "dumpsys", name)
                  for name in ("battery", "thermalservice", "display", "power")}
        result["policy"] = adb("shell", "dumpsys", "window", "policy")
        result["activity"] = "\n".join(line for line in adb("shell", "dumpsys", "activity", "activities").splitlines()
                                       if "ResumedActivity:" in line)
        return result

    pid = int(adb("shell", "pidof", "com.maxzrb.piliexo").split()[0])
    ticks = int(adb("shell", "getconf", "CLK_TCK"))
    layers = [line for line in adb("shell", "dumpsys", "SurfaceFlinger", "--list").splitlines()
              if line.startswith("SurfaceView[com.maxzrb.piliexo/") and "(BLAST)" in line]
    before = context()
    if errors := foreground_errors(before):
        raise RuntimeError("；".join(errors))
    if not layers:
        raise RuntimeError("没有找到应用 Surface；先核对前台页面")
    (root / "screen-before.png").write_bytes(subprocess.check_output(command + ["exec-out", "screencap", "-p"]))
    baseline = {layer: present_times(adb("shell", "dumpsys", "SurfaceFlinger", "--latency", shlex.quote(layer)))
                for layer in layers}
    observed = {layer: set() for layer in layers}
    samples = []
    start = time.monotonic()
    deadline = start + args.seconds
    swipe_count = 0
    with (root / "resources.jsonl").open("w", encoding="utf-8") as file:
        while True:
            sample = {"elapsed": time.monotonic() - start,
                      "aggregate": parse_stat(adb("shell", "cat", f"/proc/{pid}/stat")),
                      "threads": [value for line in adb("shell", "cat", f"/proc/{pid}/task/*/stat", partial=True).splitlines()
                                  if (value := parse_stat(line))]}
            sample["surfaceTimesNs"] = {}
            for layer in layers:
                text = adb("shell", "dumpsys", "SurfaceFlinger", "--latency", shlex.quote(layer))
                times = present_times(text)
                sample["surfaceTimesNs"][layer] = sorted(times)
                observed[layer].update(times - baseline[layer])
            samples.append(sample)
            file.write(json.dumps(sample, ensure_ascii=False) + "\n")
            file.flush()
            if time.monotonic() >= deadline:
                break
            if args.scroll and swipe_count < args.scroll_pairs * 2:
                y1, y2 = (args.bottom, args.top) if swipe_count % 2 == 0 else (args.top, args.bottom)
                adb("shell", "input", "swipe", str(args.x), str(y1), str(args.x), str(y2), "700")
                swipe_count += 1
            time.sleep(max(0, min(1, deadline - time.monotonic())))
    first, last = samples[0], samples[-1]
    elapsed = last["elapsed"] - first["elapsed"]
    old = {row["tid"]: row for row in first["threads"]}
    threads = [{"name": row["name"], "tid": row["tid"],
                "cpuCorePercent": (row["ticks"] - old[row["tid"]]["ticks"]) / ticks / elapsed * 100}
               for row in last["threads"] if row["tid"] in old]
    after = context()
    errors = foreground_errors(after)
    if args.scroll and swipe_count != args.scroll_pairs * 2:
        errors.append("未完成相同次数的往返滑动")
    if not adb("shell", "pidof", "com.maxzrb.piliexo").split()[0] == str(pid):
        errors.append("采样进程发生变化")
    (root / "screen-after.png").write_bytes(subprocess.check_output(command + ["exec-out", "screencap", "-p"]))
    result = {"pid": pid, "seconds": elapsed, "scroll": args.scroll,
              "swipes": swipe_count, "ticksPerSecond": ticks,
              "cpuCorePercent": (last["aggregate"]["ticks"] - first["aggregate"]["ticks"]) / ticks / elapsed * 100,
              "threads": sorted(threads, key=lambda row: -row["cpuCorePercent"]),
              "surfaceSubmissionsObserved": {layer: len(values) for layer, values in observed.items()},
              "surfaceBaselineSamples": {layer: len(values) for layer, values in baseline.items()},
              "surfaceMeasurement": "有限环形缓冲的观测下界；空数据不能证明零绘制；滚动时可能覆盖，不能据此计算实际 FPS。",
              "contextBefore": before, "contextAfter": after,
              "valid": not errors, "validationErrors": errors}
    (root / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: result[key] for key in ("valid", "validationErrors", "seconds", "cpuCorePercent", "swipes", "surfaceSubmissionsObserved")}, ensure_ascii=False), flush=True)
    print(json.dumps(result["threads"][:7], ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
