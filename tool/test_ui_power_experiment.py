"""验证同位置界面归因的 CPU 计算和窗口有效性。"""

import unittest

from ui_power_experiment import summarize


class UiPowerExperimentTest(unittest.TestCase):
    def fixture(self):
        start = {"event": "phase_start", "label": "scroll-1-A", "epochMs": 0,
                 "offset": 100, "moving": True}
        end = {"event": "phase_end", "label": "scroll-1-A", "epochMs": 20000,
               "offset": 100, "cycles": 10, "durationMs": 20000}
        samples = [{"epochMs": second * 1000, "pid": 12,
                    "aggregate": {"ticks": second * 50},
                    "threads": [{"tid": 12, "name": "main", "ticks": second * 50}]}
                   for second in range(21)]
        return [start, end], samples

    def test_single_core_percent_and_boundary_exclusion(self):
        events, samples = self.fixture()
        phase = summarize(events, samples, 12, 100)[0]
        self.assertTrue(phase["valid"])
        self.assertEqual(phase["cpuCorePercent"], 50)
        self.assertEqual(phase["resourceSamples"], 19)
        self.assertEqual(phase["threads"][0]["cpuCorePercent"], 50)

    def test_rejects_position_drift_and_incomplete_cycles(self):
        events, samples = self.fixture()
        events[1].update(offset=300, cycles=9)
        phase = summarize(events, samples, 12, 100)[0]
        self.assertFalse(phase["valid"])
        self.assertEqual(len(phase["validationErrors"]), 2)

    def test_does_not_mix_other_process_or_incomplete_phase(self):
        events, samples = self.fixture()
        self.assertEqual(summarize(events[:1], samples, 12, 100), [])
        self.assertFalse(summarize(events, samples, 13, 100)[0]["valid"])


if __name__ == "__main__":
    unittest.main()
