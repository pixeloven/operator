#!/usr/bin/env bash
# tests/po-theme-surfaces.test.sh - behavior tests for ADR-0020 stage S5: the
# Bearings board, the fleet view, the human inbox commands, the voice relay's
# spoken words, and the alias-skill descriptions, plus the board's design-system
# injection of ADR-0034 (DS6).
#
# Coverage:
#   - render-board prints the template byte for byte under nautical, with or
#     without the Firstmate Default design system applied
#   - under the operator theme the rendered and the built board carry no
#     "captain" and no "Captain's Call", the page still renders, and an answer
#     queued from the themed board closes a held call through
#     fm-bearings-answer.v1 and the real keyed-answer intake
#   - a theme's icon.brand and icon.underway pictures replace the board's
#     anchor and ship; an invalid icon keeps nautical's
#   - an applied design system other than the Firstmate Default is injected as
#     one style element right after the template's own, under any theme
#   - the fleet view and the inbox note and status output are upstream's at the
#     pin under nautical (golden), and differ under operator in exactly the
#     themed words (golden)
#   - the voice relay's session prompt is upstream's under nautical and gains
#     one vocabulary paragraph under a theme
#   - alias skills describe their command in the theme's words, and verify
#     reports a hand-edited one
#   - the A9 registry check accepts a hook line as often as rows register it
#   - validation refuses display strings that could break the page or a printf
#     format, and duplicate fleet-view headings
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PT="$ROOT/bin/po-theme.sh"
TEMPLATE="$ROOT/.agents/skills/bearings/assets/board-template.html"
PIN=$(tr -d '[:space:]' < "$ROOT/docs/pixeloven/upstream-pin" 2>/dev/null || true)
TMP_ROOT=$(fm_test_tmproot po-theme-surfaces)
fm_git_identity fmtest fmtest@example.invalid

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

USER_SKILLS='afk ahoy bearings lavish-url quiet stow updatefirstmate'

# new_code <name>: a throwaway code root carrying this tree's theme scripts,
# themes, design systems, the board template, and stub user-invocable skills,
# because apply writes alias skills under the code root of the script it runs.
new_code() {
  local code="$TMP_ROOT/$1/code" s
  mkdir -p "$code/bin" "$code/.agents/skills"
  cp "$PT" "$ROOT/bin/po-theme-lib.sh" "$ROOT/bin/po-design-lib.sh" "$code/bin/"
  cp -R "$ROOT/.agents/skills/po-theme" "$ROOT/.agents/skills/bearings" "$code/.agents/skills/"
  for s in $USER_SKILLS; do
    [ -f "$code/.agents/skills/$s/SKILL.md" ] && continue
    mkdir -p "$code/.agents/skills/$s"
    printf -- '---\nname: %s\nuser-invocable: true\n---\n' "$s" > "$code/.agents/skills/$s/SKILL.md"
  done
  git init -q -b main "$code"
  git -C "$code" add -A
  git -C "$code" commit -q -m seed
  printf '%s\n' "$code"
}

new_home() {  # <name> [theme] [design]
  local home="$TMP_ROOT/$1/home"
  mkdir -p "$home/config/po-themes/assets" "$home/data" "$home/state"
  [ -z "${2:-}" ] || printf '%s\n' "$2" > "$home/config/po-theme"
  [ -z "${3:-}" ] || printf '%s\n' "$3" > "$home/config/po-design"
  printf '%s\n' "$home"
}

render() {  # <code> <home>: the board template rendered in that home
  FM_HOME="$2" "$1/bin/po-theme.sh" render-board "$1/.agents/skills/bearings/assets/board-template.html"
}

no_captain() {  # <file> <what>: the page names no captain, as a word in any case
  if LC_ALL=C grep -niw 'captain' "$1" >/dev/null; then
    fail "$2 still says captain: $(LC_ALL=C grep -niw 'captain' "$1" | head -n 3)"
  fi
  if grep -qF "Captain's Call" "$1"; then fail "$2 still says Captain's Call"; fi
}

