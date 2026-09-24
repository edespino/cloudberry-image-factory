#!/usr/bin/env bash
# Computes the target matrix that validate.yml checks from a newline-separated
# changed-file list on stdin, or every target with --all. Prints JSON
# {"build":[{family,name,path},...]} on stdout.
# Rules:
#   vm-images/aws/<family>/build/<os>/**                -> that target
#   vm-images/common/scripts/X.sh                       -> targets whose HCL references X.sh
#   vm-images/scripts/** or vm-images/common/tests/**   -> all targets
# Deleted paths are classified too: deleting a common script still selects
# every template that references it, so the broken reference fails validation.
set -euo pipefail

all_targets() {
  local d fam os
  for d in vm-images/aws/*/build/*/; do
    [ -f "${d}main.pkr.hcl" ] || continue
    fam=$(basename "$(dirname "$(dirname "$d")")")
    os=$(basename "$d")
    echo "$fam $os ${d%/}"
  done
}

declare -A picked=()
add_target() { picked["$1|$2|$3"]=1; }
add_all() { local f n p; while read -r f n p; do add_target "$f" "$n" "$p"; done < <(all_targets); }

if [ "${1:-}" = "--all" ]; then
  add_all
else
while IFS= read -r file; do
  [ -z "$file" ] && continue
  case "$file" in
    vm-images/aws/*/build/*/*)
      fam=$(echo "$file" | cut -d/ -f3); os=$(echo "$file" | cut -d/ -f5)
      dir="vm-images/aws/$fam/build/$os"
      [ -f "$dir/main.pkr.hcl" ] && add_target "$fam" "$os" "$dir"
      ;;
    vm-images/common/scripts/*.sh)
      script=$(basename "$file")
      while read -r f n p; do
        grep -q "$script" "$p/main.pkr.hcl" && add_target "$f" "$n" "$p"
      done < <(all_targets)
      ;;
    vm-images/scripts/*|vm-images/common/tests/*)
      add_all
      ;;
  esac
done
fi

entries=()
for key in "${!picked[@]}"; do
  IFS='|' read -r fam os path <<< "$key"
  entries+=("{\"family\":\"$fam\",\"name\":\"$os\",\"path\":\"$path\"}")
done
printf '{"build":[%s]}\n' "$(IFS=,; echo "${entries[*]-}")"
