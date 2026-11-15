"""采集视频合成与调度证据；默认只读，可显式指定一次长按，不负责解锁或导航。"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import threading
import time


def trace_config(seconds, wakers=False):
    events = ["sched/sched_switch", "sched/sched_waking", "sched/sched_process_exit",
              "sched/sched_process_free", "task/task_newtask", "task/task_rename",
              "power/cpu_frequency", "power/cpu_idle", "binder/binder_transaction",
              "binder/binder_transaction_received"]
    ftrace = "\n".join(f'ftrace_events: "{event}"' for event in events)
    categories = "\n".join(f'atrace_categories: "{name}"' for name in ["gfx", "video", "input"])
    return f'''buffers {{ size_kb: {262144 if wakers else 131072} fill_policy: RING_BUFFER }}
duration_ms: {int(seconds * 1000)}
flush_period_ms: 1000
data_sources {{ config {{ name: "linux.ftrace" ftrace_config {{
{ftrace}
{categories}
atrace_apps: "com.maxzrb.piliexo"
compact_sched {{ enabled: {str(not wakers).lower()} }}
}} }} }}
data_sources {{ config {{ name: "linux.process_stats" process_stats_config {{
scan_all_processes_on_start: true proc_stats_poll_ms: 1000
}} }} }}
data_sources {{ config {{ name: "linux.sys_stats" sys_stats_config {{
stat_period_ms: 1000 cpufreq_period_ms: 500
}} }} }}
data_sources {{ config {{ name: "android.surfaceflinger.frametimeline" }} }}
data_sources {{ config {{ name: "android.gpu.memory" }} }}
data_sources {{ config {{ name: "android.log" android_log_config {{ filter_tags: "PILI_TRACE" }} }} }}
'''


def capture(args):
    root = Path(args.output)
    root.mkdir(parents=True, exist_ok=False)
    adb = [args.adb, "-s", args.serial]

    def run(*values):
        return subprocess.run(adb + list(values), capture_output=True, check=True).stdout

    def snapshot(prefix):
        for name, command in {
            "sf": ["dumpsys", "SurfaceFlinger"], "display": ["dumpsys", "display"],
            "power": ["dumpsys", "power"], "window": ["dumpsys", "window", "policy"],
            "activity": ["dumpsys", "activity", "activities"],
            "thermal": ["dumpsys", "thermalservice"], "battery": ["dumpsys", "battery"],
            "processes": ["ps", "-A", "-T"],
        }.items():
            (root / f"{prefix}-{name}.txt").write_bytes(run("shell", *command))
        (root / f"{prefix}.png").write_bytes(run("exec-out", "screencap", "-p"))

    snapshot("before")
    config = trace_config(args.seconds, args.wakers).encode("utf-8")
    (root / "config.pbtxt").write_bytes(config)
    remote = "/data/misc/perfetto-traces/piliexo-composition.pftrace"
    # 保持前台命令直到追踪结束，避免后台尚未落盘便拉到空文件。
    logcat = (root / "logcat.txt").open("wb")
    logger = subprocess.Popen(adb + ["logcat", "-v", "epoch", "-T", "1",
                                    "TraceLog:W", "CCodec:D", "CCodecConfig:D", "flutter:I", "PILI_TRACE:I", "*:S"],
                              stdout=logcat, stderr=subprocess.DEVNULL)
    stopped = threading.Event()

    def sample_gpu():
        with (root / "gpu.jsonl").open("w", encoding="utf-8") as stream:
            while not stopped.is_set():
                result = subprocess.run(adb + ["shell", "cat", "/sys/class/kgsl/kgsl-3d0/gpubusy"],
                                        capture_output=True, timeout=5)
                stream.write(json.dumps({"epoch": time.time(), "raw": result.stdout.decode("utf-8", errors="replace").strip(),
                                         "error": result.stderr.decode("utf-8", errors="replace").strip()}) + "\n")
                stream.flush()
                stopped.wait(1)

    sampler = threading.Thread(target=sample_gpu) if args.gpu_busy else None
    if sampler:
        sampler.start()
    gesture_errors = []

    def hold():
        if stopped.wait(6):
            return
        try:
            x, y = map(str, args.hold)
            run("shell", "log", "-p", "i", "-t", "PILI_TRACE", "hold_start")
            run("shell", "input", "swipe", x, y, x, y, "4000")
            run("shell", "log", "-p", "i", "-t", "PILI_TRACE", "hold_release")
        except Exception as error:
            gesture_errors.append(str(error))

    gesture = threading.Thread(target=hold) if args.hold else None
    if gesture:
        gesture.start()
    try:
        result = subprocess.run(adb + ["shell", "perfetto", "--txt", "-c", "-", "-o", remote],
                                input=config, capture_output=True, timeout=args.seconds + 45)
        (root / "perfetto.txt").write_bytes(result.stdout + result.stderr)
        result.check_returncode()
    finally:
        stopped.set()
        if sampler:
            sampler.join(timeout=6)
        if gesture:
            gesture.join(timeout=6)
        logger.terminate()
        logger.wait(timeout=10)
        logcat.close()
    run("pull", remote, str(root / "trace.pftrace"))
    if (root / "trace.pftrace").stat().st_size == 0:
        raise RuntimeError("追踪为空，不能作为有效样本")
    snapshot("after")
    (root / "capture.json").write_text(json.dumps({"serial": args.serial,
        "seconds": args.seconds, "label": args.label, "epoch": time.time(),
        "hold": args.hold, "gestureErrors": gesture_errors}, indent=2), encoding="utf-8")


def analyze(args):
    from perfetto.trace_processor import TraceProcessor, TraceProcessorConfig

    root = Path(args.output)
    config = TraceProcessorConfig(bin_path=args.trace_processor)
    with TraceProcessor(trace=args.trace, config=config) as tp:
        def query(sql):
            return [vars(row) for row in tp.query(sql)]

        bounds = query("select start_ts, end_ts from trace_bounds")[0]
        # 舍弃首尾各一秒，CPU区间按边界裁剪，避免完整slice跨窗带来偏差。
        start = bounds["start_ts"] + int(args.start_seconds * 1e9)
        end = (bounds["start_ts"] + int(args.end_seconds * 1e9)
               if args.end_seconds is not None else bounds["end_ts"] - 1_000_000_000)
        end = min(end, bounds["end_ts"])
        if end <= start:
            raise ValueError("追踪时间过短或为空")
        tp.query(f"create perfetto table window as select {start} lo, {end} hi, {end-start} span")
        tp.query("""create perfetto table cpu_window as
            select s.*, min(s.ts+s.dur,w.hi)-max(s.ts,w.lo) clipped_dur
            from sched s, window w where s.dur>0 and s.ts<w.hi and s.ts+s.dur>w.lo""")
        result = {"bounds": bounds, "windowSeconds": (end - start) / 1e9}
        queries = {
            "errors": "select name,value from stats where severity='error' and value>0",
            "dataLoss": "select name,idx,value from stats where severity='data_loss' and value>0",
            "metadata": "select name,str_value,int_value from metadata where name glob '*error*' or name glob '*trac*'",
            "bufferStats": "select name,idx,value from stats where name glob '*buffer*' and value>0",
            "markers": "select ts,tag,msg from android_logs where tag='PILI_TRACE' order by ts",
            "clockSnapshots": "select ts,clock_name,clock_value from clock_snapshot where clock_name='REALTIME'",
            "processCpu": """select p.pid,p.name,sum(s.clipped_dur)*100.0/w.span cpuPercent,
                count(*) switches from cpu_window s join thread t using(utid) join process p using(upid), window w
                where p.pid!=0 group by p.upid order by cpuPercent desc limit 30""",
            "threadCpu": """select p.pid,p.name process,t.tid,t.name thread,
                sum(s.clipped_dur)*100.0/w.span cpuPercent,count(*) switches,
                sum(case when s.cpu>=4 then s.clipped_dur else 0 end)*100.0/sum(s.clipped_dur) bigCorePercent,
                min(s.priority) minPriority,max(s.priority) maxPriority
                from cpu_window s join thread t using(utid) join process p using(upid), window w
                where p.name glob '*piliexo*' or p.name glob '*surfaceflinger*' or p.name glob '*composer-service*' or p.name glob '*codec*'
                group by utid order by cpuPercent desc limit 100""",
            "threadStates": """select p.pid,t.tid,t.name,st.state,count(*) n,
                sum(min(st.ts+st.dur,w.hi)-max(st.ts,w.lo))/1e6 totalMs,
                percentile(min(st.ts+st.dur,w.hi)-max(st.ts,w.lo),95)/1e6 p95Ms,
                max(min(st.ts+st.dur,w.hi)-max(st.ts,w.lo))/1e6 maxMs
                from thread_state st join thread t using(utid) join process p using(upid), window w
                where st.dur>0 and st.ts<w.hi and st.ts+st.dur>w.lo
                and (p.name glob '*piliexo*' or p.name glob '*surfaceflinger*' or p.name glob '*composer-service*')
                group by utid,st.state order by totalMs desc""",
            "codecWakers": """select t.tid,t.name thread,wt.tid wakerTid,wt.name waker,wp.name wakerProcess,count(*) n
                from thread_state st join thread t using(utid) join process p using(upid)
                left join thread wt on st.waker_utid=wt.utid left join process wp on wt.upid=wp.upid, window w
                where st.ts>=w.lo and st.ts<w.hi and st.state='R' and p.name glob '*piliexo*'
                and (t.name glob '*MediaCodec*' or t.name glob '*HwBinder*')
                group by t.utid,st.waker_utid order by n desc limit 40""",
            "appAndSfSlices": """select p.pid,t.name thread,s.name,count(*) n,
                sum(s.dur)/1e6 totalMs,percentile(s.dur,95)/1e6 p95Ms,max(s.dur)/1e6 maxMs
                from slice s join thread_track tr on s.track_id=tr.id join thread t using(utid)
                join process p using(upid),window w where s.dur>0 and s.ts>=w.lo and s.ts+s.dur<=w.hi
                and (p.name glob '*piliexo*' or p.name glob '*surfaceflinger*' or p.name glob '*composer-service*')
                group by t.utid,s.name order by totalMs desc limit 150""",
            "frameTimeline": """select p.pid,f.layer_name,f.present_type,f.jank_type,f.gpu_composition,count(*) n,
                percentile(f.dur,95)/1e6 p95DurationMs from actual_frame_timeline_slice f
                left join process p using(upid),window w where f.ts>=w.lo and f.ts<w.hi and f.dur>0
                group by f.upid,f.layer_name,f.present_type,f.jank_type,f.gpu_composition order by n desc""",
            "frequency": """select tr.name,tr.cpu,count(*) samples,min(c.value) minKhz,max(c.value) maxKhz
                from counter c join cpu_counter_track tr on c.track_id=tr.id,window w
                where c.ts>=w.lo and c.ts<w.hi and tr.name glob '*freq*' group by tr.id""",
        }
        for name, sql in queries.items():
            result[name] = query(sql)
        log_path = Path(args.trace).parent / "logcat.txt"
        if log_path.exists() and result["clockSnapshots"]:
            # 个别厂商没有输出android.log数据源，用同窗REALTIME快照对齐独立logcat标记。
            result["logcatMarkers"] = []
            for line in log_path.read_text(encoding="utf-8").splitlines():
                match = re.search(r"^\s*(\d+\.\d+).*PILI_TRACE:\s*(.*)$", line)
                if match:
                    epoch = round(float(match[1]) * 1e9)
                    clock = min(result["clockSnapshots"], key=lambda row: abs(row["clock_value"] - epoch))
                    result["logcatMarkers"].append({"ts": epoch - clock["clock_value"] + clock["ts"], "msg": match[2]})
        # FrameTimeline不覆盖所有视频SurfaceView；没有条目不能推论视频没有丢帧。
        result["caveats"] = ["CPU为单核100%口径；调度追踪有额外负载。",
            "slice耗时包含等待，不能把嵌套slice相加当CPU。",
            "HWC DEVICE仅说明最终图层合成，不能证明应用内部视频绕过GPU。",
            "FrameTimeline不保证覆盖视频SurfaceView；这些数据不等同瓦数或源视频送显帧率。"]
        result["caveats"].append("紧凑调度不保留完整唤醒者；研究调用来源必须用--wakers重新采集。")
    root.mkdir(parents=True, exist_ok=True)
    (root / "analysis.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: result[key] for key in ["windowSeconds", "errors", "dataLoss"]}, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["capture", "analyze"])
    parser.add_argument("--output", required=True)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial")
    parser.add_argument("--seconds", type=int, default=22)
    parser.add_argument("--label", default="manual-state")
    parser.add_argument("--trace")
    parser.add_argument("--trace-processor")
    parser.add_argument("--gpu-busy", action="store_true", help="可选KGSL滚动窗口采样，不能换算瓦数")
    parser.add_argument("--wakers", action="store_true", help="关闭紧凑调度以保留唤醒者；增大追踪缓冲")
    parser.add_argument("--hold", nargs=2, type=int, metavar=("X", "Y"), help="可选：第6秒在指定坐标长按4秒")
    parser.add_argument("--start-seconds", type=float, default=1, help="分析窗口相对追踪起点的秒数")
    parser.add_argument("--end-seconds", type=float)
    args = parser.parse_args()
    if args.mode == "capture":
        if not args.serial or not 5 <= args.seconds <= 50:
            parser.error("capture需要指定serial，seconds范围5到50")
        capture(args)
    else:
        if not args.trace:
            parser.error("analyze需要指定trace")
        if args.start_seconds < 0 or (args.end_seconds is not None and args.end_seconds <= args.start_seconds):
            parser.error("分析窗口必须从非负时间开始，且结束时间大于开始时间")
        analyze(args)


if __name__ == "__main__":
    main()
