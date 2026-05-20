#!/usr/bin/env bash
# @version: 1.0.0
# Detects the project's build command, runs it once, classifies output.
# Reused as the BuildFailed event subscriber.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

project_root="$(dirname "$CORTEX_ROOT")"
cmd=""
if [[ -f "$project_root/package.json" ]]; then
  cmd="npm run build --silent"
elif compgen -G "$project_root/*.csproj" >/dev/null || compgen -G "$project_root/*.sln" >/dev/null; then
  cmd="dotnet build --nologo -v quiet"
elif [[ -f "$project_root/Cargo.toml" ]]; then
  cmd="cargo build --quiet"
elif [[ -f "$project_root/go.mod" ]]; then
  cmd="go build ./..."
elif [[ -f "$project_root/pom.xml" ]]; then
  cmd="mvn -q -DskipTests compile"
fi

[[ -z "$cmd" ]] && { jq -nc '{kind:"build", status:"SKIP", reason:"no build manifest"}'; exit 0; }

log="$CORTEX_TEMP/build-$(date +%s).log"
( cd "$project_root" && timeout 60 bash -c "$cmd" ) > "$log" 2>&1
rc=$?

errors=$(grep -iE '(error|warning):' "$log" 2>/dev/null | head -n 20 | jq -R . | jq -sc .)
[[ -z "$errors" ]] && errors="[]"

jq -nc --arg cmd "$cmd" --argjson rc "$rc" --argjson errors "$errors" \
  '{kind:"build", command:$cmd, exit:$rc, status:(if $rc==0 then "OK" else "FAIL" end), errors:$errors}'