test_board_nautical_byte_identical() {
  local code home
  code=$(new_code board-nautical)
  home=$(new_home board-nautical-unset)
  render "$code" "$home" | cmp -s - "$TEMPLATE" || fail "the board changed in a home with no theme selection"
  home=$(new_home board-nautical-explicit nautical)
  render "$code" "$home" | cmp -s - "$TEMPLATE" || fail "the board changed under the nautical theme"
  home=$(new_home board-nautical-firstmate nautical firstmate)
  FM_HOME="$home" "$code/bin/po-theme.sh" apply >/dev/null 2>&1 || fail "apply failed under nautical and firstmate"
  render "$code" "$home" | cmp -s - "$TEMPLATE" || fail "the board changed under the Firstmate Default design system"
  pass "the nautical board is byte-identical to the template, also under the Firstmate Default"
}

# A lavish-axi stub shaped like the real one (see tests/fm-bearings-board.test.sh):
# the build proves a live session, and the listener's poll returns the prompt
# row the test writes to $FM_HOME/answer-row once the board's answer is captured.
make_board_home() {  # <name>
  local home fakebin
  home=$(new_home "$1" operator)
  fm_test_track_procevent_home "$home" "$home/procevent-claims"
  mkdir -p "$home/lavish-state"
  fakebin=$(fm_fakebin "$home")
  cat > "$fakebin/lavish-axi" <<'SH'
#!/usr/bin/env bash
case "${1-}" in
  --version) printf '0.1.80\n' ;;
  '')
    printf 'sessions[1]{file,status,url,pending_prompts}:\n'
    [ ! -s "$FM_HOME/lavish-open" ] \
      || printf '  %s,open,"http://127.0.0.1:4387/session/0123456789abcdef",0\n' "$(cat "$FM_HOME/lavish-open")"
    ;;
  poll)
    while [ ! -s "$FM_HOME/answer-row" ] && [ "$SECONDS" -lt 60 ]; do sleep 0.2; done
    [ -s "$FM_HOME/answer-row" ] || exit 75
    printf 'session:\n  status: feedback\n  session_ended: false\nprompts[1]{uid,prompt,selector,tag,text}:\n'
    cat "$FM_HOME/answer-row"
    rm -f "$FM_HOME/answer-row"
    ;;
  *)
    real=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
    printf '%s\n' "$real" > "$FM_HOME/lavish-open"
    mkdir -p "$LAVISH_AXI_STATE_DIR"
    jq -n --arg file "$real" \
      '{sessions:{"0123456789abcdef":{file:$file,url:"http://127.0.0.1:4387/session/0123456789abcdef"}}}' \
      > "$LAVISH_AXI_STATE_DIR/state.json"
    printf 'session:\n  status: opened\n'
    ;;
esac
exit 0
SH
  chmod +x "$fakebin/lavish-axi"
  printf '%s\n' "$home"
}

in_home() {  # <home> <command...>
  local home=$1
  shift
  PATH="$home/fakebin:$PATH" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROCEVENT_CLAIM_ROOT="$home/procevent-claims" LAVISH_AXI_STATE_DIR="$home/lavish-state" \
    "$@"
}

