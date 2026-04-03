#!/usr/bin/env bash
# @version: 1.0.0
# Scans .cs files for dangerous .NET APIs: unsafe deserialization,
# Process.Start, Shell(), and other common vulnerability patterns.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.cs ]] && exit 0

if grep -qiE '(Process\.Start|Shell\(|BinaryFormatter|JavaScriptSerializer|XmlSerializer.*UnsafeDeserializ|ObjectStateFormatter|LosFormatter|NetDataContractSerializer)' "$file"; then
  echo "WARNING: potentially unsafe .NET API in $file — verify intent"
fi
