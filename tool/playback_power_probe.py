"""接入显式功耗研究包，保存分阶段线程CPU、Codec和播放正确性证据。"""

import argparse
import json
import os
import pathlib
import re
import statistics
import subprocess
import time

from ui_power_probe import foreground_errors



def parse_gpu_busy(text):
    """只接受有效的busy/total原始计数，不把权限错误或零区间当成零负载。"""
    values = text.split()
    if len(values) != 2 or any(not value.isdecimal() for value in values):
        return None
    busy, total = map(int, values)
    return {"busy": busy, "total": total} if total > 0 and 0 <= busy <= total else None


def gpu_busy_summary(points):
    # 排除首个可能跨界的读数；厂商通常给出滚动窗口，结果仅是整机GPU采样比例。
    values = [point["gpuBusy"] for point in points[1:] if point.get("gpuBusy") is not None]
    return {"samples": len(values), "sampledSystemBusyPercent":
            sum(value["busy"] for value in values) / sum(value["total"] for value in values) * 100
            if values else None,
            "frequencyHzSamples": [point["gpuFrequencyHz"] for point in points[1:] if point.get("gpuFrequencyHz")]}


def video_codec_samples(text, pid, decoder="c2.qti.hevc.decoder"):
    """只统计指定进程的视频解码器，避免混入同进程音频计数。"""
    pattern = re.compile(
        r"^\s*(\d+\.\d+)\s+(\d+)\s+\d+.*TraceLog.*\("
        + re.escape(decoder)
        + r":[^)]*\) Queued: ([\d.]+)/s Done: ([\d.]+)/s "
          r"Rendered: ([\d.]+)/s Discarded: ([\d.]+)/s")
    return [match for line in text.splitlines()
            if (match := pattern.search(line)) and int(match[2]) == pid]


def decoder_operating_rate_changes(text, pid, decoder="c2.qti.hevc.decoder"):
    """按进程、CCodec线程与组件归属读取真实解码配置，避免只相信Dart选项。"""
    pattern = re.compile(r"^\s*(\d+\.\d+)\s+(\d+)\s+(\d+)\s+\w\s+(CCodec(?:Config)?)\s*:\s*(.*)$")
    components = {}
    rows = []
    for line in text.splitlines():
        match = pattern.search(line)
        if not match or int(match[2]) != pid:
            continue
        tid = int(match[3])
        body = match[5]
        component = re.search(r"(?:allocate\(|Created component \[)([^)\]]+)", body)
        if component:
            components[tid] = component[1]
        rate = re.search(r"c2::float algo\.rate\.value = ([\d.eE+-]+)", body)
        if rate and components.get(tid) == decoder:
            rows.append({"epochMs": float(match[1]) * 1000, "tid": tid,
                         "decoder": decoder, "rate": float(rate[1])})
    return rows