# answer_capture <board.html> <question-key> <option>: submit that card's form
# under a DOM shim and print what the board queued to Lavish, as one prompt row
# in lavish-axi's poll shape.
answer_capture() {
  node --input-type=module - "$1" "$2" "$3" <<'JS'
import { readFileSync } from "node:fs";
const [file, key, option] = process.argv.slice(2);
const html = readFileSync(file, "utf8");
const forms = [];
class Node {
  constructor(tag) {
    Object.assign(this, { tagName: tag, className: "", children: [], attributes: {}, listeners: {},
      _text: "", hidden: false, disabled: false, innerHTML: "", parentNode: null, type: "", value: "",
      checked: false, name: "", style: {} });
    const set = () => new Set(this.className.split(/\s+/).filter(Boolean));
    this.classList = {
      add: (c) => { const s = set(); s.add(c); this.className = [...s].join(" "); },
      remove: (c) => { const s = set(); s.delete(c); this.className = [...s].join(" "); },
      contains: (c) => set().has(c),
      toggle: (c, force) => { const s = set(); const on = force ?? !s.has(c); if (on) s.add(c); else s.delete(c); this.className = [...s].join(" "); return on; },
    };
  }
  get textContent() { return this.children.length ? this.children.map((c) => c.textContent).join("") : this._text; }
  set textContent(v) { this._text = String(v); this.children = []; }
  appendChild(n) { n.parentNode = this; this.children.push(n); return n; }
  setAttribute(k, v) { this.attributes[k] = v; }
  addEventListener(ev, fn) { (this.listeners[ev] ||= []).push(fn); }
  walk(fn) { for (const c of this.children) { fn(c); c.walk(fn); } }
  querySelectorAll(sel) {
    const want = sel.replace(/^\./, "").replace(/:checked$/, ""), out = [];
    this.walk((c) => { if (c.className.split(/\s+/).includes(want) && (!sel.endsWith(":checked") || c.checked)) out.push(c); });
    return out;
  }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
}
const byId = new Map();
const data = new Node("script");
data.textContent = html.split('<script id="bearings-data" type="application/json">')[1].split("</script>")[0];
byId.set("bearings-data", data);
globalThis.document = {
  createElement: (tag) => { const n = new Node(tag); if (tag === "form") forms.push(n); return n; },
  getElementById: (id) => { if (!byId.has(id)) { const n = new Node("div"); new Node("div").appendChild(n); byId.set(id, n); } return byId.get(id); },
  querySelector: (sel) => { const id = "sel:" + sel; if (!byId.has(id)) byId.set(id, new Node("div")); return byId.get(id); },
};
const queued = [];
globalThis.window = { lavish: { queuePrompt: (text, opts) => queued.push({ text, opts }) } };
globalThis.setTimeout = () => 0;
globalThis.FormData = class {
  constructor(form) { this.form = form; }
  get(name) {
    let v = null;
    this.form.walk((c) => { if (c.name === name && (c.type !== "radio" || c.checked)) v = c.value; });
    return v;
  }
};
const script = html.slice(html.indexOf("<script>") + "<script>".length, html.lastIndexOf("</script>"));
new Function(script)();
const form = forms.find((f) => f.attributes["data-lavish-question"] === key);
if (!form) { console.error("no card for " + key); process.exit(1); }
form.walk((c) => { if (c.type === "radio" && c.value === option) c.checked = true; });
for (const fn of form.listeners.submit || []) fn({ preventDefault() {} });
if (queued.length !== 1) { console.error("expected one queued answer, got " + queued.length); process.exit(1); }
const { text, opts } = queued[0];
const prompt = text + "\n\nContext data:\n" + JSON.stringify(opts.data, null, 2);
const q = (s) => '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"';
process.stdout.write(`  "2",${q(prompt)},"form",${opts.tag},${q(opts.text)}\n`);
console.error(text);
JS
}

