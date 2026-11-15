"""功耗归因日志的音视频计数隔离回归。"""

import unittest

from playback_power_probe import ambient_validation_errors, video_codec_samples, parse_gpu_busy, gpu_busy_summary, decoder_operating_rate_changes


class VideoCodecSamplesTest(unittest.TestCase):
    def test_excludes_audio_and_other_process(self):
        lines = "\n".join([
            "100.000 12 20 W TraceLog: (c2.android.aac.decoder:0x1) Queued: 43/s Done: 43/s Rendered: 0/s Discarded: 43/s",
            "100.001 12 21 W TraceLog: (c2.qti.hevc.decoder:0x2) Queued: 60/s Done: 61/s Rendered: 60/s Discarded: 0/s",
            "100.002 13 21 W TraceLog: (c2.qti.hevc.decoder:0x3) Queued: 30/s Done: 30/s Rendered: 30/s Discarded: 0/s",
        ])
        rows = video_codec_samples(lines, 12)
        self.assertEqual(len(rows), 1)
        self.assertEqual(float(rows[0][5]), 60)
        self.assertEqual(float(rows[0][6]), 0)

    def test_decoder_name_is_exact_and_escaped(self):
        lines = "\n".join([
            "100.0 12 20 W TraceLog: (c2.qti.avc.decoder:0x1) Queued: 60/s Done: 60/s Rendered: 60/s Discarded: 0/s",
            "100.1 12 21 W TraceLog: (c2XqtiXavcXdecoder:0x2) Queued: 30/s Done: 30/s Rendered: 30/s Discarded: 0/s",
        ])
        self.assertEqual(len(video_codec_samples(lines, 12, "c2.qti.avc.decoder")), 1)
        self.assertEqual(video_codec_samples(lines, 12), [])

    def test_multiple_video_instances_are_counted_without_audio(self):
        lines = "\n".join(
            f"100.{index} 12 21 W TraceLog: (c2.qti.hevc.decoder:0x{index}) Queued: 60.1/s Done: 60.2/s Rendered: 60.0/s Discarded: 0.0/s"
            for index in range(2))
        self.assertEqual(len(video_codec_samples(lines, 12)), 2)


class AmbientValidationTest(unittest.TestCase):
    def test_gpu_requires_continuous_texture_and_zero_snapshots(self):
        start = {"ambient": True, "ambientImplementation": "gpu-texture"}
        readings = [{"ambientTextureId": 17}] * 20
        self.assertEqual(ambient_validation_errors(start, {"ambientCaptures": 0}, readings), [])
        self.assertTrue(ambient_validation_errors(start, {"ambientCaptures": 1}, readings))

    def test_missing_or_invalid_texture_cannot_masquerade_as_saved_work(self):
        start = {"ambient": True, "ambientImplementation": "gpu-texture"}
        for readings in ([], [{"ambientTextureId": None}], [{"ambientTextureId": -1}], [{"ambientTextureId": True}]):
            self.assertTrue(ambient_validation_errors(start, {"ambientCaptures": 0}, readings))

    def test_raw_and_legacy_must_actually_capture(self):
        for mode in ("rgba", "snapshot"):
            start = {"ambient": True, "ambientImplementation": mode}
            self.assertTrue(ambient_validation_errors(start, {"ambientCaptures": 0}, []))
            self.assertEqual(ambient_validation_errors(start, {"ambientCaptures": 200}, []), [])

    def test_disabled_group_cannot_keep_capturing(self):
        self.assertTrue(ambient_validation_errors({"ambient": False}, {"ambientCaptures": 1}, []))


class GpuBusyTest(unittest.TestCase):
    def test_invalid_or_unavailable_is_unknown(self):
        for value in ["", "Permission denied", "1 0", "21 20", "-1 20", "1 20 30"]:
            self.assertIsNone(parse_gpu_busy(value))
        self.assertEqual(parse_gpu_busy("0 20"), {"busy": 0, "total": 20})

    def test_weighted_ratio_excludes_first_cross_boundary_interval(self):
        values = [{"gpuBusy": {"busy": 100, "total": 100}},
                  {"gpuBusy": {"busy": 1, "total": 10}},
                  {"gpuBusy": {"busy": 9, "total": 90}}]
        self.assertEqual(gpu_busy_summary(values), {"samples": 2, "sampledSystemBusyPercent": 10, "frequencyHzSamples": []})
        self.assertIsNone(gpu_busy_summary([{}, {"gpuBusy": None}])["sampledSystemBusyPercent"])


class NativeOperatingRateTest(unittest.TestCase):
    def test_binds_video_component_to_process_and_thread(self):
        text = "\n".join([
            "100.00 12 20 D CCodec : allocate(c2.qti.hevc.decoder)",
            "100.01 12 20 I CCodecConfig: c2::float algo.rate.value = 30",
            "100.02 12 21 D CCodec : allocate(c2.android.aac.decoder)",
            "100.03 12 21 I CCodecConfig: c2::float algo.rate.value = 48000",
            "100.04 13 20 I CCodecConfig: c2::float algo.rate.value = 999",
            "100.05 12 20 I CCodecConfig: c2::float algo.rate.value = 180",
        ])
        self.assertEqual([x["rate"] for x in decoder_operating_rate_changes(text, 12)], [30, 180])

    def test_unknown_or_reused_thread_cannot_supply_video_rate(self):
        text = "\n".join([
            "100.0 12 20 I CCodecConfig: c2::float algo.rate.value = 180",
            "101.0 12 20 I CCodec : Created component [c2.qti.hevc.decoder]",
            "101.1 12 20 I CCodecConfig: c2::float algo.rate.value = 60",
            "102.0 12 20 I CCodec : Created component [c2.android.aac.decoder]",
            "102.1 12 20 I CCodecConfig: c2::float algo.rate.value = 48000",
        ])
        self.assertEqual([x["rate"] for x in decoder_operating_rate_changes(text, 12)], [60])


if __name__ == "__main__":
    unittest.main()
