"""通过 ADB 对诊断构建执行固定视频的长按对照，输出 UTF-8 原始日志和统计。"""

import argparse
import json
import pathlib
import re
import statistics
import subprocess
import time


def adb(*args, timeout=30):
    result = subprocess.run(
        ["adb", *args], capture_output=True, encoding="utf-8", errors="replace",
        timeout=timeout, check=True,
    )
    return result.stdout


def device_ms():
    return float(adb("shell", "date", "+%s.%N").strip()) * 1000


def stop_app(package):
    try:
        adb("shell", "am", "force-stop", package)
    except (subprocess.SubprocessError, OSError) as error:
        # 设备断连时仍需保存结果，不能让清理异常覆盖实验中的原始错误。
        print(f"停止应用失败：{error}", flush=True)


def device_context(directory, name):
    result = {"hostEpochMs": time.time_ns() // 1_000_000}
    for key, command in {
        "battery": ("shell", "dumpsys", "battery"),
        "thermal": ("shell", "dumpsys", "thermalservice"),
    }.items():
        try:
            result[key] = adb(*command)
        except (subprocess.SubprocessError, OSError) as error:
            result[key] = {"error": str(error)}
    # USB 充电状态仅作为实验条件，不能据此把电池电流解释为整机功耗。
    (directory / f"context-{name}.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8",
    )
    return result


def records(path):
    result = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "PILI_PLAYBACK " not in line:
            continue
        try:
            result.append(json.loads(line.split("PILI_PLAYBACK ", 1)[1]))
        except json.JSONDecodeError:
            continue
    return result


def percentile(values, fraction):
    return sorted(values)[min(len(values) - 1, int(len(values) * fraction))] if values else None


def diagnostic_pid(text):
    # 只接受本次诊断日志中唯一的应用进程，不能混入其他播放器或上次实例。
    values = {int(match[1]) for line in text.splitlines()
              if (match := re.search(r"^\s*[\d.]+\s+(\d+)\s+\d+.*flutter.*PILI_PLAYBACK ", line))}
    return next(iter(values)) if len(values) == 1 else None


def video_codec_rows(text, pid, decoder):
    if pid is None:
        return []
    pattern = re.compile(r"^\s*(\d+\.\d+)\s+(\d+)\s+\d+.*TraceLog.*\("
                         + re.escape(decoder)
                         + r":[^)]*\) Queued: ([\d.]+)/s Done: ([\d.]+)/s Rendered: ([\d.]+)/s Discarded: ([\d.]+)/s")
    return [[float(match[1]), *map(float, match.groups()[2:])]
            for line in text.splitlines()
            if (match := pattern.search(line)) and int(match[2]) == pid]


def phase_statistics(samples, start, end):
    selected = [x for x in samples if start + 1500 <= x["epochMs"] <= end - 500]
    result = {"samples": len(selected)}
    for key in ("video-pts", "audio-pts", "positionMs"):
        slopes = []
        for a, b in zip(selected, selected[1:]):
            va, vb = a.get(key), b.get(key)
            elapsed = (b["elapsedUs"] - a["elapsedUs"]) / 1_000_000
            if va is not None and vb is not None and elapsed > 0:
                slopes.append((vb - va) / elapsed / (1000 if key == "positionMs" else 1))
        result[key + "-rate-median"] = statistics.median(slopes) if slopes else None
    avsync = [abs(x["avsync"]) for x in selected if x.get("avsync") is not None]
    result["avsync-p95-seconds"] = percentile(avsync, .95)
    result["query-p95-us"] = percentile([x["queryUs"] for x in selected], .95)
    if selected:
        result["max-flutter-build-us"] = max(x["maxBuildUs"] for x in selected)
        result["max-flutter-raster-us"] = max(x["maxRasterUs"] for x in selected)
        result["configured-speeds"] = sorted({x["speed"] for x in selected if x.get("speed") is not None})
        for key in ("frame-drop-count", "decoder-frame-drop-count", "mistimed-frame-count"):
            first, last = selected[0].get(key), selected[-1].get(key)
            result[key + "-delta"] = last - first if first is not None and last is not None else None
    return result


def run_round(args, index):
    directory = args.output / f"round-{index}"
    directory.mkdir(parents=True, exist_ok=False)
    log_path = directory / "logcat.txt"
    if not args.attach:
        adb("shell", "am", "force-stop", args.package)
    context_before = device_context(directory, "before")
    phases = []
    with log_path.open("w", encoding="utf-8") as output:
        logcat = subprocess.Popen(
            ["adb", "logcat", "-v", "epoch", "-T", "1", "flutter:I", "TraceLog:W",
             "CCodec:D", "CCodecConfig:D", "IHnMediaCodecService:D", "*:S"],
            stdout=output, stderr=subprocess.DEVNULL,
        )
        try:
            if not args.attach:
                uri = f"https://www.bilibili.com/video/{args.bvid}/?t={args.start_seconds}"
                adb("shell", "am", "start", "-W", "-n", f"{args.package}/.MainActivity",
                    "-a", "android.intent.action.VIEW", "-d", uri)
            deadline = time.monotonic() + 60
            while True:
                data = records(log_path)
                sources = [x for x in data if x["event"] == "source" and x.get("bvid") == args.bvid]
                samples = [x for x in data if x["event"] == "sample"]
                recent = samples[-3:]
                # 初始 seek 会先写入目标位置；必须等音频启动、画面进度连续推进。
                if ((sources or args.attach) and len(recent) == 3
                        and all(x.get("audio-pts") is not None for x in recent)
                        and recent[-1]["positionMs"] > args.start_seconds * 1000 + 1000
                        and all(b["positionMs"] > a["positionMs"] for a, b in zip(recent, recent[1:]))):
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError("60秒内没有获得目标视频诊断数据；请查看日志和手机播放状态")
                time.sleep(.5)
            for name, duration in (("normal", args.normal_seconds),
                                   ("hold", args.hold_seconds),
                                   ("recovery", args.recovery_seconds)):
                start = device_ms()
                if name == "hold":
                    # 使用已确认的竖屏播放器坐标，只按住，不产生拖动。
                    adb("shell", "input", "swipe", str(args.x), str(args.y),
                        str(args.x), str(args.y), str(int(duration * 1000)))
                else:
                    time.sleep(duration)
                phases.append({"name": name, "startMs": start, "endMs": device_ms()})
                print(f"第{index}轮 {name} 完成", flush=True)
            adb("shell", "cmd", "media_session", "dispatch", "pause")
            time.sleep(.5)
        finally:
            # 部分设备不会立即响应媒体按键；停止实验应用保证下一轮没有旧会话。
            stop_app(args.package)
            logcat.terminate()
            logcat.wait(timeout=5)
    context_after = device_context(directory, "after")
    data = records(log_path)
    samples = [x for x in data if x["event"] == "sample"]
    sources = [x for x in data if x["event"] == "source"]
    result = {"round": index, "sources": sources, "phases": phases,
              "contextBefore": context_before, "contextAfter": context_after}
    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    pid = diagnostic_pid(log_text)
    codec_rows = video_codec_rows(log_text, pid, args.decoder)
    result["videoCodec"] = {"pid": pid, "decoder": args.decoder}
    for phase in phases:
        phase["statistics"] = phase_statistics(samples, phase["startMs"], phase["endMs"])
        rows = [r for r in codec_rows if phase["startMs"] + 2000 <= r[0] * 1000 <= phase["endMs"] - 1000]
        phase["codec-samples"] = len(rows)
        phase["codec-mean"] = dict(zip(
            ("queued", "done", "rendered", "discarded"),
            [statistics.mean(r[i] for r in rows) for i in range(1, 5)],
        )) if rows else None
    result["events"] = [x for x in data if x["event"] != "sample"]
    # 输入命令成功不等于手势被播放器接收，缺少确认的轮次不能纳入结论。
    errors = []
    if pid is None or not codec_rows:
        errors.append("缺少唯一应用进程的视频Codec数据")
    for name in ("gesture_start", "gesture_end"):
        if not any(x["event"] == name for x in data):
            errors.append(f"缺少{name}事件")
    hold = next(x for x in phases if x["name"] == "hold")
    rates = hold["statistics"].get("configured-speeds", [])
    if not rates or any(abs(rate - args.expected_rate) > .01 for rate in rates):
        errors.append(f"长按速度{rates}与预期{args.expected_rate}不一致")
    result["validationErrors"] = errors
    result["valid"] = not errors
    (directory / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--package", default="com.maxzrb.piliexo")
    parser.add_argument("--bvid", default="BV1a2pr6aEC1")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--attach", action="store_true", help="接入当前播放页，不冷启动；每轮需从界面恢复播放")
    parser.add_argument("--expected-rate", type=float, default=3.0)
    parser.add_argument("--decoder", default="c2.qti.hevc.decoder", help="精确视频组件名，不包含AAC统计")
    parser.add_argument("--start-seconds", type=int, default=60)
    parser.add_argument("--normal-seconds", type=float, default=8)
    parser.add_argument("--hold-seconds", type=float, default=10)
    parser.add_argument("--recovery-seconds", type=float, default=20)
    parser.add_argument("--x", type=int, default=800)
    parser.add_argument("--y", type=int, default=400)
    args = parser.parse_args()
    if args.attach and args.rounds != 1:
        parser.error("--attach只支持单轮；每轮需要先在界面确认素材、起点和播放状态")
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    try:
        for index in range(1, args.rounds + 1):
            results.append(run_round(args, index))
            if not results[-1]["valid"]:
                raise SystemExit("本轮未通过手势/倍速确认，已保存原始数据并停止后续轮次")
    finally:
        stop_app(args.package)
        (args.output / "summary.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
