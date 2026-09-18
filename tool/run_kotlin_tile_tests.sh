#!/bin/sh
# Host-JVM test runner for the framework-free QuickTile state mirror.
# No Gradle, no Android SDK: kotlinc compiles the mirror + its JUnit test and
# JUnitCore runs them directly. This is the only way to exercise the state
# logic on this box because TileService/Tile cannot load on the host JVM.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname -- "$script_dir")
cd "$repo_root"

kotlin_version=2.2.20
tools_dir="$repo_root/build/kotlin-tools"
kotlinc_bin="$tools_dir/kotlinc/bin/kotlinc"
out_dir="$repo_root/build/kotlin-tile-tests"
classes_dir="$out_dir/classes"
compile_log="$out_dir/compile.log"
test_log="$out_dir/junit.log"

mirror_src="$repo_root/android/app/src/main/kotlin/ai/hermes/flames/QuickTileStateMirror.kt"
test_src="$repo_root/android/app/src/test/kotlin/ai/hermes/flames/QuickTileStateMirrorTest.kt"

if [ ! -x "$kotlinc_bin" ]; then
  echo "kotlinc not found at $kotlinc_bin — downloading Kotlin $kotlin_version"
  mkdir -p "$tools_dir"
  zip="$tools_dir/kotlin-compiler-$kotlin_version.zip"
  curl -fL -o "$zip" \
    "https://github.com/JetBrains/kotlin/releases/download/v$kotlin_version/kotlin-compiler-$kotlin_version.zip"
  unzip -q -o "$zip" -d "$tools_dir"
fi

if [ ! -x "$kotlinc_bin" ]; then
  echo "run_kotlin_tile_tests.sh: kotlinc still missing after download: $kotlinc_bin" >&2
  echo "KOTLIN_TILE_TESTS_EXIT=1"
  exit 1
fi

junit_jar=$(find "$HOME/.gradle/wrapper/dists" -name 'junit-4.13.2.jar' -print 2>/dev/null | head -n 1)
hamcrest_jar=$(find "$HOME/.gradle/wrapper/dists" -name 'hamcrest-core-1.3.jar' -print 2>/dev/null | head -n 1)

if [ -z "$junit_jar" ] || [ ! -f "$junit_jar" ]; then
  echo "run_kotlin_tile_tests.sh: junit-4.13.2.jar not found under $HOME/.gradle/wrapper/dists" >&2
  echo "KOTLIN_TILE_TESTS_EXIT=1"
  exit 1
fi

if [ -z "$hamcrest_jar" ] || [ ! -f "$hamcrest_jar" ]; then
  echo "run_kotlin_tile_tests.sh: hamcrest-core-1.3.jar not found under $HOME/.gradle/wrapper/dists" >&2
  echo "KOTLIN_TILE_TESTS_EXIT=1"
  exit 1
fi

rm -rf "$classes_dir"
mkdir -p "$classes_dir"

if ! "$kotlinc_bin" -jvm-target 17 -cp "$junit_jar:$hamcrest_jar" \
    -d "$classes_dir" "$mirror_src" "$test_src" > "$compile_log" 2>&1; then
  echo "run_kotlin_tile_tests.sh: compilation failed" >&2
  cat "$compile_log" >&2
  echo "KOTLIN_TILE_TESTS_EXIT=1"
  exit 1
fi

if java -cp "$classes_dir:$junit_jar:$hamcrest_jar" \
    org.junit.runner.JUnitCore ai.hermes.flames.QuickTileStateMirrorTest > "$test_log" 2>&1; then
  exit_code=0
else
  exit_code=$?
fi

cat "$test_log"
echo "KOTLIN_TILE_TESTS_EXIT=$exit_code"
exit "$exit_code"
