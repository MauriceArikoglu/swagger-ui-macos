const nextra = require('nextra').default;

const withNextra = nextra({});
const basePath = process.env.NODE_ENV === 'production' ? '/swagger-ui-macos' : '';

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  outputFileTracingRoot: __dirname,
  basePath,
  images: {
    unoptimized: true,
  },
  reactStrictMode: true,
  trailingSlash: true,
};

module.exports = withNextra(nextConfig);
