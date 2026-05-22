"""Unit tests for the repair-loop matrix runner (F-042a + F-042b).

Covers the two harness-script defence-in-depth items lodged in
`experiments/repair-loop/findings/compiler-engineer.md` §CE-E:

- F-042a: resolve_batch_dir rejects a --batch-id that already has the
  batch_label suffix appended (prevents silent sibling-directory creation
  on resume).
- F-042b: end-of-matrix exit code splits "completed with prior failures"
  (rc=4) from "aborted" (rc=1).

Run via:
    python3 -m unittest experiments/repair-loop/scripts/test_run_matrix.py
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPTS_DIR))

import run_matrix  # noqa: E402


class ResolveBatchDirSuffixGuardTests(unittest.TestCase):
    """F-042a: silent sibling-directory creation on suffixed --batch-id."""

    def test_rejects_suffixed_batch_id(self):
        args = argparse.Namespace(
            batch_id="20260520T173939Z-matrix",
            output=Path("/tmp/dummy"),
        )
        manifest: dict = {}  # no batch_label → defaults to "matrix"
        with self.assertRaises(SystemExit) as ctx:
            run_matrix.resolve_batch_dir(args, manifest)
        message = str(ctx.exception)
        self.assertIn("20260520T173939Z", message)
        self.assertIn("F-042a", message)


class EndOfMatrixExitCodeTests(unittest.TestCase):
    """F-042b: rc=4 distinguishes 'completed with prior failures' from rc=1 abort."""

    def test_returns_4_when_matrix_completes_with_prior_failure(self):
        with tempfile.TemporaryDirectory() as tmp_str:
            tmp = Path(tmp_str)
            manifest = {
                "experiments": ["e1"],
                "targets": ["t1"],
                "agents": [{"name": "stub-agent", "run_count": 2}],
                "_circuit_breaker_consecutive_infra_fail": 5,
            }
            manifest_path = tmp / "manifest.json"
            manifest_path.write_text(json.dumps(manifest) + "\n", encoding="utf-8")
            outputs = tmp / "runs"

            def fake_run_one_cell(*, cell, batch_dir, manifest, args):
                status = "infrastructure-fail" if cell["cell"] == 1 else "target-reached"
                return {"cell": cell["cell"], "status": status}

            argv = [
                "run_matrix.py",
                str(manifest_path),
                "--output", str(outputs),
                "--skip-prereqs",
                "--no-evaluate",
            ]
            with mock.patch.object(sys, "argv", argv), \
                 mock.patch.object(run_matrix, "run_one_cell", side_effect=fake_run_one_cell):
                rc = run_matrix.main()

            self.assertEqual(rc, run_matrix.EXIT_COMPLETED_WITH_PRIOR_FAILURES)
            self.assertEqual(rc, 4)


if __name__ == "__main__":
    unittest.main()
