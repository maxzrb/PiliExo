"""接入显式界面研究包，分析同缓存列表静置/滚动的磨砂 ABBA。"""

import argparse
import json
import pathlib
import subprocess
import time

from playback_power_probe import parse_gpu_busy, gpu_busy_summary
from ui_power_probe import foreground_errors, parse_stat


def summarize(events, samples, pid, ticks):
    phases = []
    for start in (event for event in events if event["event"] == "phase_start"):
        end = next((event for event in events if event["event"] == "phase_end"
                    and event["label"] == start["label"]), None)
        if end is None:
            continue
        points = [point for point in samples if point["pid"] == pid and
                  start["epochMs"] + 1000 <= point["epochMs"] <= end["epochMs"] - 1000]
        errors = []
        phase = {"start": start, "end": end, "resourceSamples": len(points)}
        if any("gpuBusy" in point for point in points):
            phase["gpuBusy"] = gpu_busy_summary(points)
        if len(points) < 10:
            errors.append("CPU采样不足")
        else:
            first, last = points[0], points[-1]
            elapsed = (last["epochMs"] - first["epochMs"]) / 1000
            phase["cpuCorePercent"] = (last["aggregate"]["ticks"] - first["aggregate"]["ticks"]) / ticks / elapsed * 100
            old = {row["tid"]: row for row in first["threads"]}
            threads = [{"name": row["name"], "tid": row["tid"],
                        "cpuCorePercent": (row["ticks"] - old[row["tid"]]["ticks"]) / ticks / elapsed * 100}
                       for row in last["threads"] if row["tid"] in old]
            phase["threads"] = sorted(threads, key=lambda row: -row["cpuCorePercent"])
        if abs(start["offset"] - 100) > 1 or abs(end["offset"] - 100) > 1:
            errors.append("起止列表位置未对齐")
        if end["cycles"] != (10 if start["moving"] else 0):
            errors.append("滚动次数不一致")
        if not 19900 <= end["durationMs"] <= 21000:
            errors.append("窗口时长异常")
        phase["validationErrors"] = errors
        phase["valid"] = not errors
        phases.append(phase)
    return phases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--launch", action="store_true")
    parser.add_argument("--gpu-busy", action="store_true", help="可选KGSL整机GPU忙碌计数，不是功率")
    args = parser.parse_args()
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

    log = root / "logcat.txt"
    events = []
    samples = []
    pid = None
    ticks = int(adb("shell", "getconf", "CLK_TCK"))
    offset = float(adb("shell", "date", "+%s.%N")) * 1000 - time.time() * 1000
    before = context()
    status = "timeout"
    with log.open("w", encoding="utf-8") as output, (root / "resources.jsonl").open("w", encoding="utf-8") as resources:
        process = subprocess.Popen(command + ["logcat", "-v", "epoch", "-T", "1", "flutter:I", "*:S"],
                                   stdout=output, stderr=subprocess.DEVNULL)
        try:
            if args.launch:
                adb("shell", "am", "start", "-n", "com.maxzrb.piliexo/.MainActivity")
            deadline = time.monotonic() + 300
            while time.monotonic() < deadline:
                events = []
                for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
                    if "PILI_UI_POWER " in line:
                        try:
                            events.append(json.loads(line.split("PILI_UI_POWER ", 1)[1]))
                        except ValueError:
                            pass
                ending = next((event for event in reversed(events) if event["event"] in ("complete", "aborted")), None)
                if ending:
                    status = ending["event"]
                    break
                value = adb("shell", "pidof", "com.maxzrb.piliexo", partial=True).strip()
                if value:
                    pid = int(value.split()[0])
                    begin = time.time() * 1000
                    aggregate = parse_stat(adb("shell", "cat", f"/proc/{pid}/stat"))
                    threads = [row for line in adb("shell", "cat", f"/proc/{pid}/task/*/stat", partial=True).splitlines()
                               if (row := parse_stat(line))]
                    sample = {"epochMs": (begin + time.time() * 1000) / 2 + offset,
                              "pid": pid, "aggregate": aggregate, "threads": threads}
                    if args.gpu_busy:
                        gpu = adb("shell", "cat", "/sys/class/kgsl/kgsl-3d0/gpubusy", "/sys/class/kgsl/kgsl-3d0/gpuclk", partial=True).splitlines()
                        sample["gpuBusy"] = parse_gpu_busy(gpu[0]) if gpu else None
                        sample["gpuFrequencyHz"] = int(gpu[1]) if len(gpu) > 1 and gpu[1].strip().isdecimal() else None
                    samples.append(sample)
                    resources.write(json.dumps(sample, ensure_ascii=False) + "\n")
                    resources.flush()
                time.sleep(1)
        except Exception as error:
            status = f"collector_error: {error}"
        finally:
            process.terminate()
            process.wait(timeout=5)
    after = context()
    phases = summarize(events, samples, pid, ticks)
    errors = foreground_errors(after)
    result = {"status": status, "pid": pid, "ticksPerSecond": ticks,
              "contextBefore": before, "contextAfter": after, "events": events, "phases": phases,
              "validationErrors": errors,
              "valid": status == "complete" and not errors and len(phases) == 8 and all(phase["valid"] for phase in phases)}
    (root / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    for phase in phases:
        print(phase["start"]["label"], phase.get("cpuCorePercent"), phase["end"], phase["validationErrors"], flush=True)
    print("实验有效：", result["valid"], status, flush=True)


if __name__ == "__main__":
    main()
