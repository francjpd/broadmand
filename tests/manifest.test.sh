#!/usr/bin/env bash
# tests/manifest.test.sh — validate the Herdr plugin manifest (herdr-plugin.toml).
#
# The repo has no TOML parser dependency, so this parses the manifest's small,
# constrained subset directly: top-level key/value pairs, [[actions]] and
# [[panes]] array-of-table sections, and the string/integer/string-array values
# the manifest uses. A broken manifest (malformed line, missing id, an
# unparseable value) fails the suite. It also checks that every command path the
# manifest names is a relative path that exists and is executable in the
# checkout, so a manifest that points at a missing or absolute script path fails
# CI.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap finish EXIT

manifest="$REPO_DIR/herdr-plugin.toml"

if [ ! -f "$manifest" ]; then
  _fail "herdr-plugin.toml is missing"
  exit 0
fi
_pass "herdr-plugin.toml is present"

# --- minimal TOML subset parser --------------------------------------------
# strip_comments removes a trailing '#' outside a double-quoted string.
strip_comments() {
  local s="$1" i c out="" in_str=0
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    if [ "$c" = '"' ]; then
      if [ "$in_str" = 0 ]; then in_str=1; else in_str=0; fi
      out="$out$c"
      continue
    fi
    if [ "$c" = '#' ] && [ "$in_str" = 0 ]; then
      break
    fi
    out="$out$c"
  done
  printf '%s' "$out"
}

# trim removes leading and trailing whitespace.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# parse_array "[\"bash\", \"scripts/run-all.sh\"]" prints one element per line.
parse_array() {
  local v="$1" elem
  v="${v#\[}"; v="${v%\]}"
  IFS=',' read -r -a elems <<< "$v"
  for elem in "${elems[@]}"; do
    elem="$(trim "$elem")"
    elem="${elem#\"}"; elem="${elem%\"}"
    [ -n "$elem" ] && printf '%s\n' "$elem"
  done
}

top_id=""; top_name=""; top_version=""; top_min=""
platforms=""; action_ids=""; pane_ids=""; command_paths=""
section=""
parse_fail=0

while IFS= read -r line; do
  line="$(strip_comments "$line")"
  line="$(trim "$line")"
  [ -n "$line" ] || continue

  case "$line" in
    \[\[*\]\])
      section="${line#\[\[}"; section="${section%\]\]}"
      case "$section" in
        actions|panes) ;;
        *)
          _fail "unexpected manifest section [[$section]]"
          parse_fail=1
          ;;
      esac
      continue
      ;;
  esac

  key="${line%%=*}"
  value="${line#*=}"
  key="$(trim "$key")"
  value="$(trim "$value")"

  if [ -z "$key" ] || [ "$key" = "$line" ]; then
    _fail "unparseable manifest line: $line"
    parse_fail=1
    continue
  fi

  # Validate the key token shape (letters, digits, underscore, hyphen).
  case "$key" in
    *[!A-Za-z0-9_-]*) _fail "invalid manifest key: $key"; parse_fail=1 ;;
  esac

  case "$section" in
    actions|panes)
      if [ "$key" = "id" ]; then
        id="${value#\"}"; id="${id%\"}"
        if [ "$section" = "actions" ]; then
          action_ids="$action_ids$id
"
        else
          pane_ids="$pane_ids$id
"
        fi
      elif [ "$key" = "command" ]; then
        if [ "${value#\[}" = "$value" ]; then
          _fail "manifest $section command is not an array: $value"
          parse_fail=1
        else
          while IFS= read -r arg; do
            [ -n "$arg" ] || continue
            case "$arg" in
              */*) command_paths="$command_paths$arg
" ;;
            esac
          done < <(parse_array "$value")
        fi
      fi
      ;;
    "")
      case "$key" in
        id) top_id="${value#\"}"; top_id="${top_id%\"}" ;;
        name) top_name="${value#\"}"; top_name="${top_name%\"}" ;;
        version) top_version="${value#\"}"; top_version="${top_version%\"}" ;;
        min_herdr_version) top_min="${value#\"}"; top_min="${top_min%\"}" ;;
        platforms)
          if [ "${value#\[}" != "$value" ]; then
            while IFS= read -r p; do
              [ -n "$p" ] && platforms="$platforms$p
"
            done < <(parse_array "$value")
          fi
          ;;
      esac
      ;;
  esac
done < "$manifest"

if [ "$parse_fail" -ne 0 ]; then
  exit 0
fi
_pass "herdr-plugin.toml parses as TOML"

# --- required metadata ------------------------------------------------------
assert_eq "manifest id" "broadmand" "$top_id"
if [ -n "$top_name" ]; then _pass "manifest name is present"; else _fail "manifest name is missing"; fi
if [ -n "$top_version" ]; then _pass "manifest version is present"; else _fail "manifest version is missing"; fi
if [ -n "$top_min" ]; then _pass "manifest min_herdr_version is present"; else _fail "manifest min_herdr_version is missing"; fi

assert_contains "manifest declares linux platform" "$platforms" "linux"
assert_contains "manifest declares macos platform" "$platforms" "macos"

# --- declared action and pane entrypoints -----------------------------------
assert_contains "manifest declares the broadcast action" "$action_ids" "broadcast"
assert_contains "manifest declares the cd-picker action" "$action_ids" "cd-picker"
assert_contains "manifest declares the broadcast pane" "$pane_ids" "broadcast"
assert_contains "manifest declares the cd-picker pane" "$pane_ids" "cd-picker"

# --- every command path resolves and is executable in the checkout ----------
paths_checked=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  paths_checked=$((paths_checked + 1))
  case "$path" in
    /*)
      _fail "manifest command uses an absolute path: $path"
      continue
      ;;
  esac
  if [ -f "$REPO_DIR/$path" ]; then
    _pass "manifest command path exists: $path"
  else
    _fail "manifest command path is missing: $path"
    continue
  fi
  if [ -x "$REPO_DIR/$path" ]; then
    _pass "manifest command path is executable: $path"
  else
    _fail "manifest command path is not executable: $path"
  fi
done <<< "$command_paths"

if [ "$paths_checked" -eq 0 ]; then
  _fail "manifest declares no command paths"
fi
