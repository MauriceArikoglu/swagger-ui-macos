import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';

const repositoryRoot = new URL('../../', import.meta.url);
const contentDirectory = new URL('../src/content/', import.meta.url);
const publicDirectory = new URL('../public/', import.meta.url);
const repositoryURL = 'https://github.com/MauriceArikoglu/swagger-ui-macos';

const readme = await readFile(new URL('README.md', repositoryRoot), 'utf8');
const content = readme
  .replaceAll('](LICENSE)', `](${repositoryURL}/blob/main/LICENSE)`)
  .replaceAll('](THIRD_PARTY_NOTICES.md)', `](${repositoryURL}/blob/main/THIRD_PARTY_NOTICES.md)`);

const frontmatter = `---
title: Swagger UI for macOS
description: Bracket is a native macOS app for local Swagger and OpenAPI files. Open JSON or YAML definitions in Swagger UI, browse endpoints, and test API requests on your Mac.
---

`;

await mkdir(contentDirectory, { recursive: true });
await mkdir(publicDirectory, { recursive: true });
await writeFile(new URL('index.mdx', contentDirectory), frontmatter + content);
await copyFile(new URL('Assets/Bracket.png', repositoryRoot), new URL('icon.png', publicDirectory));

console.log('Prepared documentation from README.md and the current app icon.');
