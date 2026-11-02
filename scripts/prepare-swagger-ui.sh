#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$project_root/node_modules/swagger-ui-dist"
destination="$project_root/Sources/Bracket/Resources/Web/vendor"
assets=(swagger-ui-bundle.js swagger-ui.css oauth2-redirect.html oauth2-redirect.js LICENSE NOTICE swagger-ui-bundle.js.LICENSE.txt)

for asset in "${assets[@]}"; do
  if [[ ! -f "$source_dir/$asset" ]]; then
    printf 'Swagger UI is missing. Run npm install in the repository root before building.\n' >&2
    exit 1
  fi
done

# SwiftPM copies a resource directory. This generated staging folder is ignored
# by Git; the Xcode project copies the same files directly from node_modules.
mkdir -p "$destination"
for asset in "${assets[@]}"; do
  if ! cmp -s "$source_dir/$asset" "$destination/$asset"; then
    cp "$source_dir/$asset" "$destination/$asset"
  fi
done