test_operator_board() {
  local home data board origin=s5-board-review key=operator-choice hold out show sid row
  command -v node >/dev/null 2>&1 || { echo "skip: node not found; operator board not exercised"; return 0; }
  command -v tasks-axi >/dev/null 2>&1 || { echo "skip: tasks-axi not found; operator board not exercised"; return 0; }
  home=$(make_board_home board-operator)
  hold="$origin-decision-$key"
  board="$home/.lavish/bearings-board.html"
  render "$ROOT" "$home" > "$TMP_ROOT/operator-rendered.html"
  no_captain "$TMP_ROOT/operator-rendered.html" "the rendered operator board"
  assert_grep "Operator's Call" "$TMP_ROOT/operator-rendered.html" "the rendered operator board does not name the operator's call"

  fm_test_tasks_toml "$home/.tasks.toml"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  fm_write_meta "$home/state/$origin.meta" "project=$home/projects/sample" "kind=scout"
  in_home "$home" "$ROOT/bin/fm-decision-hold.sh" hold "$origin" "$key" \
    --title "Choose the theme proof" --reason "operator choice pending" --repo sample >/dev/null \
    || fail "could not create the held call"
  data="$home/payload.json"
  jq -n --arg key "$hold" '{
    schema: "fm-bearings-board.v1", home: "test-home", generated: "2026-11-18T00:00Z", prs_live: false,
    captains_call: [{ key: $key, type: "decision", repo: "sample", title: "Choose the theme proof",
      about: "S5", decide: "Adopt it?", options: [{ value: "yes", label: "Adopt" }, { value: "no", label: "Keep" }],
      allow_freeform: false }],
    underway: [], landed: [], charted: [], charted_more: 0 }' > "$data"
  out=$(in_home "$home" "$ROOT/bin/fm-bearings-board.sh" build "$data" 2>&1) || fail "the operator board build failed: $out"
  no_captain "$board" "the built operator board"
  out=$(node "$ROOT/tests/assets/board-render-harness.mjs" "$board") || fail "the built operator board does not render"
  assert_equals "" "$(printf '%s' "$out" | jq -r .error)" "the built operator board rendered its error notice"
  assert_equals "1" "$(printf '%s' "$out" | jq -r '.captains_call | length')" "the built operator board lost its call card"

  row=$(answer_capture "$board" "$hold" yes 2> "$TMP_ROOT/queued-text") || fail "the themed board queued no answer: $(cat "$TMP_ROOT/queued-text")"
  assert_contains "$(cat "$TMP_ROOT/queued-text")" "Operator's Call answer - Choose the theme proof: yes" "the queued answer is not in the theme's words"
  assert_contains "$row" 'fm-bearings-answer.v1' "the themed board's answer does not carry its versioned context"
  printf '%s\n' "$row" > "$home/answer-row.tmp" && mv "$home/answer-row.tmp" "$home/answer-row"
  for _ in $(seq 1 150); do
    show=$(cd "$home" && tasks-axi show "$hold" --full) || fail "the held call disappeared"
    case "$show" in *"state: done"*) break ;; esac
    sleep 0.2
  done
  assert_contains "$show" "state: done" "an answer from the themed board did not close the held call"
  assert_contains "$show" "Resolution mode: answered" "the held call was not closed through the keyed-answer intake"
  sid=$(in_home "$home" "$ROOT/bin/fm-procevent-lavish.sh" source-id "$board")
  [ -n "$sid" ] || fail "the board has no source id"
  pass "the operator board names no captain and an answer from it closes a held call through fm-bearings-answer.v1"
}

test_board_icons() {
  local code home out
  code=$(new_code board-icons)
  home=$(new_home board-icons iconic)
  sed -e 's/^name = .*/name = "iconic"/' "$ROOT/.agents/skills/po-theme/themes/operator.theme" > "$home/config/po-themes/iconic.theme"
  printf 'icon.brand = "po-crosshair.svg"\nicon.underway = "po-radio.svg"\n' >> "$home/config/po-themes/iconic.theme"
  printf '<circle cx="12" cy="12" r="10"/>\n<line x1="22" y1="12" x2="18" y2="12"/>\n' > "$home/config/po-themes/assets/po-crosshair.svg"
  printf '<path d="M4.9 19.1C1 15.2 1 8.8 4.9 4.9"/>\n' > "$home/config/po-themes/assets/po-radio.svg"
  out=$(render "$code" "$home") || fail "render-board failed with theme icons"
  assert_contains "$out" '<circle cx="12" cy="12" r="10"/> <line x1="22" y1="12" x2="18" y2="12"/>' "the brand icon was not drawn"
  assert_not_contains "$out" '<path d="M12 6v16"/>' "the anchor stayed in the brand mark"
  assert_contains "$out" 'stroke-linejoin="round"><path d="M4.9 19.1C1 15.2 1 8.8 4.9 4.9"/></svg>' "the Underway icon was not drawn inside its svg"
  assert_not_contains "$out" 'M19.38 20A11.6' "the ship stayed on the Underway heading"
  # An invalid asset never reaches the cache, and a cached copy that no longer
  # validates is refused at render time; either way the ship stays.
  cp "$home/config/po-themes/assets/po-radio.svg" "$TMP_ROOT/po-radio.svg"
  printf '<script>alert(1)</script>\n' > "$home/config/po-themes/assets/po-radio.svg"
  FM_HOME="$home" "$code/bin/po-theme.sh" refresh >/dev/null 2>&1 || fail "refresh failed with an invalid icon"
  out=$(render "$code" "$home" 2>/dev/null) || fail "render-board failed with an invalid icon"
  assert_contains "$out" 'M19.38 20A11.6' "an invalid Underway icon replaced the ship"
  cp "$TMP_ROOT/po-radio.svg" "$home/config/po-themes/assets/po-radio.svg"
  FM_HOME="$home" "$code/bin/po-theme.sh" refresh >/dev/null 2>&1 || fail "refresh failed with a valid icon"
  printf '<script>alert(1)</script>\n' > "$home/state/po-theme/assets/po-radio.svg"
  out=$(render "$code" "$home" 2> "$TMP_ROOT/icon.err") || fail "render-board failed with a tampered cached icon"
  assert_contains "$out" 'M19.38 20A11.6' "a tampered cached Underway icon replaced the ship"
  assert_grep 'icon.underway: icon po-radio.svg is missing or invalid' "$TMP_ROOT/icon.err" "render-board did not warn about the tampered icon"
  pass "theme icons replace the board's anchor and ship, and an invalid one keeps nautical's"
}

