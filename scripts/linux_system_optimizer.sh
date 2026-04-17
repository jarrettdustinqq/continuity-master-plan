#!/usr/bin/env bash
# linux_system_optimizer.sh — Linux host audit, cleanup, and optimization utility
# Part of the Continuity System (Logan Ryker)
#
# Modes:
#   --analyze   Gather diagnostics and write a report (read-only)
#   --clean     Remove package caches, journal logs, stale /tmp files (requires --apply --yes)
#   --optimize  Apply sysctl tuning (requires --apply --yes)
#   --full      Run analyze + clean + optimize
#
# Safety flags:
#   --apply     Enable write/mutating actions (requires --yes)
#   --yes       Confirm apply actions (must pair with --apply)
#
# Usage examples:
#   bash linux_system_optimizer.sh --analyze
#   sudo bash linux_system_optimizer.sh --clean --apply --yes
#   sudo bash linux_system_optimizer.sh --full --apply --yes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORTS_DIR="$REPO_ROOT/reports"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_FILE="$REPORTS_DIR/system-audit-${TIMESTAMP}.txt"

MODE_ANALYZE=false
MODE_CLEAN=false
MODE_OPTIMIZE=false
DO_APPLY=false
DO_YES=false

# ─── Arg parsing ────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --analyze)  MODE_ANALYZE=true ;;
    --clean)    MODE_CLEAN=true ;;
    --optimize) MODE_OPTIMIZE=true ;;
    --full)     MODE_ANALYZE=true; MODE_CLEAN=true; MODE_OPTIMIZE=true ;;
    --apply)    DO_APPLY=true ;;
    --yes)      DO_YES=true ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      echo "[error] Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if ! $MODE_ANALYZE && ! $MODE_CLEAN && ! $MODE_OPTIMIZE; then
  echo "[error] Specify at least one mode: --analyze, --clean, --optimize, or --full" >&2
  exit 1
fi

if ($MODE_CLEAN || $MODE_OPTIMIZE) && $DO_APPLY && ! $DO_YES; then
  echo "[error] --apply requires --yes to confirm mutating actions." >&2
  exit 1
fi

# ─── Helpers ────────────────────────────────────────────────────────────────────
log()  { echo "[$(date -u +%H:%M:%SZ)] $*" | tee -a "$REPORT_FILE"; }
warn() { echo "[warn] $*" | tee -a "$REPORT_FILE" >&2; }
section() { echo "" | tee -a "$REPORT_FILE"; echo "═══ $* ═══" | tee -a "$REPORT_FILE"; }

mkdir -p "$REPORTS_DIR"
echo "System Audit Report — $TIMESTAMP" > "$REPORT_FILE"
echo "Host: $(hostname -f 2>/dev/null || hostname)" >> "$REPORT_FILE"
echo "User: $(whoami)" >> "$REPORT_FILE"
echo "Modes: analyze=$MODE_ANALYZE clean=$MODE_CLEAN optimize=$MODE_OPTIMIZE apply=$DO_APPLY" >> "$REPORT_FILE"

# ─── ANALYZE ────────────────────────────────────────────────────────────────────
if $MODE_ANALYZE; then
  section "KERNEL / OS"
  log "Kernel: $(uname -r)"
  log "OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo unknown)"
  log "Uptime: $(uptime -p 2>/dev/null || uptime)"

  section "CPU"
  log "CPUs: $(nproc)"
  log "Load avg: $(cut -d' ' -f1-3 /proc/loadavg)"
  if command -v top &>/dev/null; then
    log "Top 5 CPU consumers:"
    ps aux --sort=-%cpu 2>/dev/null | awk 'NR<=6{print}' | tee -a "$REPORT_FILE" || true
  fi

  section "MEMORY"
  free -h 2>/dev/null | tee -a "$REPORT_FILE" || cat /proc/meminfo | grep -E '^(Mem|Swap)' | tee -a "$REPORT_FILE"
  SWAP_TOTAL=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
  if [[ "$SWAP_TOTAL" == "0" ]]; then
    warn "No swap configured — agent stalls likely under memory pressure"
  fi

  section "DISK"
  df -h 2>/dev/null | tee -a "$REPORT_FILE" || true
  log "Inodes:"
  df -i 2>/dev/null | tee -a "$REPORT_FILE" || true

  section "PROCESS HOTSPOTS"
  log "Top 5 memory consumers:"
  ps aux --sort=-%mem 2>/dev/null | awk 'NR<=6{print}' | tee -a "$REPORT_FILE" || true

  section "FAILED SERVICES"
  if command -v systemctl &>/dev/null; then
    systemctl --failed --no-legend 2>/dev/null | tee -a "$REPORT_FILE" || true
  else
    log "systemctl not available"
  fi

  section "BOOT ANALYSIS"
  if command -v systemd-analyze &>/dev/null; then
    systemd-analyze blame 2>/dev/null | head -20 | tee -a "$REPORT_FILE" || true
  else
    log "systemd-analyze not available"
  fi

  section "FILE DESCRIPTOR PRESSURE"
  log "Open FDs: $(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1"/"$3}' || echo unknown)"
  log "max_user_watches: $(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo unknown)"
  log "vm.swappiness: $(cat /proc/sys/vm/swappiness 2>/dev/null || echo unknown)"

  section "JOURNAL DISK USAGE"
  if command -v journalctl &>/dev/null; then
    journalctl --disk-usage 2>/dev/null | tee -a "$REPORT_FILE" || true
  fi

  section "PACKAGE CACHE SIZE"
  if command -v apt-get &>/dev/null; then
    du -sh /var/cache/apt/archives 2>/dev/null | tee -a "$REPORT_FILE" || true
  fi
  if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
    du -sh /var/cache/dnf 2>/dev/null | tee -a "$REPORT_FILE" || true
  fi
  if command -v pacman &>/dev/null; then
    du -sh /var/cache/pacman 2>/dev/null | tee -a "$REPORT_FILE" || true
  fi

  log ""
  log "Analyze complete. Report: $REPORT_FILE"
