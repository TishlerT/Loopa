"""Runner contract tests. Uses stub tools only; never launches Xcode or a simulator.

Run with: python3 ios/Tests/TestRunnerTests.py
"""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[2]
PASSING_SUMMARY = {
    "result": "Passed",
    "totalTestCount": 2,
    "passedTests": 2,
    "failedTests": 0,
    "skippedTests": 0,
    "expectedFailures": 0,
    "testFailures": [],
    # These repeated field names caused the old grep-based parser to misread counts.
    "devicesAndConfigurations": [{"passedTests": 2, "failedTests": 0, "skippedTests": 0,
                                  "expectedFailures": 0}],
}


class TestRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="loopa runner tests ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project with spaces"
        self.project.mkdir()
        self.runner = self.project / "run_tests.sh"
        shutil.copy2(REPO / "ios/run_tests.sh", self.runner)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.output = self.root / "saved evidence"
        self.calls = self.root / "calls.jsonl"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        STUB_CALLS=str(self.calls), STUB_SUMMARY=json.dumps(PASSING_SUMMARY))
        self.write_tool("xcodebuild", """
import json, os, pathlib, sys, time
args = sys.argv[1:]
with open(os.environ['STUB_CALLS'], 'a') as stream:
    stream.write(json.dumps({'tool': 'xcodebuild', 'args': args}) + '\\n')
bundle = pathlib.Path(args[args.index('-resultBundlePath') + 1])
if not os.environ.get('STUB_NO_BUNDLE'):
    bundle.mkdir()
    (bundle / 'evidence.txt').write_text('retained result evidence')
print('stub build output', flush=True)
if os.environ.get('STUB_WAIT'):
    pathlib.Path(os.environ['STUB_WAIT']).write_text('ready')
    time.sleep(60)
sys.exit(int(os.environ.get('STUB_BUILD_EXIT', '0')))
""")
        self.write_tool("xcrun", """
import json, os, pathlib, sys
args = sys.argv[1:]
assert args[:5] == ['xcresulttool', 'get', 'test-results', 'summary', '--path'], args
assert pathlib.Path(args[5]).is_dir()
with open(os.environ['STUB_CALLS'], 'a') as stream:
    stream.write(json.dumps({'tool': 'xcrun', 'args': args}) + '\\n')
print(os.environ['STUB_SUMMARY'])
print('stub parser diagnostic', file=sys.stderr)
sys.exit(int(os.environ.get('STUB_PARSE_EXIT', '0')))
""")

    def write_tool(self, name, body):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\n" + body)
        path.chmod(0o755)

    def run_runner(self, *args, summary=None, overrides=None):
        env = self.env.copy()
        if summary is not None:
            env["STUB_SUMMARY"] = json.dumps(summary) if not isinstance(summary, str) else summary
        env.update(overrides or {})
        result = subprocess.run(["/bin/bash", str(self.runner), "--output-dir", str(self.output), *args],
                                cwd=self.root, env=env, text=True, capture_output=True, timeout=10)
        # Random run suffixes are unique, not chronologically sortable.
        paths = [line.removeprefix("Result Bundle: ") for line in result.stdout.splitlines()
                 if line.startswith("Result Bundle: ")]
        self.last_run = Path(paths[0]).parent if paths else None
        return result

    def artifacts(self):
        return sorted(self.output.glob("run-*"))

    def receipt(self):
        self.assertIsNotNone(self.last_run, "runner did not report its artifact path")
        return json.loads((self.last_run / "verification.json").read_text())

    def invocations(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def assert_rejected(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("ALL TESTS PASSED", result.stdout)
        self.assertFalse(self.receipt()["passed"])

    def test_actual_saved_xcresult_summaries_pass(self):
        for fixture in ("unit_test_summary.json", "ui_test_summary.json"):
            with self.subTest(fixture=fixture):
                summary = (REPO / "migration/fixtures/ios_test_results" / fixture).read_text()
                result = self.run_runner(summary=summary)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("ALL TESTS PASSED", result.stdout)

    def test_unique_artifacts_preserve_old_and_new_evidence(self):
        old_bundle = self.project / "TestResults.xcresult"
        old_bundle.mkdir()
        (old_bundle / "old").write_text("keep")
        old_log = self.project / "test_output.log"
        old_log.write_text("old log")
        for _ in range(2):
            result = self.run_runner("--quick")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.artifacts()), 2)
        for run in self.artifacts():
            self.assertEqual((run / "TestResults.xcresult/evidence.txt").read_text(), "retained result evidence")
            self.assertIn("stub build output", (run / "xcodebuild.log").read_text())
            self.assertEqual(json.loads((run / "summary.json").read_text()), PASSING_SUMMARY)
            self.assertIn("stub parser diagnostic", (run / "xcresulttool.log").read_text())
            self.assertTrue(json.loads((run / "verification.json").read_text())["passed"])
        self.assertEqual((old_bundle / "old").read_text(), "keep")
        self.assertEqual(old_log.read_text(), "old log")

    def test_selectors_default_ui_unit_ui_and_all(self):
        for args, targets in (([], ["LoopaUITests"]), (["--unit"], ["LoopaTests"]),
                              (["--ui"], ["LoopaUITests"]),
                              (["--all"], ["LoopaTests", "LoopaUITests"])):
            with self.subTest(args=args):
                result = self.run_runner(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                command = [c for c in self.invocations() if c["tool"] == "xcodebuild"][-1]["args"]
                self.assertEqual([a for a in command if a.startswith("-only-testing:")],
                                 [f"-only-testing:{target}" for target in targets])

    def test_specific_test_and_destination_are_literal_arguments(self):
        destination = "platform=iOS Simulator,id=ABCD"
        marker = self.root / "injected"
        test_name = f"SomeTests/testName; touch {marker}"
        result = self.run_runner("--unit", "--test", test_name, "--destination", destination)
        self.assertEqual(result.returncode, 0, result.stderr)
        command = self.invocations()[0]["args"]
        self.assertEqual(command[command.index("-destination") + 1], destination)
        self.assertIn(f"-only-testing:LoopaTests/{test_name}", command)
        self.assertFalse(marker.exists())

    def test_all_requires_qualified_specific_test(self):
        result = self.run_runner("--all", "--test", "LoopaTests/MathTests/testExample")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-only-testing:LoopaTests/MathTests/testExample", self.invocations()[0]["args"])
        self.calls.unlink()
        result = self.run_runner("--all", "--test", "MathTests/testExample")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_expected_count_matches_or_rejects(self):
        result = self.run_runner("--expected-tests", "2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_rejected(self.run_runner("--expected-tests", "3"))

    def test_nonzero_xcodebuild_overrides_passing_summary(self):
        result = self.run_runner(overrides={"STUB_BUILD_EXIT": "65"})
        self.assert_rejected(result)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(self.receipt()["xcodebuildExitCode"], 65)

    def test_nonzero_summary_command_overrides_valid_json(self):
        self.assert_rejected(self.run_runner(overrides={"STUB_PARSE_EXIT": "9"}))
        self.assertEqual(self.receipt()["summaryExitCode"], 9)

    def test_missing_bundle_fails_even_when_build_command_succeeds(self):
        self.assert_rejected(self.run_runner(overrides={"STUB_NO_BUNDLE": "1"}))
        self.assertEqual([call["tool"] for call in self.invocations()], ["xcodebuild"])

    def test_empty_malformed_wrong_type_and_duplicate_json_fail(self):
        for summary in ("", "not JSON", "[]", "null", '{"passedTests": 2, "passedTests": 2}'):
            with self.subTest(summary=summary):
                self.assert_rejected(self.run_runner(summary=summary))

    def test_nonfinite_json_tokens_are_rejected_outside_counters(self):
        for field, value in (("startTime", float("nan")), ("finishTime", float("inf")),
                             ("finishTime", float("-inf"))):
            with self.subTest(field=field, value=value):
                self.assert_rejected(self.run_runner(summary=dict(PASSING_SUMMARY, **{field: value})))
        summary = dict(PASSING_SUMMARY, statistics=[{"unrelatedMetric": float("nan")}])
        self.assert_rejected(self.run_runner(summary=summary))

    def test_device_outcomes_cannot_contradict_passing_summary(self):
        record = PASSING_SUMMARY["devicesAndConfigurations"][0]
        for changes in ({"failedTests": 1}, {"skippedTests": 1}, {"expectedFailures": 1},
                        {"result": "Failed"}, {"result": "Error"}, {"result": "Skipped"},
                        {"testFailures": [{"failureText": "device failure"}]}):
            with self.subTest(changes=changes):
                summary = dict(PASSING_SUMMARY, devicesAndConfigurations=[dict(record, **changes)])
                self.assert_rejected(self.run_runner(summary=summary))

    def test_device_counters_must_be_valid_and_consistent(self):
        record = PASSING_SUMMARY["devicesAndConfigurations"][0]
        for changes in ({"passedTests": 1}, {"passedTests": 3}, {"failedTests": -1},
                        {"skippedTests": "0"}, {"expectedFailures": False},
                        {"passedTests": None}, {"totalTestCount": 3}, {"testFailures": "invalid"}):
            with self.subTest(changes=changes):
                summary = dict(PASSING_SUMMARY, devicesAndConfigurations=[dict(record, **changes)])
                self.assert_rejected(self.run_runner(summary=summary))
        missing = record.copy()
        del missing["skippedTests"]
        for records in (None, {}, [], [None], [missing]):
            with self.subTest(records=records):
                self.assert_rejected(self.run_runner(summary=dict(PASSING_SUMMARY,
                                                                  devicesAndConfigurations=records)))

    def test_repeated_per_configuration_counts_are_not_added_to_summary_counts(self):
        record = PASSING_SUMMARY["devicesAndConfigurations"][0]
        summary = dict(PASSING_SUMMARY, devicesAndConfigurations=[record.copy(), record.copy()])
        result = self.run_runner(summary=summary)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_partitioned_configuration_counts_and_every_configuration_are_checked(self):
        record = dict(PASSING_SUMMARY["devicesAndConfigurations"][0], passedTests=1)
        summary = dict(PASSING_SUMMARY, devicesAndConfigurations=[record.copy(), record.copy()])
        result = self.run_runner(summary=summary)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for changes in ({"failedTests": 1}, {"passedTests": 0}):
            with self.subTest(changes=changes):
                summary = dict(PASSING_SUMMARY,
                               devicesAndConfigurations=[record.copy(), dict(record, **changes)])
                self.assert_rejected(self.run_runner(summary=summary))

    def test_unrelated_metadata_result_fields_are_not_test_outcomes(self):
        record = dict(PASSING_SUMMARY["devicesAndConfigurations"][0],
                      testPlanConfiguration={"result": "unrelated metadata"})
        summary = dict(PASSING_SUMMARY, devicesAndConfigurations=[record],
                       statistics=[{"result": "not a test status"}])
        result = self.run_runner(summary=summary)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_invalid_negative_and_boolean_counts_fail(self):
        for value in (None, "2", -1, True, 1.5):
            with self.subTest(value=value):
                self.assert_rejected(self.run_runner(summary=dict(PASSING_SUMMARY, passedTests=value)))
        summary = PASSING_SUMMARY.copy()
        del summary["totalTestCount"]
        self.assert_rejected(self.run_runner(summary=summary))

    def test_zero_tests_fail(self):
        self.assert_rejected(self.run_runner(summary=dict(PASSING_SUMMARY, totalTestCount=0, passedTests=0)))

    def test_skipped_required_test_fails(self):
        self.assert_rejected(self.run_runner(summary=dict(PASSING_SUMMARY, passedTests=1, skippedTests=1)))

    def test_expected_failure_is_not_a_pass(self):
        self.assert_rejected(self.run_runner(summary=dict(PASSING_SUMMARY, passedTests=1, expectedFailures=1)))

    def test_failed_test_overrides_zero_command_exit(self):
        self.assert_rejected(self.run_runner(summary=dict(PASSING_SUMMARY, passedTests=1, failedTests=1)))

    def test_inconsistent_counts_fail(self):
        self.assert_rejected(self.run_runner(summary=dict(PASSING_SUMMARY, totalTestCount=3)))

    def test_failed_result_and_failure_records_override_passing_counts(self):
        for changes in ({"result": "Failed"}, {"testFailures": [{"testName": "A", "failureText": "bad"}]},
                        {"testFailures": "invalid"}):
            with self.subTest(changes=changes):
                self.assert_rejected(self.run_runner(summary=dict(PASSING_SUMMARY, **changes)))

    def test_cannot_write_log_is_a_failure(self):
        self.write_tool("tee", "import sys\nsys.stdin.read()\nsys.exit(17)\n")
        self.assert_rejected(self.run_runner())
        self.assertEqual(self.receipt()["logExitCode"], 17)

    def test_quick_mode_still_saves_raw_json_and_checks_failures(self):
        result = self.run_runner("--quick")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("--- SUMMARY JSON ---", result.stdout)
        self.assertEqual(json.loads((self.artifacts()[0] / "summary.json").read_text()), PASSING_SUMMARY)
        self.assert_rejected(self.run_runner("--quick", summary=dict(PASSING_SUMMARY, skippedTests=1)))

    def test_relative_output_directory_uses_callers_directory(self):
        result = self.run_runner("--output-dir", "relative results")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list((self.root / "relative results").glob("run-*"))), 1)

    def test_default_output_is_under_excluded_build_directory(self):
        result = subprocess.run(["/bin/bash", str(self.runner), "--quick"], cwd=self.root,
                                env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list((self.project / "build/test-results").glob("run-*"))), 1)

    def test_help_and_bad_arguments_do_not_run_tools(self):
        for args in (("--help",), ("-h",)):
            result = self.run_runner(*args)
            self.assertEqual(result.returncode, 0)
            self.assertIn("--all", result.stdout)
        for args in (("--bogus",), ("--test",), ("--destination",), ("--output-dir",),
                     ("--expected-tests",), ("--expected-tests", "0"), ("--expected-tests", "bad"),
                     ("--destination", ""), ("--test", "--unit")):
            with self.subTest(args=args):
                result = self.run_runner(*args)
                self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_termination_preserves_partial_bundle_and_log(self):
        ready = self.root / "build ready"
        env = dict(self.env, STUB_WAIT=str(ready))
        process = subprocess.Popen(["/bin/bash", str(self.runner), "--output-dir", str(self.output)],
                                   cwd=self.root, env=env, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "stub build did not start")
            os.killpg(process.pid, signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=5)
            self.assertNotEqual(process.returncode, 0, stdout + stderr)
            self.assertNotIn("ALL TESTS PASSED", stdout)
            run = self.artifacts()[0]
            self.assertEqual((run / "TestResults.xcresult/evidence.txt").read_text(), "retained result evidence")
            self.assertIn("stub build output", (run / "xcodebuild.log").read_text())
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
