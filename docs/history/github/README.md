# GitHub migration archive

This directory preserves GitHub-only metadata that GitHub discards when a public fork leaves its fork network.

- `pr-2.json`: pull request metadata, reviews, inline comments, timeline, commits, and file statistics for PR #2.
- `pr-3.json`: the equivalent record for PR #3.
- `repository-before-detach.json`: repository settings, refs, releases, and Actions configuration captured before detachment.

The source patches are not duplicated here because their commits remain in git history. The JSON files are historical snapshots, not live configuration.

Original repository: https://github.com/wylie102/duckdb.yazi
Continuation: https://github.com/stevencarpenter/duckdb.yazi
