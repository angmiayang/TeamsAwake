#!/bin/bash
# Runs the unit tests for the decision logic (src/governor.swift).
# The tests need no Accessibility access and no waiting: time is injected.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p build
swiftc -swift-version 5 src/governor.swift tests/main.swift -o build/governor-tests
./build/governor-tests
