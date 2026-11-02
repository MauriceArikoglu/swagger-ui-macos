import type { ReactNode } from 'react';
import { Head } from 'nextra/components';
import { getPageMap } from 'nextra/page-map';
import { Footer, Layout, Navbar } from 'nextra-theme-docs';

import themeConfig from '../../theme.config';
import 'nextra-theme-docs/style.css';
import '../styles/global.css';

const basePath = process.env.NODE_ENV === 'production' ? '/swagger-ui-macos' : '';

export const metadata = {
  metadataBase: new URL('https://mauricearikoglu.github.io'),
  title: 'Swagger UI for macOS — Bracket',
  description: 'Bracket is a native macOS app for local Swagger and OpenAPI files. Open JSON or YAML definitions in Swagger UI, browse endpoints, and test API requests on your Mac.',
  alternates: {
    canonical: '/swagger-ui-macos/',
  },
  icons: {
    icon: `${basePath}/icon.png`,
  },
};

export default async function RootLayout({ children }: { children: ReactNode }) {
  const pageMap = await getPageMap();

  return (
    <html className="group/html" lang="en" dir="ltr" suppressHydrationWarning>
      <Head />
      <body>
        <Layout
          darkMode={themeConfig.darkMode}
          docsRepositoryBase={themeConfig.docsRepositoryBase}
          editLink={null}
          feedback={{ content: null }}
          footer={<Footer>{themeConfig.footer.content}</Footer>}
          navbar={
            <Navbar
              logo={themeConfig.logo}
              projectLink={themeConfig.project.link}
            />
          }
          pageMap={pageMap}
        >
          {children}
        </Layout>
      </body>
    </html>
  );
}
