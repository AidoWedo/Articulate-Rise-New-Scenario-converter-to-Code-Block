#!/bin/bash
# macOS: Bash plus built-in unzip, zip, sed, grep, find and mktemp.
# Usage: bash convert-rise-scenario-mac.sh INPUT.zip OUTPUT.zip
set -euo pipefail

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[ "$#" -eq 2 ] || fail "Usage: bash $0 INPUT.zip OUTPUT.zip"
for tool in unzip zip sed grep find mktemp cp ln; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required tool not found: $tool"
done

input_arg=$1
output_arg=$2
[ -f "$input_arg" ] || fail "Input ZIP not found: $input_arg"
input_dir=$(cd -- "$(dirname -- "$input_arg")" && pwd -P)
input_path="$input_dir/$(basename -- "$input_arg")"
output_dir=$(cd -- "$(dirname -- "$output_arg")" && pwd -P) || fail 'Output directory must exist.'
output_path="$output_dir/$(basename -- "$output_arg")"
[ ! -e "$output_path" ] && [ ! -L "$output_path" ] || fail "Output already exists: $output_path"

# Work only in a new private folder beside the output ZIP.
work=$(mktemp -d "$output_dir/.rise-scenario.XXXXXXXX")
cleanup() {
  case "$work" in
    "$output_dir"/.rise-scenario.*) [ ! -L "$work" ] && rm -rf -- "$work" ;;
  esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Reject paths that could escape the temporary extraction directory.
unzip -Z1 "$input_path" > "$work/entries.txt"
if LC_ALL=C grep -Eq '(^/|(^|/)\.\.(/|$)|\\|:)' "$work/entries.txt"; then
  fail 'ZIP contains an unexpected or unsafe path.'
fi
unzip -q "$input_path" -d "$work/extracted"
if [ -n "$(find "$work/extracted" -type l -print)" ]; then
  fail 'ZIP contains symbolic links; expected regular exported files.'
fi

if [ -f "$work/extracted/content/index.html" ]; then
  root="$work/extracted/content"
elif [ -f "$work/extracted/index.html" ]; then
  root="$work/extracted"
else
  fail 'Expected content/index.html or index.html in the ZIP.'
fi
[ -f "$root/runtime-data.js" ] || fail 'Missing runtime-data.js. Use the Rise web export ZIP.'
LC_ALL=C grep -Eiq '</head>' "$root/index.html" || fail 'index.html has no closing head tag.'

if ! grep -q 'id="rise-scenario-embed"' "$root/index.html"; then
  # BSD sed (included with macOS), using | as the delimiter.
  # Insert the same embed styling used by the PowerShell version.
  LC_ALL=C sed 's|</[hH][eE][aA][dD]>|<style id="rise-scenario-embed">.one-page-lesson-header { display: none !important; } html, body { margin: 0; padding: 0; }</style></head>|' \
    "$root/index.html" > "$work/index.html"
  cp "$work/index.html" "$root/index.html"
fi

# Zip the folder contents so index.html is at the archive root.
(cd "$root" && zip -q -r "$work/result.zip" .)
unzip -tq "$work/result.zip" >/dev/null
unzip -Z1 "$work/result.zip" > "$work/result-entries.txt"
grep -qx 'index.html' "$work/result-entries.txt" || fail 'Output index.html is not at the ZIP root.'

# Publish without overwriting a file created since the initial check.
ln "$work/result.zip" "$output_path" || fail "Could not create output: $output_path"
printf 'Created: %s\n' "$output_path"
printf 'Upload using Rise: All Blocks > Code > Upload project.\n'
printf 'Leave completion requirements off unless completion reporting is added separately.\n'