fi

# ─── CLEAN ──────────────────────────────────────────────────────────────────────
if $MODE_CLEAN; then
  section "CLEANUP"
  if $DO_APPLY && $DO_YES; then
    # Package cache
    if command -v apt-get &>/dev/null; then
      log "Cleaning apt cache..."
      apt-get clean -y 2>&1 | tee -a "$REPORT_FILE" || warn "apt-get clean failed"
      apt-get autoremove -y 2>&1 | tee -a "$REPORT_FILE" || warn "apt-get autoremove failed"
    fi
    if command -v dnf &>/dev/null; then
      log "Cleaning dnf cache..."
      dnf clean all 2>&1 | tee -a "$REPORT_FILE" || warn "dnf clean failed"
    fi
    if command -v yum &>/dev/null; then
      log "Cleaning yum cache..."
      yum clean all 2>&1 | tee -a "$REPORT_FILE" || warn "yum clean failed"
    fi
    if command -v pacman &>/dev/null; then
      log "Cleaning pacman cache..."
      pacman -Sc --noconfirm 2>&1 | tee -a "$REPORT_FILE" || warn "pacman -Sc failed"
    fi

    # Journal vacuum
    if command -v journalctl &>/dev/null; then
      log "Vacuuming journal (keep 200MB / 2 weeks)..."
      journalctl --vacuum-size=200M 2>&1 | tee -a "$REPORT_FILE" || warn "journal vacuum-size failed"
      journalctl --vacuum-time=2weeks 2>&1 | tee -a "$REPORT_FILE" || warn "journal vacuum-time failed"
    fi

    # Stale /tmp files older than 7 days
    log "Removing stale /tmp files older than 7 days..."
    find /tmp -maxdepth 2 -atime +7 -delete 2>/dev/null | tee -a "$REPORT_FILE" || warn "/tmp cleanup partial"

    log "Cleanup complete."
  else
    log "[dry-run] Would clean: apt/dnf/yum/pacman cache, journal logs, stale /tmp files"
    log "[dry-run] Re-run with --apply --yes to execute (requires root for some operations)"
  fi
fi

# ─── OPTIMIZE ───────────────────────────────────────────────────────────────────
if $MODE_OPTIMIZE; then
  section "SYSCTL OPTIMIZATION"
  SYSCTL_PARAMS=(
    "vm.swappiness=10"
    "fs.inotify.max_user_watches=524288"
    "fs.file-max=1000000"
  )
  if $DO_APPLY && $DO_YES; then
    for param in "${SYSCTL_PARAMS[@]}"; do
      key="${param%%=*}"
      val="${param##*=}"
      log "Setting $key=$val"
      if sysctl -w "$key=$val" 2>&1 | tee -a "$REPORT_FILE"; then
        # Persist across reboots
        CONF_FILE="/etc/sysctl.d/99-continuity-optimizer.conf"
        if [[ -w /etc/sysctl.d/ ]]; then
          grep -qxF "$key=$val" "$CONF_FILE" 2>/dev/null || echo "$key=$val" >> "$CONF_FILE"
          log "Persisted to $CONF_FILE"
        else
          warn "Cannot write to /etc/sysctl.d/ — setting is not persistent"
        fi
      else
        warn "sysctl write failed for $key (may be read-only in container)"
      fi
    done
    log "Optimization complete."
  else
    log "[dry-run] Would apply sysctl params:"
    for param in "${SYSCTL_PARAMS[@]}"; do
      log "  $param"
    done
    log "[dry-run] Re-run with --apply --yes to execute (requires root)"
  fi
fi

# ─── FINAL SUMMARY ──────────────────────────────────────────────────────────────
section "SUMMARY"
log "Report written: $REPORT_FILE"
log "Status: OK"
echo ""
echo "OK — Report: $REPORT_FILE"
