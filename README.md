# Swagger UI for macOS

**Bracket** is a native macOS app that brings Swagger UI to local Swagger and OpenAPI files. Use it as a local Swagger UI viewer to open JSON or YAML API definitions, browse endpoints and schemas, and test API requests from a Mac window.

Drop a definition into the app, or open it with **⌘O**. Use **⌘R** to reload changes from disk.

The repository does **not** include Swagger UI's distribution files. Install them with npm before compiling. The build takes the required files from `node_modules/swagger-ui-dist` and includes them in the finished app. Node.js and npm are build dependencies; the finished app runs without them or a separate server.

## Requirements

- A Mac with Xcode 26 or later and the macOS SDK.
- Node.js with npm, for downloading Swagger UI.

The finished app supports macOS 13 or later, on Apple Silicon and Intel. Running the tests requires macOS 14 or later.

## Setup

```sh
git clone https://github.com/MauriceArikoglu/swagger-ui-macos.git
cd swagger-ui-macos
npm install
open Bracket.xcodeproj
```

For a repeatable install that uses the committed lockfile exactly, use `npm ci` instead of `npm install`. Swagger UI is pinned to version **5.34.1**.

No API credentials, environment files, private npm configuration, or signing certificates are required to build the app.

## Build in Xcode

1. Select the **Bracket** scheme and **My Mac**.
2. Press **⌘R** to build and run.
3. Press **⌘U** to run the core tests.

The project contains native app, `BracketCore` static library, and `BracketCoreTests` targets. Xcode compiles `Assets/AppIcon.icon` directly. The **Bundle Swagger UI from node_modules** build phase copies the required JavaScript, CSS, OAuth redirect files, and license notices from the npm installation into the app.

Local builds use ad-hoc signing and do not require a developer team. For distribution to other Macs, configure your own signing team and notarization in Xcode.

## Compile from a terminal

After `npm install`:

```sh
xcodebuild -project Bracket.xcodeproj -scheme Bracket \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .build/Xcode build

open .build/Xcode/Build/Products/Release/Bracket.app
```

The Release build supports Apple Silicon and Intel. Copy the resulting `Bracket.app` into Applications to install it.

### Alternate Swift Package build

```sh
npm install
./scripts/build.sh
open dist/Bracket.app
```

To build both architectures:

```sh
./scripts/build.sh --arch arm64 --arch x86_64
```

These scripts use the included compiled icon exports. They stage the required npm assets in the ignored `Sources/Bracket/Resources/Web/vendor` directory before SwiftPM copies the resources. To refresh this staging directory manually, run `npm run prepare:swagger-ui`.

## Use

- Drop one `.json`, `.yaml`, or `.yml` definition anywhere in the window.
- Click **Choose a file…** or **Open…**, or press **⌘O**.
- Use Finder's **Open With → Bracket**, or drop a file onto its Dock icon.
- Press **⌘R** after editing the file.
- Search, expand operations, authorize, and execute requests through Swagger UI.
- Use **⌘+**, **⌘−**, and **⌘0** to change or reset the viewer zoom.

The viewer supports Swagger 2.0 and the OpenAPI versions supported by the installed Swagger UI. Definitions must be UTF-8 text and at most 32 MB. One definition is open at a time. Local JSON and YAML references in the definition's folder or its subfolders are available; references above that folder are blocked.

The finished app serves its viewer through an in-process HTTP server bound to `127.0.0.1` on a dynamically selected port. It does not upload definitions to the Swagger validator. Remote `$ref` files and OAuth discovery can require a network connection. **Try it out** sends requests to the server selected in the definition. That server must allow the app's `http://127.0.0.1:<port>` origin through CORS. Bracket does not proxy API requests. Authorization uses an in-memory WebKit session.

## Tests

```sh
npm ci
xcodebuild -project Bracket.xcodeproj -scheme Bracket \
  -destination 'platform=macOS' -derivedDataPath .build/Xcode test
```

Swift Package tests are also available through `./scripts/test.sh`.

To run the actual app's smoke check after a Release build:

```sh
.build/Xcode/Build/Products/Release/Bracket.app/Contents/MacOS/Bracket \
  --smoke-test "$PWD/Tests/Fixtures/petstore.yaml" \
  --smoke-output "$PWD/.build/smoke"
```

The smoke check verifies the native start-screen icon, pasteboard drop handling, YAML and JSON rendering, special-character filenames, Swagger 2.0, operation expansion, changed-file reload, parser errors, and local resource loading. It writes screenshots and `report.json`, then exits. It does not simulate a physical Finder drag or execute API operations.

## Documentation

Read the [Bracket documentation](https://mauricearikoglu.github.io/swagger-ui-macos/) on GitHub Pages.

The site uses the Nextra docs theme, Next.js static export, and Pagefind search. Its main page is generated from this README on each build. Edit this file to keep the repository and documentation in sync. The build also copies the current app icon and converts the license links to GitHub URLs.

To build the documentation with Node.js 24:

```sh
npm ci --prefix docs
npm run --prefix docs export
```

The static site is written to `docs/out`. For local development, run `npm run --prefix docs dev` and open `http://localhost:3000`.

The **Pages: Build and Push** action validates documentation changes in pull requests and deploys changes from `main`. You can also run it manually from GitHub Actions. GitHub Pages uses **GitHub Actions** as its publishing source.

## Icon and source layout

- `Bracket.xcodeproj`: app project and shared build, run, and test scheme.
- `Sources/Bracket`: native window, menus, file drop handling, and WebKit integration.
- `Sources/BracketCore`: document loading and loopback HTTP server.
- `Sources/Bracket/Resources/Web`: the app's HTML, CSS, and JavaScript shell.
- `Assets/AppIcon.icon`: editable Icon Composer document, with rounded brackets and dots in translucent white glass over a green gradient.
- `Tests/Fixtures/petstore.yaml`: a synthetic definition for local validation.

The start screen uses an image rendered from the running app's native icon, so it matches the current glass icon. It does not use a separate flat SVG.

To edit the icon, open `Assets/AppIcon.icon` in Icon Composer. Xcode compiles it automatically. For the alternate Swift Package build, regenerate the included icon exports with `./scripts/make-icon.sh`; this requires Apple's Icon Composer renderer and Xcode.

`node_modules`, generated Swagger UI staging files, build outputs, Xcode user data, credentials, local settings, and editor metadata are excluded from Git. Do not add private API definitions or authentication files to the repository.

## License

Copyright (C) 2026 MauriceArikoglu.

Bracket is licensed under the GNU Affero General Public License v3.0 only (`AGPL-3.0-only`). See [LICENSE](LICENSE) for the full terms.

Third-party components retain their own licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for upstream licenses. Bracket is an independent wrapper for [Swagger UI](https://github.com/swagger-api/swagger-ui).
