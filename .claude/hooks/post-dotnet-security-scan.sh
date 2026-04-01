#!/usr/bin/env bash
# Scans .cs files for dangerous .NET APIs: unsafe deserialization,
# Process.Start, Shell(), and other common vulnerability patterns.

file=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')

[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.cs ]] && exit 0

if grep -qiE '(Process\.Start|Shell\(|BinaryFormatter|JavaScriptSerializer|XmlSerializer.*UnsafeDeserializ|ObjectStateFormatter|LosFormatter|NetDataContractSerializer)' "$file"; then
  echo "WARNING: potentially unsafe .NET API in $file — verify intent"
fi
