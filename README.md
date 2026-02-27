# continuity-master-plan
Public memory archive: Continuity Master Plan by Logan Ryker

## Linux system analysis, cleanup, and optimization
This repository now includes an executable system utility for Linux hosts:

- `scripts/linux_system_optimizer.sh`

### What it does
- Collects a full system audit report (CPU, memory, disk, process hotspots, failed services, and basic pressure indicators).
- Surfaces cleanup opportunities (package caches, journal logs, stale `/tmp` files).
- Surfaces runtime optimization opportunities (swappiness, file limits, startup service footprint, CPU governor checks).
- Optionally applies cleanup and runtime tuning commands with root/sudo.

### Usage
```bash
# Audit only
scripts/linux_system_optimizer.sh --analyze

# Audit + cleanup recommendations
scripts/linux_system_optimizer.sh --clean

# Audit + optimization recommendations
scripts/linux_system_optimizer.sh --optimize

# Full audit + cleanup + optimization recommendations
scripts/linux_system_optimizer.sh --full

# Apply cleanup and optimization immediately (non-interactive)
scripts/linux_system_optimizer.sh --full --apply --yes
```

Reports are saved under `reports/` by default.
