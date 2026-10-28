"""Require a release commit on main with successful CI for that exact SHA."""

import json
import os
import re
import subprocess
import sys


def github_api(endpoint):
    result = subprocess.run(
        ["gh", "api", endpoint], check=True, capture_output=True, text=True
    )
    return json.loads(result.stdout)


def verify_release(repository, sha, api=github_api):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repository):
        raise ValueError("Invalid repository")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Invalid release commit SHA")
    comparison = api(f"repos/{repository}/compare/{sha}...main")
    if (comparison.get("status") not in ("ahead", "identical")
            or comparison.get("merge_base_commit", {}).get("sha") != sha):
        raise ValueError("Release commit must be contained in main")

    runs = api(
        f"repos/{repository}/actions/workflows/ci.yaml/runs"
        f"?branch=main&event=push&head_sha={sha}&per_page=1"
    ).get("workflow_runs", [])
    if not runs:
        raise ValueError("No main push CI run exists for the release commit")
    run = runs[0]
    expected = {
        "head_sha": sha,
        "head_branch": "main",
        "event": "push",
        "path": ".github/workflows/ci.yaml",
        "status": "completed",
        "conclusion": "success",
    }
    if any(run.get(key) != value for key, value in expected.items()):
        raise ValueError("Latest main push CI run for the release commit must succeed")
    if run.get("head_repository", {}).get("full_name") != repository:
        raise ValueError("CI must run in the publishing repository")
    return run["id"]


if __name__ == "__main__":
    try:
        run_id = verify_release(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_SHA"])
    except (KeyError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Release verification failed: {error}", file=sys.stderr)
        sys.exit(1)
    print(f"Release verified against main and successful CI run {run_id}")
