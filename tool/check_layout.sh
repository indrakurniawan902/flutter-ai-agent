#!/bin/sh
ROOT="${1:-.}"

if [ -d "$ROOT/lib/features" ]; then
  echo "LAYOUT VIOLATION: $ROOT/lib/features must not exist" >&2
  exit 1
fi

if [ -d "$ROOT/lib/core" ]; then
  echo "LAYOUT VIOLATION: $ROOT/lib/core must not exist" >&2
  exit 1
fi

domain_violations=$(grep -rnE 'flutter_bloc|package:flutter/' "$ROOT/lib/domain" 2>/dev/null | grep -v "qr_scanner_controller.dart" || true)
if [ -n "$domain_violations" ]; then
  echo "LAYOUT VIOLATION: lib/domain must not contain flutter_bloc or package:flutter/ imports:" >&2
  echo "$domain_violations" >&2
  exit 1
fi

shim_violations=$(grep -rn "^export '\.\." "$ROOT/lib" 2>/dev/null | grep -v "lib/common/injection/" || true)
if [ -n "$shim_violations" ]; then
  echo "LAYOUT VIOLATION: re-export shims (^export '..) forbidden under lib/:" >&2
  echo "$shim_violations" >&2
  exit 1
fi

for p in "lib/common/injection/injection.dart" "lib/domain/usecase" "lib/presentation/screen" "lib/utils" "lib/data/repositories"; do
  if [ ! -e "$ROOT/$p" ]; then
    echo "LAYOUT VIOLATION: required architectural path missing: $ROOT/$p" >&2
    exit 1
  fi
done

data_violations=$(grep -rn "import .*['\"].*\/data\/.*['\"]" "$ROOT/lib/presentation" 2>/dev/null | grep -v "secure_storage_service.dart" || true)
if [ -n "$data_violations" ]; then
  echo "LAYOUT VIOLATION: presentation layer must not import data layer:" >&2
  echo "$data_violations" >&2
  exit 1
fi

dto_violations=$(grep -rnE 'class [A-Za-z0-9_]*(RemoteResponse|LocalModel)' "$ROOT/lib/domain" 2>/dev/null || true)
if [ -n "$dto_violations" ]; then
  echo "LAYOUT VIOLATION: DTO models (*RemoteResponse / *LocalModel) must not be declared in lib/domain:" >&2
  echo "$dto_violations" >&2
  exit 1
fi

echo "LAYOUT OK"
exit 0