# with_design <template> <css>: the template with the stylesheet injected as one
# style element right after the template's own closing style tag.
with_design() {
  awk -v css="$2" '{ print } $0 == "</style>" && !done { print "<style id=\"po-design\">"; while ((getline l < css) > 0) print l; print "</style>"; done = 1 }' "$1"
}

test_board_design_injection() {
  local code home
  code=$(new_code board-design)
  home=$(new_home board-design nautical pixeloven)
  FM_HOME="$home" "$code/bin/po-theme.sh" apply >/dev/null 2>&1 || fail "apply failed under pixeloven"
  FM_HOME="$home" "$code/bin/po-theme.sh" ds-css > "$TMP_ROOT/pixeloven.css" || fail "ds-css failed"
  with_design "$TEMPLATE" "$TMP_ROOT/pixeloven.css" > "$TMP_ROOT/board-design.expected"
  render "$code" "$home" | cmp -s - "$TMP_ROOT/board-design.expected" \
    || fail "the board did not carry exactly the applied design system after its own styles"
  printf 'operator\n' > "$home/config/po-theme"
  FM_HOME="$home" "$code/bin/po-theme.sh" apply >/dev/null 2>&1 || fail "apply failed under operator and pixeloven"
  render "$code" "$home" > "$TMP_ROOT/board-design.operator"
  assert_grep '<style id="po-design">' "$TMP_ROOT/board-design.operator" "the operator board lost the design system"
  assert_grep "Operator's Call" "$TMP_ROOT/board-design.operator" "the design system dropped the theme's words"
  pass "an applied design system is injected after the template's tokens under any theme"
}

# upstream_bin <script>: this tree's bin/ with <script> at the upstream pin, so
# upstream's version runs beside the same sibling libraries. Empty when the pin
# commit is not in this clone.
upstream_bin() {
  local dir="$TMP_ROOT/upstream-$1/bin"
  [ -d "$dir" ] && { printf '%s\n' "$dir"; return 0; }
  [ -n "$PIN" ] && git -C "$ROOT" cat-file -e "$PIN:bin/$1" 2>/dev/null || return 0
  mkdir -p "${dir%/bin}"
  cp -R "$ROOT/bin" "$dir"
  git -C "$ROOT" show "$PIN:bin/$1" > "$dir/$1"
  printf '%s\n' "$dir"
}

fleet_view() {  # <bin> <home>
  local fb
  fb=$(fm_fakebin "$2")
  fm_fake_exit0 "$fb" no-mistakes
  PATH="$fb:$PATH" FM_HOME="$2" FM_STATE_OVERRIDE="$2/state" FM_DATA_OVERRIDE="$2/data" "$1/fm-fleet-view.sh" | sed "s|$2|<home>|g"
}

