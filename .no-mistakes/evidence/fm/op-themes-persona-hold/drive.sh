#!/usr/bin/env bash
# Drive persona headline scenarios against real bin/ scripts in disposable lab homes.
set -u
WT=$1; EV=$2; cd "$WT"
run() { local home=$1; shift; env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$home" "$@"; }
mklab() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); bin/fm-lab-home.sh create "$d" >/dev/null; echo "$d"; }
head_of() { awk '/SESSION START/{f=1} f{print} /LOCK/{if(f) exit}' "$1"; }
LABS=()
banner() { printf '\n===== %s =====\n' "$*"; }

banner "S3 nautical home: headline bytes and session-start head"
P=$(mklab); LABS+=("$P")
printf 'headline bytes: %s\n' "$(run "$P" bin/po-theme.sh headline | wc -c | tr -d ' ')"
run "$P" bin/fm-session-start.sh --source startup > "$EV/s3-nautical-digest.txt" 2>&1; echo "session-start rc=$?"
head_of "$EV/s3-nautical-digest.txt"
printf 'PERSONA/drift lines in digest: %s\n' "$(grep -cE '^PERSONA|persona drift' "$EV/s3-nautical-digest.txt")"

banner "S1 primary operator theme applied: full digest head"
echo operator > "$P/config/po-theme"
run "$P" bin/po-theme.sh apply 2>&1 | tail -3
run "$P" bin/po-theme.sh verify
run "$P" bin/fm-session-start.sh --source startup > "$EV/s1-operator-digest.txt" 2>&1; echo "session-start rc=$?"
head_of "$EV/s1-operator-digest.txt"
printf 'byte offset of PERSONA line in digest: %s (harness inline preview ~2000)\n' "$(grep -bm1 '^PERSONA' "$EV/s1-operator-digest.txt" | cut -d: -f1)"
printf 'digest total bytes: %s; byte offset of full "## Persona" block: %s\n' "$(wc -c < "$EV/s1-operator-digest.txt" | tr -d ' ')" "$(grep -bm1 '^## Persona' "$EV/s1-operator-digest.txt" | cut -d: -f1)"

banner "S2 primary operator theme: --reemit (post-compaction) head"
run "$P" bin/fm-session-start.sh --reemit --source compact > "$EV/s2-operator-reemit.txt" 2>&1; echo "session-start rc=$?"
head_of "$EV/s2-operator-reemit.txt"
printf 'byte offset of PERSONA line: %s\n' "$(grep -bm1 '^PERSONA' "$EV/s2-operator-reemit.txt" | cut -d: -f1)"

banner "S4 primary drift: hand-edited Persona block"
cp "$P/data/captain-shared.md" "$P/shared.bak"
sed -i '' 's/all systems nominal/ALL QUIET/' "$P/data/captain-shared.md"
run "$P" bin/po-theme.sh verify; echo "verify rc=$?"
run "$P" bin/po-theme.sh headline
run "$P" bin/fm-session-start.sh --reemit --source compact > "$EV/s4-drift-reemit.txt" 2>&1
head_of "$EV/s4-drift-reemit.txt"
cp "$P/shared.bak" "$P/data/captain-shared.md"

banner "S5 nautical selected but stale Persona block left (apply not rerun)"
echo nautical > "$P/config/po-theme"
run "$P" bin/po-theme.sh headline; echo "headline rc=$?"
run "$P" bin/fm-session-start.sh --reemit --source compact > "$EV/s5-nautical-stale.txt" 2>&1
head_of "$EV/s5-nautical-stale.txt"
banner "S5b after nautical apply: block removed, headline silent"
run "$P" bin/po-theme.sh apply 2>&1 | tail -2
printf 'headline bytes: %s\n' "$(run "$P" bin/po-theme.sh headline | wc -c | tr -d ' ')"

banner "S6 secondmate inheriting current bundled operator block: no drift"
S=$(mklab); LABS+=("$S"); touch "$S/.fm-secondmate-home"
echo operator > "$P/config/po-theme"; run "$P" bin/po-theme.sh apply >/dev/null 2>&1
cp "$P/data/captain-shared.md" "$S/data/captain-shared.md"
run "$S" bin/po-theme.sh verify; echo "verify rc=$?"
run "$S" bin/po-theme.sh headline

banner "S7 secondmate inheriting an older self-consistent block (differs from bundled)"
L=$(mklab); LABS+=("$L"); mkdir -p "$L/config/po-themes"
sed 's/^noop_reply = .*/noop_reply = "Operator, standing by."/' .agents/skills/po-theme/themes/operator.theme > "$L/config/po-themes/operator.theme"
echo operator > "$L/config/po-theme"; run "$L" bin/po-theme.sh apply >/dev/null 2>&1
grep -o 'source=local -->' "$L/data/captain-shared.md"
# simulate an older bundled-theme block: same block without the local token
sed 's/ source=local -->/ -->/' "$L/data/captain-shared.md" > "$S/data/captain-shared.md"
run "$S" bin/po-theme.sh verify; echo "verify rc=$?"
run "$S" bin/po-theme.sh headline
run "$S" bin/fm-session-start.sh --source startup > "$EV/s7-secondmate-older-block.txt" 2>&1
head_of "$EV/s7-secondmate-older-block.txt"

banner "S8 secondmate inheriting a local (source=local) primary-only override: comparison skipped"
cp "$L/data/captain-shared.md" "$S/data/captain-shared.md"
run "$S" bin/po-theme.sh verify; echo "verify rc=$?"
run "$S" bin/po-theme.sh headline

banner "S9 secondmate inheriting a hand-edited block"
awk '!/^<!--/{sub(/standing by/,"ZZZ")} {print}' "$L/data/captain-shared.md" > "$S/data/captain-shared.md"
run "$S" bin/po-theme.sh verify; echo "verify rc=$?"
run "$S" bin/po-theme.sh headline

banner "S10 AGENTS.md Persona line"
grep -c '^Persona: ' AGENTS.md; grep '^Persona: ' AGENTS.md

for d in "${LABS[@]}"; do rm -rf "$d"; done
echo "labs removed"
