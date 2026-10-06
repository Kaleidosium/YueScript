import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { locales } from "../src/locales.mjs";

const decodeHtml = (text) =>
  text.replace(/&(#x[\da-f]+|#\d+|amp|quot|lt|gt|apos);/gi, (_, entity) => {
    if (entity[0] === "#")
      return String.fromCodePoint(
        entity[1].toLowerCase() === "x"
          ? parseInt(entity.slice(2), 16)
          : Number(entity.slice(1)),
      );
    return { amp: "&", quot: '"', lt: "<", gt: ">", apos: "'" }[entity];
  });

const files = readdirSync("src/content/docs", { recursive: true }).filter(
  (file) => /\.mdx?$/.test(file),
);
const docs = files
  .map((file) => {
    const source = readFileSync(`src/content/docs/${file}`, "utf8");
    const frontmatter = source.match(/^---\n([\s\S]*?)\n---/)?.[1] ?? "";
    const slug = file.replace(/\.mdx?$/, "").replace(/\/index$/, "");
    return {
      file,
      source,
      slug,
      splash: /^template:\s*splash$/m.test(frontmatter),
      order: Number(frontmatter.match(/^  order: (-?\d+)/m)?.[1] ?? Infinity),
    };
  })
  .sort((a, b) => a.order - b.order || a.slug.localeCompare(b.slug));

const localeFor = (file) =>
  Object.keys(locales).find((locale) => file.startsWith(`${locale}/`)) ?? "root";

function checkInterface(html, route) {
  for (const [image] of html.matchAll(/<img\b[^>]*>/g)) {
    assert.match(image, /\salt(?:="[^"]*"|(?=\s|>))/, `Image needs alternative text: ${route}`);
    assert.match(image, /\bwidth="\d+"/, `Image needs a numeric width: ${route}`);
    assert.match(image, /\bheight="\d+"/, `Image needs a numeric height: ${route}`);
  }
  assert.match(html, /class="[^"]*sl-skip-link/, `Missing skip link: ${route}`);
  assert.match(html, /name="theme-color"/, `Missing theme color: ${route}`);
  assert.match(html, /rel="preload"[^>]*as="font"/, `Missing heading font preload: ${route}`);
  for (const [code] of html.matchAll(/<(?:pre|code)\b[^>]*>/g)) {
    assert.match(code, /\btranslate="no"/, `Code must not be auto-translated: ${route}`);
  }
}

for (const [locale, { lang }] of Object.entries(locales)) {
  const route = locale === "root" ? "/all-in-one/" : `/${locale}/all-in-one/`;
  const aggregate = readFileSync(`dist${route}index.html`, "utf8");
  checkInterface(aggregate, route);
  const localeDocs = docs.filter(({ file, splash }) => !splash && localeFor(file) === locale);
  const sections = [...aggregate.matchAll(/<article id="([^"]+)"/g)].map(
    (match) => match[1],
  );
  assert.deepEqual(
    sections,
    localeDocs.map(({ slug }) => slug),
    `${route} must include only its language's docs, excluding splash pages, once in sidebar order`,
  );
  assert.ok(aggregate.includes(`lang="${lang}"`), `Wrong page language: ${route}`);
  const ids = [...aggregate.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]);
  const anchors = new Set(ids);
  assert.equal(ids.length, anchors.size, `Duplicate aggregate IDs: ${route}`);
  for (const [, hash] of aggregate.matchAll(/\shref="#([^"]+)"/g)) {
    assert.ok(anchors.has(decodeURIComponent(hash)), `Missing anchor: ${route}#${hash}`);
  }
  assert.ok(!aggregate.includes("<starlight-toc"), `Unexpected TOC: ${route}`);
  assert.equal(
    (aggregate.match(/data-yue-compile(?:>|\s)/g) ?? []).length,
    localeDocs.reduce((count, { source }) =>
      count + (source.match(/data-yue-compile(?:>|\s)/g) ?? []).length, 0),
    `Missing aggregate compiler controls: ${route}`,
  );
}

let controls = 0;
for (const { file, source, slug, splash } of docs) {
  const output = `dist/${slug === "index" ? "" : `${slug}/`}index.html`;
  assert.ok(existsSync(output), `Missing documentation route: ${output}`);
  if (!/(^|\/)index\.mdx?$/.test(file)) {
    const redirect = `dist/${slug}.html`;
    assert.ok(
      statSync(redirect).isFile(),
      `Legacy HTML route must be a file: ${redirect}`,
    );
    assert.ok(
      readFileSync(redirect, "utf8").includes(`/${slug}/`),
      `Wrong legacy redirect: ${redirect}`,
    );
  }
  const html = readFileSync(output, "utf8");
  checkInterface(html, `/${slug}/`);
  const locale = localeFor(file);
  const aggregateRoute = locale === "root" ? "/all-in-one/" : `/${locale}/all-in-one/`;
  // Splash pages have no sidebar; all documentation pages link to their own language.
  if (!splash) {
    assert.ok(html.includes(`href="${aggregateRoute}"`), `Missing locale aggregate link: ${file}`);
  }
  const expectedControls = (source.match(/data-yue-compile(?:>|\s)/g) ?? [])
    .length;
  assert.equal(
    (html.match(/data-yue-compile(?:>|\s)/g) ?? []).length,
    expectedControls,
    `Missing compiler controls: ${file}`,
  );
  controls += expectedControls;
  const snippets = [
    ...source.matchAll(
      /<div class="yue-example">[\s\S]*?```(?:yue|yuescript)\n([\s\S]*?)\n```/g,
    ),
  ].map((match) => match[1]);
  const payloads = [
    ...html.matchAll(/<div class="yue-example">[\s\S]*?\sdata-code="([^"]*)"/g),
  ].map((match) => decodeHtml(match[1]).replaceAll("\u007f", "\n"));
  assert.deepEqual(
    payloads,
    snippets,
    `Compiler payload must preserve every code line: ${file}`,
  );
  for (const [, pathname] of html.matchAll(
    /(?:href|src)="(\/(?!\/)[^"#?]*)[^\"]*"/g,
  )) {
    const path = decodeURIComponent(pathname);
    assert.ok(
      existsSync(`dist${path}`) || existsSync(`dist${path}/index.html`),
      `Broken local link in ${file}: ${path}`,
    );
  }
}
assert.ok(
  !readdirSync(".").some((file) => /^yue-.*\.md$/.test(file)),
  "Standalone yue-*.md manuals must be removed",
);
console.log(
  `Verified ${docs.length} routes, legacy HTML redirects, ${Object.keys(locales).length} language aggregates, ordering and anchors, and ${controls} compiler controls.`,
);