test_fleet_view_golden() {
  local naut op up out
  naut=$(new_home fleet-nautical)
  op=$(new_home fleet-operator operator)
  out=$(fleet_view "$ROOT/bin" "$naut") || fail "the nautical fleet view failed"
  up=$(upstream_bin fm-fleet-view.sh)
  if [ -n "$up" ]; then
    assert_equals "$(fleet_view "$up" "$naut")" "$out" "the nautical fleet view differs from upstream's at the pin"
  else
    printf 'note: upstream pin %s is not in this clone; nautical fleet view compared to the golden headings only\n' "${PIN:-?}"
  fi
  assert_equals $'# Fleet View\n## Under Way\n## Queued\n## Done\n## Secondmates' "$(printf '%s\n' "$out" | grep '^#')" \
    "the nautical fleet view headings are not upstream's"
  assert_equals "$(printf '%s\n' "$out" | sed 's/^# Fleet View$/# Task Force View/; s/^## Secondmates$/## Navigators/')" \
    "$(fleet_view "$ROOT/bin" "$op")" "the operator fleet view differs from the nautical one in more than its headings"
  pass "the fleet view is upstream's under nautical and themes only its headings under operator"
}

inbox() {  # <bin> <home> <args...>: output normalized for note ids and times
  local bin=$1 home=$2
  shift 2
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" FM_CONFIG_OVERRIDE="$home/config" \
    "$bin/fm-inbox.sh" "$@" 2>&1 | grep -v ': Is a directory$' \
    | sed -E "s|$home|<home>|g; s/^(queued|replay) .*/\\1 <id>/; s/^time .*/time <time>/; s/note [^ ]+ is saved at [^ ]+/note <id> is saved at <path>/"
}

inbox_session() {  # <bin> <home>: note, status, a status with no workers, and an unannounced note
  local bin=$1 home=$2
  inbox "$bin" "$home" note "check the theme"
  inbox "$bin" "$home" status
  mkdir -p "$home/state"
  rm -rf "$home/state/.wake-queue"
  mkdir "$home/state/.wake-queue"
  inbox "$bin" "$home" note "a note whose wake fails"
  rmdir "$home/state/.wake-queue"
}

test_inbox_golden() {
  local naut op up out want
  naut=$(new_home inbox-nautical)
  op=$(new_home inbox-operator operator)
  out=$(inbox_session "$ROOT/bin" "$naut")
  up=$(upstream_bin fm-inbox.sh)
  if [ -n "$up" ]; then
    assert_equals "$(inbox_session "$up" "$(new_home inbox-upstream)" | sed 's|inbox-upstream|inbox-nautical|g')" "$out" \
      "the nautical inbox output differs from upstream's at the pin"
  else
    printf 'note: upstream pin %s is not in this clone; nautical inbox compared to the golden lines only\n' "${PIN:-?}"
  fi
  assert_contains "$out" "  firstmate will pick this up at its next check." "the nautical note is not upstream's"
  assert_contains "$out" "=== firstmate status (read-only, no wake sent) ===" "the nautical status heading is not upstream's"
  assert_contains "$out" "inbox    1 note(s) waiting for firstmate" "the nautical waiting line is not upstream's"
  assert_contains "$out" "(no workers on deck)" "the nautical idle line is not upstream's"
  assert_contains "$out" "but firstmate was NOT woken" "the nautical unannounced note is not upstream's"
  want=$(printf '%s\n' "$out" | sed 's/firstmate will pick/spotter will pick/; s/=== firstmate status/=== spotter status/; s/waiting for firstmate/waiting for spotter/; s/(no workers on deck)/(no specialists active)/; s/but firstmate was NOT woken/but spotter was NOT woken/g')
  assert_equals "$want" "$(inbox_session "$ROOT/bin" "$op" | sed 's|inbox-operator|inbox-nautical|g')" \
    "the operator inbox output differs from the nautical one in more than the themed words"
  pass "the inbox note and status output is upstream's under nautical and themes only its words under operator"
}

