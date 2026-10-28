import copy
import unittest
from unittest.mock import Mock

from verify_release import verify_release


class ReleaseVerificationTests(unittest.TestCase):
    repository = "ostk0069/kareki"
    sha = "a" * 40

    def setUp(self):
        self.comparison = {"status": "identical", "merge_base_commit": {"sha": self.sha}}
        self.run = {
            "id": 123, "head_sha": self.sha, "head_branch": "main", "event": "push",
            "path": ".github/workflows/ci.yaml", "status": "completed",
            "conclusion": "success", "head_repository": {"full_name": self.repository},
        }

    def verify(self, comparison=None, runs=None):
        api = Mock(side_effect=[
            self.comparison if comparison is None else comparison,
            {"workflow_runs": [self.run] if runs is None else runs},
        ])
        return verify_release(self.repository, self.sha, api)

    def test_accepts_main_tip_and_ancestor(self):
        for status in ("identical", "ahead"):
            with self.subTest(status=status):
                self.comparison["status"] = status
                self.assertEqual(self.verify(), 123)

    def test_rejects_commits_outside_main(self):
        for status in ("behind", "diverged"):
            with self.subTest(status=status), self.assertRaises(ValueError):
                self.verify(comparison={"status": status, "merge_base_commit": {"sha": self.sha}})
        with self.assertRaises(ValueError):
            self.verify(comparison={"status": "ahead", "merge_base_commit": {"sha": "b" * 40}})

    def test_rejects_missing_ci(self):
        with self.assertRaises(ValueError):
            self.verify(runs=[])

    def test_rejects_untrusted_or_unsuccessful_ci(self):
        cases = {
            "head_sha": "b" * 40, "head_branch": "other", "event": "pull_request",
            "path": ".github/workflows/other.yaml", "status": "in_progress",
            "conclusion": "failure", "head_repository": {"full_name": "other/fork"},
        }
        for key, value in cases.items():
            run = copy.deepcopy(self.run)
            run[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify(runs=[run])
        for conclusion in ("cancelled", "skipped", "neutral", None):
            with self.subTest(conclusion=conclusion), self.assertRaises(ValueError):
                self.verify(runs=[dict(self.run, conclusion=conclusion)])

    def test_rejects_latest_failure_despite_older_success(self):
        with self.assertRaises(ValueError):
            self.verify(runs=[dict(self.run, conclusion="failure"), self.run])

    def test_rejects_bad_inputs_before_api_call(self):
        api = Mock()
        for repo, sha in (("../repo", self.sha), (self.repository, "main")):
            with self.subTest(repo=repo, sha=sha), self.assertRaises(ValueError):
                verify_release(repo, sha, api)
        api.assert_not_called()


if __name__ == "__main__":
    unittest.main()
