# Third-party software

Swagger UI's distribution files are not committed to this repository. `npm install` downloads the pinned `swagger-ui-dist` dependency declared in `package.json`; `package-lock.json` records its version, public registry URL, and integrity checksum.

- Upstream: [swagger-api/swagger-ui](https://github.com/swagger-api/swagger-ui)
- Installed package: `swagger-ui-dist` 5.34.1
- License: Apache License 2.0, with additional dependency notices.

When compiling the app, the build copies the upstream `LICENSE`, `NOTICE`, and `swagger-ui-bundle.js.LICENSE.txt` from `node_modules/swagger-ui-dist` alongside the required viewer assets into `Bracket.app/Contents/Resources/Web/vendor`. The alternate Swift Package build places these files in its resource bundle instead.

The Bracket icon is an original vector drawing inspired by the Swagger logo, with square brackets in place of curly braces. Bracket is an independent wrapper and is not an official Swagger product.
