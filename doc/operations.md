---
title: Best practices
weight: 7
---

`kareki` works well as a scheduled maintenance task that asks an AI agent to prepare a focused cleanup pull request. It usually should not block every commit or pull request.

## Recommended operating model

Use the following loop:

1. Run a GitHub Actions workflow with `schedule`.
2. Let the workflow trigger an AI agent rather than modify the repository itself.
3. Have the agent run `kareki` against the latest default branch.
4. Investigate each finding and fix only the items that are demonstrably safe to remove.
5. Run formatting, analysis, tests, and `kareki` again.
6. Open a small pull request for normal human review.

This keeps feature delivery independent from repository-wide cleanup and gives the agent enough context to validate removals.

## Why not run it on every pull request?

`kareki` analyzes references across the workspace. A finding reported during a pull request was not necessarily introduced by that pull request.

Making all findings a required check can cause several problems:

- Existing findings block unrelated feature work.
- Developers add broad exclusions merely to make CI pass.
- Large deletions become mixed into feature changes and are harder to review.
- Every commit pays the cost of repository-wide analysis.

Teams that must reject all new findings can add a pull-request check backed by a [baseline](../baseline/). Even then, routine cleanup is best handled in a separate scheduled pull request.

## GitHub Actions example

This workflow triggers an AI agent from a cron schedule.

```yaml {filename=".github/workflows/kareki-cleanup.yml"}
name: "kareki: scheduled cleanup"

on:
  schedule:
    - cron: "0 0 * * *"
  workflow_dispatch:

concurrency:
  group: kareki-scheduled-cleanup
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  trigger-agent:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger the AI agent
        env:
          AI_AGENT_URL: ${{ secrets.AI_AGENT_URL }}
          AI_AGENT_TOKEN: ${{ secrets.AI_AGENT_TOKEN }}
        run: |
          curl --fail-with-body --retry 3 \
            -X POST "$AI_AGENT_URL" \
            -H "Authorization: Bearer $AI_AGENT_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"prompt":"Read .github/kareki-agent.md and perform the scheduled cleanup."}'
```

Adapt `AI_AGENT_URL` and the request body to your AI service. If an external GitHub App creates the branch and pull request, the workflow itself does not need repository write access.

Scheduled workflows run against the latest commit on the default branch, and the workflow file must exist on that branch. See the [GitHub Actions `schedule` documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule) for details.

## Agent instructions

Keep the full instructions in the repository so they can be reviewed independently of the workflow and AI service configuration.

```markdown {filename=".github/kareki-agent.md"}
# Scheduled kareki cleanup

1. Check out the latest default branch.
2. Install dependencies and run `dart run kareki --format json` at the workspace root.
3. Investigate every candidate. Check for dynamic access, code generation, routing, dependency injection, serialization, and external consumers.
4. Remove only items whose safety you can explain. Keep the pull request small and avoid unrelated refactoring.
5. Run `dart format`, `dart analyze`, relevant tests, `dart run kareki`, and `dart run kareki doctor`.
6. Push a branch and open a pull request only when there is a verified change. If there are no safe changes, do nothing.

## Constraints

- Never push directly to the default branch.
- Do not add exclusions or suppressions merely to silence `kareki`.
- Do not edit generated files directly.
- Do not remove public APIs or dynamically referenced code without evidence that they are unused.
- Do not open a pull request with failing tests.

## Pull request description

- List what was removed and why each removal is safe.
- List the verification commands and their results.
- List findings that were left unchanged because they could not be verified.
```

The objective is not to eliminate every finding. It is to fix only findings whose safety can be established. Reflection, code generation, string-based routing, dependency-injection containers, and plugin boundaries deserve extra care.

## Starting point

Begin with only a few findings per pull request. Increase the batch size after the team understands false-positive patterns and review cost.

For a repository with many existing findings, create a baseline first and ask the agent to focus on findings outside the baseline or on the safest rules.
