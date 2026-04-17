# continuity-master-plan
Public memory archive: Continuity Master Plan by Logan Ryker

## Linux System Optimizer

`scripts/linux_system_optimizer.sh` — Auditable tool to analyze, clean, and optimize Linux hosts.
Prevents agent stalls by surfacing memory/disk pressure and applying low-risk tuning.

```bash
# Audit only (no changes)
bash scripts/linux_system_optimizer.sh --analyze

# Full audit + cleanup + optimization (requires root)
sudo bash scripts/linux_system_optimizer.sh --full --apply --yes
```

Reports are written to `reports/system-audit-<timestamp>.txt` (excluded from git).
