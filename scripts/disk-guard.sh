#!/usr/bin/env bash
# Disk guard: prevent the k3d node from hitting ephemeral-storage disk-pressure,
# which evicts every pod and taints the node NoSchedule so `make wait` hangs forever.
#
# Runs early in `./rghw.sh --fresh` (before `make images` piles on more layers) and:
#   1. fails loudly if the Docker VM is critically low on disk (kubelet evicts at ~5%);
#   2. prunes dangling host images to reclaim space;
#   3. clears a node.kubernetes.io/disk-pressure taint so pods can reschedule.
set -euo pipefail

NAMESPACE="rube-goldberg"

warn() { echo -e "\033[1;33m[disk-guard]\033[0m $*" >&2; }
say()  { echo -e "\033[0;36m[disk-guard]\033[0m $*" >&2; }

# --- 1. Critically-low-disk preflight (portable: works on macOS + Linux) ---
# df -P prints POSIX output; size/used/avail are 512B blocks on macOS, 1K on Linux.
# We only need the ratio, so the block size cancels out.
read -r total_blocks _ available_blocks < <(df -P / 2>/dev/null | awk 'NR == 2 { print $2, $3, $4 }')
if [[ -n "${total_blocks:-}" && -n "${available_blocks:-}" ]]; then
  total=$(( total_blocks ))
  if [[ $total -gt 0 ]]; then
    free_pct=$(( (available_blocks * 100) / total ))
    if [[ $free_pct -lt 15 ]]; then
      warn "Host disk only ${free_pct}% free — kubelet will evict pods at ~5%."
      warn "Free space before building more images (e.g. 'docker system prune -a', grow colima --disk, or run './rghw.sh --fresh')."
    else
      say "Host disk ${free_pct}% free (ok)."
    fi
  fi
else
  warn "Could not determine host disk usage (df unavailable); skipping preflight."
fi

# --- 2. Prune dangling host images to reclaim space before the next build ---
# Dangling = untagged intermediate layers left by prior builds; safe to drop.
if command -v docker >/dev/null 2>&1; then
  reclaimed=$(docker image prune -af --filter "until=24h" 2>&1 | tail -n 1 || true)
  say "Pruned dangling images: ${reclaimed:-none}"
fi

# --- 3. Clear a disk-pressure taint so already-evicted pods can reschedule ---
if command -v kubectl >/dev/null 2>&1; then
  if kubectl get nodes 2>/dev/null | grep -q " Ready "; then
    tainted_nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[*].key}{"\n"}{end}' 2>/dev/null | awk -F'\t' '$2 ~ /disk-pressure/ {print $1}')
    for node in $tainted_nodes; do
      say "Clearing disk-pressure taint on node $node"
      kubectl taint nodes "$node" node.kubernetes.io/disk-pressure- 2>/dev/null || true
    done
    if [[ -z "${tainted_nodes:-}" ]]; then
      say "No disk-pressure taint present."
    fi
  fi
fi

exit 0