def ambient_validation_errors(start, end, readings):
    errors = []
    gpu_texture = start.get("ambientImplementation") == "gpu-texture"
    if gpu_texture and (end["ambientCaptures"] != 0 or not readings or
                        any(type(event.get("ambientTextureId")) is not int or
                            event["ambientTextureId"] < 0 for event in readings)):
        errors.append("纹理复用未持续生效或仍在截图")
    if start["ambient"] and not gpu_texture and end["ambientCaptures"] < 100:
        errors.append("环境帧开启组未实际采样")
    if not start["ambient"] and end["ambientCaptures"] != 0:
        errors.append("环境帧关闭组仍在采样")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL"))
    parser.add_argument("--output", required=True)
    parser.add_argument("--expected-phases", type=int, default=8)
    parser.add_argument("--aligned-window", action="store_true")
    parser.add_argument("--video-decoder", default="c2.qti.hevc.decoder")
    parser.add_argument("--screenshots", action="store_true")
    parser.add_argument("--display-context", action="store_true", help="记录每窗亮屏、前台和显示模式，排除状态改变")
    parser.add_argument("--codec-config", action="store_true", help="硬解预留研究需采集原生CCodec配置")
    parser.add_argument("--gpu-busy", action="store_true", help="可选KGSL整机GPU忙碌计数，不是功率")
    args = parser.parse_args()
    if not args.serial:
        parser.error("必须显式指定设备序列号")
    root = pathlib.Path(args.output)
    root.mkdir(parents=True, exist_ok=False)
    adb_command = ["adb", "-s", args.serial]

    def adb(*values, allow_partial=False):
        result = subprocess.run(adb_command + list(values), capture_output=True,
                                encoding="utf-8", errors="replace", timeout=20)
        if result.returncode and not allow_partial:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        return result.stdout

    def display_context():
        return {"display": adb("shell", "dumpsys", "display"),
                "power": adb("shell", "dumpsys", "power"),
                "policy": adb("shell", "dumpsys", "window", "policy"),
                "activity": "\n".join(line for line in adb("shell", "dumpsys", "activity", "activities").splitlines() if "ResumedActivity:" in line)}

    def context():
        values = {"battery": adb("shell", "dumpsys", "battery"),
                  "thermal": adb("shell", "dumpsys", "thermalservice")}
        if args.display_context:
            values.update(display_context())
        return values

    def parse_stat(line):
        match = re.match(r"^(\d+) \((.*)\) (.*)$", line)
        if not match:
            return None
        fields = match[3].split()
        return {"tid": int(match[1]), "name": match[2],
                "ticks": int(fields[11]) + int(fields[12])}

    def events():
        values = []
        for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if "PILI_POWER " in line:
                try:
                    values.append(json.loads(line.split("PILI_POWER ", 1)[1]))
                except ValueError:
                    pass
        return values

    log_path = root / "logcat.txt"
    samples = []
    ticks = int(adb("shell", "getconf", "CLK_TCK"))
    offset_ms = float(adb("shell", "date", "+%s.%N")) * 1000 - time.time() * 1000
    before = context()
    status = "timeout"
    pid = None
    captured_labels = set()
    display_contexts = {}
    with log_path.open("w", encoding="utf-8") as log_file, \
            (root / "resources.jsonl").open("w", encoding="utf-8") as resource_file:
        filters = ["TraceLog:W", "flutter:I", "*:S"]
        if args.codec_config:
            filters += ["CCodec:D", "CCodecConfig:D"]
        process = subprocess.Popen(adb_command + ["logcat", "-v", "epoch", "-T", "1"] + filters,
                                   stdout=log_file, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 420
            while time.monotonic() < deadline:
                stream = events()
                if args.display_context:
                    for event in stream:
                        if event["event"] == "phase_start" and event["label"] not in display_contexts:
                            label = event["label"]
                            if not re.fullmatch(r"[a-zA-Z0-9-]+", label):
                                raise ValueError("显示状态标签不安全")
                            state = display_context()
                            display_contexts[label] = state
                            (root / f"{label}-display.json").write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
                if args.screenshots:
                    for event in stream:
                        if event["event"] == "phase_end" and event["label"] not in captured_labels:
                            label = event["label"]
                            if not re.fullmatch(r"[a-zA-Z0-9-]+", label):
                                raise ValueError("截图标签不安全")
                            (root / f"{label}.png").write_bytes(subprocess.check_output(
                                adb_command + ["exec-out", "screencap", "-p"], timeout=20))
                            captured_labels.add(label)
                endings = [event for event in stream if event["event"] in ("complete", "aborted")]
                if endings:
                    status = endings[-1]["event"]
                    break
                try:
                    value = adb("shell", "pidof", "com.maxzrb.piliexo").strip()
                except RuntimeError:
                    value = ""
                if value:
                    pid = int(value.split()[0])
                    begin_ms = time.time() * 1000
                    aggregate = parse_stat(adb("shell", "cat", f"/proc/{pid}/stat").strip())
                    threads = adb("shell", "cat", f"/proc/{pid}/task/*/stat", allow_partial=True)
                    sample = {"epochMs": (begin_ms + time.time() * 1000) / 2 + offset_ms,
                              "pid": pid, "aggregate": aggregate,
                              "threads": [row for line in threads.splitlines()
                                          if (row := parse_stat(line))]}
                    if args.gpu_busy:
                        gpu = adb("shell", "cat", "/sys/class/kgsl/kgsl-3d0/gpubusy", "/sys/class/kgsl/kgsl-3d0/gpuclk", allow_partial=True).splitlines()
                        sample["gpuBusy"] = parse_gpu_busy(gpu[0]) if gpu else None
                        sample["gpuFrequencyHz"] = int(gpu[1]) if len(gpu) > 1 and gpu[1].strip().isdecimal() else None
                    samples.append(sample)
                    resource_file.write(json.dumps(sample, ensure_ascii=False) + "\n")
                    resource_file.flush()
                time.sleep(2)
        except Exception as error:
            status = f"collector_error: {error}"
        finally:
            process.terminate()
            process.wait(timeout=5)

    stream = events()
    phases = []
    codec = video_codec_samples(log_path.read_text(encoding="utf-8"), pid,
                                args.video_decoder)
    native_rates = decoder_operating_rate_changes(log_path.read_text(encoding="utf-8"), pid, args.video_decoder)
    for start in [event for event in stream if event["event"] == "phase_start"]:
        label = start["label"]
        end = next((event for event in stream if event["event"] == "phase_end"
                    and event["label"] == label), None)
        if not end:
            continue
        points = [sample for sample in samples if sample["pid"] == pid and
                  start["epochMs"] <= sample["epochMs"] <= end["epochMs"]]
        readings = [event for event in stream if event["event"] == "sample"
                    and event["label"] == label]
        phase = {"start": start, "end": end, "samples": readings,
                 "resourceSamples": len(points)}
        if args.gpu_busy:
            phase["gpuBusy"] = gpu_busy_summary(points)
        if len(points) >= 2:
            a, b = points[0], points[-1]
            elapsed = (b["epochMs"] - a["epochMs"]) / 1000
            phase["cpuCorePercent"] = (b["aggregate"]["ticks"] - a["aggregate"]["ticks"]) / ticks / elapsed * 100
            first = {row["tid"]: row for row in a["threads"]}
            thread_cpu = []
            for row in b["threads"]:
                old = first.get(row["tid"])
                if old:
                    thread_cpu.append({"name": row["name"], "tid": row["tid"],
                                       "cpuCorePercent": (row["ticks"] - old["ticks"]) / ticks / elapsed * 100})
            phase["threads"] = sorted(thread_cpu, key=lambda row: -row["cpuCorePercent"])
        rows = [match for match in codec if start["epochMs"] + 1500 <= float(match[1]) * 1000 <= end["epochMs"] - 500]
        phase["codecSamples"] = len(rows)
        phase["codecMean"] = dict(zip(["queued", "done", "rendered", "discarded"],
                                      [statistics.mean(float(row[index]) for row in rows)
                                       for index in range(3, 7)])) if rows else None
        errors = []
        if args.display_context:
            if label not in display_contexts:
                errors.append("缺少窗口显示/前台状态")
            else:
                errors.extend(foreground_errors(display_contexts[label]))
        if start.get("operatingRateTarget") is not None:
            target = start["operatingRateTarget"]
            reset = next((event for event in stream if event["event"] == "decoder_reset_start" and event["label"] == label), None)
            rates = [row for row in native_rates if reset and reset["epochMs"] <= row["epochMs"] <= start["epochMs"]]
            phase["nativeOperatingRateChanges"] = rates
            if not rates or rates[-1]["rate"] != target:
                errors.append("没有原生视频解码器配置证明目标预留速率生效")
            if start.get("decoderOptions") != f"operating_rate={target}" or start.get("hwdec") != "mediacodec":
                errors.append("Dart解码选项或硬解状态不符合预期")
        if args.aligned_window and not 68000 <= start["positionMs"] <= 68500:
            errors.append("窗口未对齐68秒")
        if any((event["width"], event["height"]) != (1920, 1080) for event in readings):
            errors.append("画面并非1920×1080")
        if len(points) < 5:
            errors.append("线程资源样本不足")
        if len(readings) != 20 or any(event["buffering"] or event["speed"] != 1 for event in readings):
            errors.append("播放样本不足、缓冲或速度并非1倍")
        if readings:
            speed = (readings[-1]["positionMs"] - readings[0]["positionMs"]) / (readings[-1]["epochMs"] - readings[0]["epochMs"])
            phase["positionRate"] = speed
            if not .97 <= speed <= 1.03:
                errors.append("实际推进速度异常")
        if not rows or not 58 <= phase["codecMean"]["rendered"] <= 62:
            errors.append("60帧素材送显不稳定")
        errors.extend(ambient_validation_errors(start, end, readings))
        avsync = sorted(abs(event['avsync']) for event in readings if isinstance(event.get('avsync'), (int, float)))
        phase['avsyncP95Seconds'] = avsync[max(0, int(len(avsync) * .95) - 1)] if avsync else None
        for counter in ['frame-drop-count', 'decoder-frame-drop-count']:
            measured = [event[counter] for event in readings if isinstance(event.get(counter), (int, float))]
            phase[counter + '-delta'] = measured[-1] - measured[0] if measured else None
        phase['queryP95Us'] = sorted(event['queryUs'] for event in readings)[18] if len(readings) == 20 else None
        phase["validationErrors"] = errors
        phase["valid"] = not errors
        phases.append(phase)
    after = context()
    state_errors = foreground_errors(after) if args.display_context else []
    result = {"validationErrors": state_errors, "status": status, "pid": pid, "ticksPerSecond": ticks,
              "videoDecoder": args.video_decoder,
              "contextBefore": before, "contextAfter": after,
              "events": stream, "phases": phases,
              "valid": not state_errors and status == "complete" and len(phases) == args.expected_phases and all(phase["valid"] for phase in phases)}
    (root / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    for phase in phases:
        print(phase["start"]["label"], "valid=", phase["valid"], "CPU=", phase.get("cpuCorePercent"),
              "Codec=", phase["codecMean"], "errors=", phase["validationErrors"], flush=True)
    print("实验有效：", result["valid"], flush=True)


if __name__ == "__main__":
    main()
