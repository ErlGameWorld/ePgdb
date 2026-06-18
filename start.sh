#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

if ! command -v erl >/dev/null 2>&1; then
    echo "[ERROR] erl not found in PATH." >&2
    exit 1
fi

if ! command -v rebar3 >/dev/null 2>&1; then
    echo "[ERROR] rebar3 not found in PATH." >&2
    exit 1
fi

echo "[1/3] Compiling project modules..."
rebar3 compile

echo "[2/3] Compiling test profile modules..."
rebar3 as test compile

echo "[3/3] Starting Erlang shell with src and test code paths..."
echo
echo "Available examples after startup:"
echo "  pgdb_test_helper:start()."
echo "  pgdb_bench_tests:run_all()."
echo "  pgdb_bench_tests:run_all(5000)."
echo "  pgdb_crud_tests:module_info()."
echo "  ePgdb:schema(players)."
echo

set -- "$@"
for dir in "$ROOT"/_build/default/lib/*/ebin; do
    if [ -d "$dir" ]; then
        set -- -pa "$dir" "$@"
    fi
done
for dir in "$ROOT"/_build/test/lib/*/ebin; do
    if [ -d "$dir" ]; then
        set -- -pa "$dir" "$@"
    fi
done
if [ -d "$ROOT/_build/test/lib/ePgdb/test" ]; then
    set -- -pa "$ROOT/_build/test/lib/ePgdb/test" "$@"
fi

exec erl "$@"
