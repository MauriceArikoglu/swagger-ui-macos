import { generateStaticParamsFor, importPage } from 'nextra/pages';

import { useMDXComponents as getMDXComponents } from '../../mdx-components';

export const generateStaticParams = generateStaticParamsFor('mdxPath');

type PageProps = {
  params: Promise<{ mdxPath?: Array<string> }>;
};

export async function generateMetadata({ params }: PageProps) {
  const { mdxPath } = await params;
  const { metadata } = await importPage(mdxPath ?? []);

  return metadata;
}

const Wrapper = getMDXComponents({}).wrapper;

export default async function Page({ params }: PageProps) {
  const resolvedParams = await params;
  const { mdxPath } = resolvedParams;
  const {
    default: MDXContent,
    toc,
    metadata,
    sourceCode,
  } = await importPage(mdxPath ?? []);

  return (
    <Wrapper toc={toc} metadata={metadata} sourceCode={sourceCode}>
      <MDXContent params={resolvedParams} />
    </Wrapper>
  );
}
