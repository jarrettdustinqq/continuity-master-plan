# continuity-master-plan

> **Archive / historical reference.** This repository is not the canonical continuity store or an active production control plane.

The current canonical source of truth for durable project state, repository classifications, decisions, and handoffs is [`jarrettdustinqq/continuity`](https://github.com/jarrettdustinqq/continuity). Check its registry and source-authority rules before relying on historical instructions here.

This repository preserves the public Continuity Master Plan and related historical utilities. Treat plans, status claims, and scripts here as archival until independently checked against the canonical repository and current environment.

## Linux System Optimizer

`scripts/linux_system_optimizer.sh` is a legacy host-audit/optimization utility.

Start with analysis-only mode:

```bash
bash scripts/linux_system_optimizer.sh --analyze
```

Review the script and its report before considering any mutation. The `--full --apply --yes` path requires root and can make host changes; do not run it unattended or treat the confirmation flag as evidence that the proposed changes are appropriate. Back up important data and verify the intended host, current state, and recovery path first.

Reports are written to `reports/system-audit-<timestamp>.txt` (excluded from Git).
