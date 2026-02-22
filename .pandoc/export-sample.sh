#!/usr/bin/env bash
set -euo pipefail

# export-sample.sh — Deprecated stub (backward compatibility)
#
# Sample content has been removed from the Keystone Docker image.
# This stub exists so older slim templates that call export-sample.sh
# fail gracefully instead of hitting a "command not found" error.

echo "DEPRECATED: 'make sample' and export-sample.sh have been removed." >&2
echo "  To get started with a working example, see:" >&2
echo "    https://github.com/knight-owl-dev/keystone-hello-world" >&2
echo "  For guided project setup, use:" >&2
echo "    https://github.com/knight-owl-dev/keystone-cli" >&2
exit 1