# session_prompt <home>: the system text the voice relay sends a new model
# session from that home, with the Bedrock client faked out.
session_prompt() {
  python3 - "$ROOT/bin" "$1" <<'PY'
import asyncio, importlib.util, pathlib, sys, types
bin_dir, home = sys.argv[1], sys.argv[2]
sys.path.insert(0, bin_dir)
fake = types.ModuleType("aws_sdk_bedrock_runtime")
client, config = types.ModuleType("aws_sdk_bedrock_runtime.client"), types.ModuleType("aws_sdk_bedrock_runtime.config")
class Client:
    def __init__(self, config): pass
    async def invoke_model_with_bidirectional_stream(self, _): return object()
class Config:
    @staticmethod
    async def resolve(**_): return None
client.AsyncBedrockRuntimeClient, client.InvokeModelWithBidirectionalStreamOperationInput = Client, lambda **_: None
config.AsyncBedrockRuntimeConfig = Config
sys.modules.update({"aws_sdk_bedrock_runtime": fake, "aws_sdk_bedrock_runtime.client": client, "aws_sdk_bedrock_runtime.config": config})
spec = importlib.util.spec_from_file_location("relay", str(pathlib.Path(bin_dir) / "fm-voice-relay.py"))
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)
class Creds:
    async def get(self): return {}
session = relay.Session(relay.parse_args(["--serve", "--home", home]), None, Creds())
sent = []
async def record(event): sent.append(event)
async def idle(): return None
session._send, session._read_model = record, idle
async def start():
    await session.start()
    await asyncio.sleep(0)
asyncio.run(start())
texts = [e["textInput"]["content"] for e in sent if "textInput" in e]
assert len(texts) == 1, texts
sys.stdout.write(texts[0] + "\n--\n" + relay.SYSTEM_PROMPT + "\n")
PY
}

test_voice_prompt() {
  local naut op out line
  command -v python3 >/dev/null 2>&1 || { echo "skip: python3 not found; voice prompt not exercised"; return 0; }
  naut=$(new_home voice-nautical)
  op=$(new_home voice-operator operator)
  out=$(session_prompt "$naut") || fail "the voice session did not start in a nautical home: $out"
  assert_equals "${out#*$'\n--\n'}" "${out%%$'\n--\n'*}" "the nautical voice prompt is not upstream's"
  line=$(FM_HOME="$op" "$PT" voice-line) || fail "voice-line failed under operator"
  assert_contains "$line" 'this home calls the captain "operator", firstmate "spotter"' "the voice line does not carry the theme's words"
  out=$(session_prompt "$op") || fail "the voice session did not start in an operator home: $out"
  assert_equals "${out#*$'\n--\n'}"$'\n\n'"$line" "${out%%$'\n--\n'*}" "the operator voice prompt is not upstream's plus one vocabulary paragraph"
  assert_equals "" "$(FM_HOME="$naut" "$PT" voice-line)" "voice-line printed under nautical"
  pass "the voice prompt is upstream's under nautical and gains one vocabulary paragraph under a theme"
}

test_alias_descriptions() {
  local code home out
  code=$(new_code aliases)
  home=$(new_home aliases operator)
  out=$(FM_HOME="$home" "$code/bin/po-theme.sh" apply 2>&1) || fail "operator apply failed: $out"
  assert_grep 'description: Pick up where you left off: the task force digest in chat, a file, or a live board. Alias of /bearings in the operator theme. Use when the user invokes /sitrep.' \
    "$code/.agents/skills/sitrep/SKILL.md" "the /sitrep description is not in the theme's words"
  assert_grep 'description: Save what the spotter learned this session and file its open work. Alias of /stow in the operator theme. Use when the user invokes /flush.' \
    "$code/.agents/skills/flush/SKILL.md" "the /flush description is not in the theme's words"
  assert_grep 'description: Update this operator home and its navigators to the latest version. Alias of /updatefirstmate' \
    "$code/.agents/skills/updateoperator/SKILL.md" "the /updateoperator description is not in the theme's words"
  out=$(FM_HOME="$home" "$code/bin/po-theme.sh" verify 2>&1) || fail "verify failed after apply: $out"
  sed -i.bak 's/task force digest/fleet digest/' "$code/.agents/skills/sitrep/SKILL.md" && rm -f "$code/.agents/skills/sitrep/SKILL.md.bak"
  out=$(FM_HOME="$home" "$code/bin/po-theme.sh" verify 2>&1) && fail "verify passed a hand-edited alias"
  assert_contains "$out" "drift: alias /sitrep for /bearings is stale or hand-edited; run apply" "verify did not name the edited alias"
  pass "alias skills describe their command in the theme's words, and verify reports a hand-edited one"
}

