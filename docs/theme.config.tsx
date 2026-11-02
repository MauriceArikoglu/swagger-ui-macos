const basePath = process.env.NODE_ENV === 'production' ? '/swagger-ui-macos' : '';

const config = {
  darkMode: true,
  logo: (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '0.6rem' }}>
      <img src={`${basePath}/icon.png`} width="36" height="36" alt="" />
      <span style={{ fontWeight: 700, fontSize: '20px' }}>Bracket</span>
    </span>
  ),
  project: {
    link: 'https://github.com/MauriceArikoglu/swagger-ui-macos',
  },
  docsRepositoryBase: 'https://github.com/MauriceArikoglu/swagger-ui-macos/tree/main',
  footer: {
    content: '© 2026 MauriceArikoglu · AGPL-3.0-only',
  },
};

export default config;
