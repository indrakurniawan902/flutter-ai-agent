#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$SCRIPT_DIR/check_layout.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

setup_clean_tree() {
  mkdir -p "$1/lib/common/injection"
  touch "$1/lib/common/injection/injection.dart"
  mkdir -p "$1/lib/domain/usecase"
  mkdir -p "$1/lib/presentation/screen"
  mkdir -p "$1/lib/utils"
  mkdir -p "$1/lib/data/repositories"
}

setup_clean_tree "$TMP_DIR/clean"
out=$(sh "$CHECKER" "$TMP_DIR/clean" 2>&1)
status=$?
if [ $status -ne 0 ]; then
  echo "FAIL Test 1 (Clean tree): expected exit 0, got $status" >&2
  echo "$out" >&2
  exit 1
fi
echo "$out" | grep -q "LAYOUT OK" || {
  echo "FAIL Test 1 (Clean tree): expected 'LAYOUT OK' in output" >&2
  echo "$out" >&2
  exit 1
}

setup_clean_tree "$TMP_DIR/with_features"
mkdir -p "$TMP_DIR/with_features/lib/features"
touch "$TMP_DIR/with_features/lib/features/x"
out=$(sh "$CHECKER" "$TMP_DIR/with_features" 2>&1)
status=$?
if [ $status -eq 0 ]; then
  echo "FAIL Test 2 (Features violation): expected non-zero exit" >&2
  exit 1
fi
echo "$out" | grep -qi "features" || {
  echo "FAIL Test 2 (Features violation): expected output to contain 'features'" >&2
  echo "$out" >&2
  exit 1
}

setup_clean_tree "$TMP_DIR/with_cubit"
printf "%s\n" "import 'package:flutter_bloc/flutter_bloc.dart';" > "$TMP_DIR/with_cubit/lib/domain/test_cubit.dart"
out=$(sh "$CHECKER" "$TMP_DIR/with_cubit" 2>&1)
status=$?
if [ $status -eq 0 ]; then
  echo "FAIL Test 3 (Domain cubit violation): expected non-zero exit" >&2
  exit 1
fi
echo "$out" | grep -qi "domain" || {
  echo "FAIL Test 3 (Domain cubit violation): expected output to contain 'domain'" >&2
  echo "$out" >&2
  exit 1
}

echo "ALL ASSERTS PASSED"
exit 0
