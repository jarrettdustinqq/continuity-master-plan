#!/usr/bin/env bash
set -euo pipefail

MODE="analyze"
APPLY=0
ASSUME_YES=0
REPORT_DIR="reports"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE=""

usage() {
  cat <<'USAGE'
Linux System Optimizer

Usage:
  scripts/linux_system_optimizer.sh [--analyze] [--clean] [--optimize] [--full] [--apply] [--yes] [--report-dir DIR]

Modes:
  --analyze   Gather system diagnostics only (default)
  --clean     Include cleanup recommendations/tasks
  --optimize  Include runtime optimization recommendations/tasks
  --full      Analyze + clean + optimize

Execution:
  --apply     Execute cleanup/optimization commands (requires root/sudo for many actions)
  --yes       Non-interactive apply

Examples:
  scripts/linux_system_optimizer.sh --full
  scripts/linux_system_optimizer.sh --full --apply --yes
USAGE
}

log() { echo "[$(date +%H:%M:%S)] $*"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_report() {
  mkdir -p "$REPORT_DIR"
  REPORT_FILE="$REPORT_DIR/system-audit-$TIMESTAMP.txt"
  : > "$REPORT_FILE"
}

append_section() {
  local title="$1"
  {
    echo
    echo "===== $title ====="
  } >> "$REPORT_FILE"
}

run_capture() {
  local desc="$1"
  shift
  append_section "$desc"
  {
    echo "$ $*"
    "$@"
  } >> "$REPORT_FILE" 2>&1 || {
    echo "Command failed: $*" >> "$REPORT_FILE"
  }
}

run_shell_capture() {
  local desc="$1"
  local cmd="$2"
  append_section "$desc"
  {
    echo "$ $cmd"
    bash -lc "$cmd"
  } >> "$REPORT_FILE" 2>&1 || {
    echo "Command failed: $cmd" >> "$REPORT_FILE"
  }
}

require_root_or_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  if has_cmd sudo; then
    return 0
  fi
  log "ERROR: apply mode requires root or sudo."
  exit 1
}

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

analyze_system() {
  log "Collecting system diagnostics..."
  run_shell_capture "Host and kernel" "uname -a && echo && cat /etc/os-release"
  run_shell_capture "CPU summary" "nproc && lscpu | sed -n '1,25p'"
  run_shell_capture "Memory summary" "free -h && echo && vmstat 1 3"
  run_shell_capture "Disk usage" "df -hT"
  run_shell_capture "Top CPU processes" "ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 20"
  run_shell_capture "Top memory processes" "ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 20"
  if has_cmd iostat; then
    run_shell_capture "Disk I/O" "iostat -xz 1 2"
  else
    append_section "Disk I/O"
    echo "iostat unavailable (install sysstat for deeper I/O diagnostics)." >> "$REPORT_FILE"
  fi
  if has_cmd systemctl; then
    run_shell_capture "Failed services" "systemctl --failed --no-pager || true"
    run_shell_capture "Boot analysis" "systemd-analyze blame | head -n 30 || true"
  fi
  run_shell_capture "Open files pressure" "cat /proc/sys/fs/file-nr"
  run_shell_capture "Swap behavior" "cat /proc/sys/vm/swappiness"
}

clean_recommendations() {
  log "Collecting cleanup opportunities..."
  append_section "Cleanup opportunities"
  {
    echo "Potential cleanup actions:"
    echo "- Package cache cleanup"
    echo "- Log vacuum"
    echo "- Remove stale temp files older than 14 days in /tmp"
  } >> "$REPORT_FILE"

  if has_cmd apt-get; then
    run_shell_capture "APT cache estimate" "du -sh /var/cache/apt/archives 2>/dev/null || true"
  elif has_cmd dnf; then
    run_shell_capture "DNF cache estimate" "du -sh /var/cache/dnf 2>/dev/null || true"
  elif has_cmd pacman; then
    run_shell_capture "Pacman cache estimate" "du -sh /var/cache/pacman/pkg 2>/dev/null || true"
  fi

  run_shell_capture "Journal size" "journalctl --disk-usage 2>/dev/null || echo 'journalctl unavailable'"
  run_shell_capture "Large files in /var/log" "find /var/log -type f -printf '%s %p\n' 2>/dev/null | sort -nr | head -n 20 | awk '{printf \"%.1f MB %s\\n\", \$1/1024/1024, \$2}'"
}

