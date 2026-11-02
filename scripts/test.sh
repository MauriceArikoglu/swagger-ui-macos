#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
"$project_root/scripts/prepare-swagger-ui.sh"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/ModuleCache"
swift test --cache-path "$project_root/.build/cache" --config-path "$project_root/.build/config" --security-path "$project_root/.build/security" --disable-sandbox
