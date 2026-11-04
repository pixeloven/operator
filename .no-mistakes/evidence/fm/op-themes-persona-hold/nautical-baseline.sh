#!/usr/bin/env bash
# Run base and target fm-session-start.sh against fresh nautical lab homes; diff the digests.
WT=$1; BASE=$2; EV=$3
run() { env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$1" "${@:2}"; }
for side in base target; do
  root=$WT; [ $side = base ] && root=$BASE
  H=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); (cd "$WT" && bin/fm-lab-home.sh create "$H" >/dev/null)
  for mode in startup reemit; do
    args="--source startup"; [ $mode = reemit ] && args="--reemit --source compact"
    (cd "$root" && run "$H" bin/fm-session-start.sh $args) 2>&1 | sed "s#$H#<LAB>#g; s#$root#<ROOT>#g; s/[0-9]\{4\}-[0-9-]*T[0-9:]*Z*/<TS>/g; s/[0-9][0-9]:[0-9][0-9]\(:[0-9][0-9]\)*/<T>/g" > "$EV/nautical-$side-$mode.txt"
  done
  rm -rf "$H"
done
for mode in startup reemit; do echo "== nautical $mode: base vs target"; diff "$EV/nautical-base-$mode.txt" "$EV/nautical-target-$mode.txt" && echo IDENTICAL; done