optimize_recommendations() {
  log "Collecting optimization opportunities..."
  append_section "Optimization opportunities"
  {
    echo "Potential optimization actions:"
    echo "- Enable CPU governor performance for low-latency workloads"
    echo "- Tune vm.swappiness to 10 for memory-heavy desktops/servers"
    echo "- Increase open file limits for high-concurrency workloads"
    echo "- Disable unused startup services"
  } >> "$REPORT_FILE"

  run_shell_capture "Current limits" "ulimit -n && cat /proc/sys/fs/file-max"
  if has_cmd systemctl; then
    run_shell_capture "Enabled services" "systemctl list-unit-files --state=enabled --no-pager | head -n 80"
  fi
  if has_cmd cpupower; then
    run_shell_capture "CPU frequency policy" "cpupower frequency-info | sed -n '1,80p'"
  else
    append_section "CPU frequency policy"
    echo "cpupower unavailable; skipping governor diagnostics." >> "$REPORT_FILE"
  fi
}

apply_cleanup() {
  log "Applying cleanup actions..."
  require_root_or_sudo

  if has_cmd apt-get; then
    as_root apt-get -y autoremove
    as_root apt-get -y autoclean
    as_root apt-get -y clean
  elif has_cmd dnf; then
    as_root dnf -y autoremove
    as_root dnf -y clean all
  elif has_cmd pacman; then
    if has_cmd paccache; then
      as_root paccache -r
    fi
  fi

  if has_cmd journalctl; then
    as_root journalctl --vacuum-time=7d || true
  fi

  as_root find /tmp -xdev -type f -mtime +14 -delete || true
}

apply_optimizations() {
  log "Applying runtime optimizations..."
  require_root_or_sudo

  as_root sysctl -w vm.swappiness=10
  as_root sysctl -w fs.inotify.max_user_watches=524288
  as_root sysctl -w fs.file-max=2097152

  if has_cmd cpupower; then
    as_root cpupower frequency-set -g performance || true
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --analyze) MODE="analyze" ;;
      --clean) MODE="clean" ;;
      --optimize) MODE="optimize" ;;
      --full) MODE="full" ;;
      --apply) APPLY=1 ;;
      --yes) ASSUME_YES=1 ;;
      --report-dir) REPORT_DIR="$2"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) log "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done
}

confirm_apply() {
  if [[ "$APPLY" -ne 1 ]]; then
    return 0
  fi

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi

  echo "Apply mode will change system state (cleanup/sysctl tuning). Continue? [y/N]"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]] || {
    log "Cancelled apply mode."
    exit 0
  }
}

main() {
  parse_args "$@"
  ensure_report

  case "$MODE" in
    analyze)
      analyze_system
      ;;
    clean)
      analyze_system
      clean_recommendations
      ;;
    optimize)
      analyze_system
      optimize_recommendations
      ;;
    full)
      analyze_system
      clean_recommendations
      optimize_recommendations
      ;;
    *)
      log "Invalid mode: $MODE"
      exit 1
      ;;
  esac

  if [[ "$APPLY" -eq 1 ]]; then
    confirm_apply
    [[ "$MODE" == "clean" || "$MODE" == "full" ]] && apply_cleanup
    [[ "$MODE" == "optimize" || "$MODE" == "full" ]] && apply_optimizations
  fi

  log "Done. Report: $REPORT_FILE"
}

main "$@"
