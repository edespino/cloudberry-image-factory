#!/usr/bin/env bash
# Computes the AMI build matrix from a newline-separated changed-file list on
# stdin. Prints JSON {"build":[{family,name,path},...]} on stdout.
# Rules:
#   vm-images/aws/<family>/build/<os>/**                -> that target
#   vm-images/common/scripts/X.sh                       -> targets whose HCL references X.sh
#   vm-images/scripts/** or vm-images/common/tests/**   -> all targets
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

while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ -f "$file" ] || continue   # deletions cannot affect a build
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

entries=()
for key in "${!picked[@]}"; do
  IFS='|' read -r fam os path <<< "$key"
  entries+=("{\"family\":\"$fam\",\"name\":\"$os\",\"path\":\"$path\"}")
done
printf '{"build":[%s]}\n' "$(IFS=,; echo "${entries[*]-}")"