test_registry_counts_repeated_hooks() {
  local repo out
  repo="$TMP_ROOT/registry/repo"
  mkdir -p "$repo/bin" "$repo/.agents/skills/po-theme"
  cp "$PT" "$ROOT/bin/po-theme-lib.sh" "$ROOT/bin/po-design-lib.sh" "$repo/bin/"
  cp -R "$ROOT/.agents/skills/po-theme/themes" "$ROOT/.agents/skills/po-theme/designs" "$repo/.agents/skills/po-theme/"
  printf 'say firstmate\nsay firstmate\nsay firstmate\n' > "$repo/bin/x.sh"
  git init -q -b main "$repo"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m upstream
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'str.x\tT\tbin/x.sh\tupstream\tsay "$who"\tsay firstmate\n' > "$repo/.agents/skills/po-theme/surfaces.tsv"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'str.x\tT\tbin/x.sh\tupstream\tsay "$who"\tsay firstmate\n' >> "$repo/.agents/skills/po-theme/surfaces.tsv"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'say "$who"\nsay "$who"\nsay firstmate\n' > "$repo/bin/x.sh"
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1) || fail "the registry check refused a hook line registered twice: $out"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'say "$who"\nsay "$who"\nsay "$who"\n' > "$repo/bin/x.sh"
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1) && fail "the registry check accepted a hook line more often than registered"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  assert_contains "$out" 'A9: bin/x.sh: hook line appears more times than it is registered: say "$who"' "the registry check did not name the extra hook line"
  pass "the registry check accepts a hook line as often as rows register it, and no more"
}

test_string_validation() {
  local home out
  home=$(new_home strings)
  derive_theme() {  # <name> <line>
    sed -e "s/^name = .*/name = \"$1\"/" "$ROOT/.agents/skills/po-theme/themes/operator.theme" > "$home/config/po-themes/$1.theme"
    printf '%s\n' "$2" >> "$home/config/po-themes/$1.theme"
  }
  derive_theme pct 'str.inbox.agent = "100% spotter"'
  out=$(FM_HOME="$home" "$PT" validate pct 2>&1) && fail "validate accepted a % in an inbox string"
  assert_contains "$out" "str.inbox.agent: '100% spotter' contains % or &" "validate did not name the % in an inbox string"
  derive_theme cmt 'str.board.user = "op */ x /* op"'
  out=$(FM_HOME="$home" "$PT" validate cmt 2>&1) && fail "validate accepted a board string that can close a comment"
  assert_contains "$out" "str.board.user: 'op */ x /* op' must be at most 48 letters" "validate did not name the unsafe board string"
  derive_theme dup 'str.fleet.underway = "Navigators"'
  out=$(FM_HOME="$home" "$PT" validate dup 2>&1) && fail "validate accepted two fleet-view headings with one name"
  assert_contains "$out" "share the section name 'Navigators'" "validate did not name the repeated fleet-view heading"
  pass "validation refuses unsafe board and inbox strings and repeated fleet-view headings"
}

test_board_nautical_byte_identical
test_operator_board
test_board_icons
test_board_design_injection
test_fleet_view_golden
test_inbox_golden
test_voice_prompt
test_alias_descriptions
test_registry_counts_repeated_hooks
test_string_validation
