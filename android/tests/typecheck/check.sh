#!/bin/bash
# Type-checks the Android app's Kotlin with the Kotlin compiler that ships inside Gradle, against stubs of the Android SDK,
# Jetpack Compose and the other libraries (tests/typecheck/stubs: only the signatures BillBox uses). It catches syntax
# errors, wrong arguments, missing imports and type mistakes without the Android SDK; the real build is ../../build.sh.
set -e
cd "$(dirname "$0")"
L=${GRADLE_LIB:-/opt/gradle/lib}
K=$(ls "$L"/kotlin-compiler-embeddable-*.jar | head -1); S=$(ls "$L"/kotlin-stdlib-[0-9]*.jar | head -1)
CO=$(ls "$L"/kotlinx-coroutines-core-jvm-*.jar | head -1)
CP="$K:$S:$(ls "$L"/kotlin-reflect-*.jar | head -1):$(ls "$L"/kotlin-script-runtime-*.jar | head -1):$(ls "$L"/kotlin-daemon-embeddable-*.jar | head -1):$(ls "$L"/trove4j-*.jar | head -1):$(ls "$L"/annotations-*.jar | head -1):$CO"
OUT=$(mktemp -d)
LOG=$(java -cp "$CP" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -nowarn -cp "$S:$CO" -d "$OUT" \
  $(find stubs -name "*.kt") $(find ../../app/src/main/java -name "*.kt") 2>&1 | grep -v JAVA_TOOL || true)
rm -rf "$OUT"
if echo "$LOG" | grep -q "error:"; then echo "$LOG" | grep -A2 "error:"; echo "ANDROID TYPECHECK FAILED: $(echo "$LOG" | grep -c "error:") errors"; exit 1; fi
echo "ANDROID TYPECHECK OK"
