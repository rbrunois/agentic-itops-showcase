// Builds the GitHub Pages site into _site/:
//   - copies docs/ (landing page and shared assets),
//   - regenerates the landing page use case catalogue from the root README tables,
//   - renders one marketing page per use case from Tools/<folder>/site.yml.
// A use case without site.yml still gets a basic page from the README catalogue.
// The full documentation stays in each README on GitHub; pages link to it.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Marked } from 'marked';
import YAML from 'yaml';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const out = path.join(root, '_site');
const repo = process.env.GITHUB_REPOSITORY || 'rbrunois/agentic-itops-showcase';
const branch = process.env.SITE_BRANCH || 'main';
const repoUrl = `https://github.com/${repo}`;
const siteUrl = (process.env.SITE_URL || `https://${repo.split('/')[0].toLowerCase()}.github.io/${repo.split('/')[1]}`).replace(/\/?$/, '/');

const ICONS = ['shield', 'refresh', 'person', 'tag', 'search', 'pulse', 'file', 'check', 'chart', 'cloud', 'network', 'clock', 'lock', 'book'];
const escapeHtml = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const stripTags = (s) => s.replace(/<[^>]+>/g, '').replace(/&(amp|lt|gt|quot|#39);/g, (m) => ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'" })[m]).trim();
// Plain text with `code` spans.
const txt = (s) => escapeHtml(s).replace(/`([^`]+)`/g, '<code>$1</code>');
const ico = (name) => `<svg class="ico"><use href="#i-${name}"/></svg>`;
const errors = [];
const fail = (msg) => errors.push(msg);

// --- Catalogue from the root README ---------------------------------------
const rootReadme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
const inline = new Marked();
const useCases = [];
const rowRe = /^\|\s*(\d+)\s*\|\s*\[([^\]]+)\]\((Tools\/([^/)]+)\/[^)]*)\)\s*\|(.*)\|\s*$/gm;
for (const m of rootReadme.matchAll(rowRe)) {
  const [what = '', value = '', owners = ''] = m[5].split(/\s\|\s/).map((c) => c.trim());
  useCases.push({
    number: m[1].padStart(2, '0'), name: m[2], folder: m[4],
    whatHtml: inline.parseInline(what), valueHtml: inline.parseInline(value), ownersHtml: inline.parseInline(owners),
    // Owners are links such as [Full Name](https://github.com/handle) or [@handle](...).
    owners: [...owners.matchAll(/\[([^\]]+)\]\([^)]*\)/g)].map((o) => o[1]),
  });
}
const kinds = {};
for (const m of rootReadme.matchAll(/^\|\s*(Runnable demo|Design or guidance package)\s*\|\s*([\d,\s]+)\|/gm)) {
  for (const n of m[2].split(',').map((x) => x.trim()).filter(Boolean)) kinds[n.padStart(2, '0')] = m[1].startsWith('Runnable') ? 'run' : 'blue';
}

// Every use case folder must be in the catalogue, so new use cases can't be missed.
const folders = fs.readdirSync(path.join(root, 'Tools'), { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name);
for (const f of folders) if (!useCases.some((u) => u.folder === f)) fail(`Tools/${f} is not listed in the root README use case table.`);
for (const u of useCases) {
  if (!folders.includes(u.folder)) fail(`README lists Tools/${u.folder}, which does not exist.`);
  if (!kinds[u.number]) fail(`Use case ${u.number} (${u.name}) is missing from the "Use case types" table.`);
  u.kind = kinds[u.number] || 'blue';
}
useCases.sort((a, b) => a.number.localeCompare(b.number));

// --- site.yml --------------------------------------------------------------
function readmeFor(folder) {
  for (const name of ['README.en.md', 'README.md']) {
    const rel = `Tools/${folder}/${name}`;
    if (fs.existsSync(path.join(root, rel))) return rel;
  }
  return null;
}

function detectAgent(text) {
  if (/SRE[\s-]+Agent/i.test(text)) return 'Azure SRE Agent';
  if (/Copilot\s+Studio/i.test(text)) return 'Copilot Studio agent';
  return 'AI agent';
}

function loadSite(u) {
  const rel = `Tools/${u.folder}/site.yml`;
  const file = path.join(root, rel);
  if (!fs.existsSync(file)) {
    console.warn(`::warning file=${rel}::No site.yml: ${u.name} gets a basic page. Copy scripts/site/site-template.yml to add marketing content.`);
    return null;
  }
  let d;
  try { d = YAML.parse(fs.readFileSync(file, 'utf8')); } catch (e) { fail(`${rel}: invalid YAML (${e.message.split('\n')[0]})`); return null; }
  const where = (k) => `${rel}: ${k}`;
  const str = (v, k, max) => {
    if (typeof v !== 'string' || !v.trim()) return fail(where(`${k} must be a non-empty string`));
    if (max && v.length > max) fail(where(`${k} is ${v.length} characters; keep it under ${max}`));
  };
  const list = (v, k, min, max) => {
    if (!Array.isArray(v) || v.length < min || v.length > max) return fail(where(`${k} needs ${min === max ? min : `${min} to ${max}`} items`)) || false;
    return true;
  };
  const pair = (v, k) => (Array.isArray(v) && v.length === 2 && v.every((x) => typeof x === 'string')) || fail(where(`${k} must be ["text", "meta"]`));
  if (!d || typeof d !== 'object') { fail(where('must be a YAML mapping')); return null; }
  str(d.tagline, 'tagline', 90);
  str(d.problem, 'problem');
  if (list(d.benefits, 'benefits', 3, 4)) d.benefits.forEach((b, i) => {
    str(b?.title, `benefits[${i}].title`, 40); str(b?.text, `benefits[${i}].text`, 160);
    if (!ICONS.includes(b?.icon)) fail(where(`benefits[${i}].icon must be one of ${ICONS.join(', ')}`));
  });
  for (const k of ['trigger', 'analyze', 'approve', 'apply']) str(d.flow?.[k], `flow.${k}`, 90);
  const demo = d.demo || {};
  str(demo.handle, 'demo.handle'); str(demo.ask, 'demo.ask'); str(demo.proposal?.title, 'demo.proposal.title');
  if (list(demo.steps, 'demo.steps', 3, 3)) demo.steps.forEach((s, i) => pair(s, `demo.steps[${i}]`));
  if (list(demo.applied, 'demo.applied', 2, 2)) demo.applied.forEach((s, i) => pair(s, `demo.applied[${i}]`));
  if (list(demo.proposal?.lines, 'demo.proposal.lines', 1, 4)) demo.proposal.lines.forEach((l, i) => {
    if (!Array.isArray(l) || !['+', '-'].includes(l[0]) || typeof l[1] !== 'string') fail(where(`demo.proposal.lines[${i}] must be ["+" or "-", "text"]`));
  });
  for (const k of ['label', 'source', 'value']) str(demo.stat?.[k] == null ? demo.stat?.[k] : String(demo.stat[k]), `demo.stat.${k}`);
  if (list(demo.evidence, 'demo.evidence', 3, 3)) demo.evidence.forEach((e, i) => {
    if (!['fact', 'inference'].includes(e?.type)) fail(where(`demo.evidence[${i}].type must be fact or inference`));
    str(e?.text, `demo.evidence[${i}].text`);
  });
  for (const k of ['readonly', 'human']) if (list(d.safety?.[k], `safety.${k}`, 2, 4)) d.safety[k].forEach((s, i) => str(s, `safety.${k}[${i}]`));
  for (const k of ['audience', 'needs']) if (list(d[k], k, 2, 5)) d[k].forEach((s, i) => str(s, `${k}[${i}]`));
  if (list(d.services, 'services', 1, 10)) d.services.forEach((s, i) => str(s, `services[${i}]`));
  if (d.image != null) {
    const img = path.posix.normalize(path.posix.join(`Tools/${u.folder}`, d.image));
    if (!img.startsWith(`Tools/${u.folder}/`) || !fs.existsSync(path.join(root, img))) fail(where(`image ${d.image} does not exist in the use case folder`));
    else d.imagePath = img;
    str(d.image_alt, 'image_alt');
  }
  return d;
}

// --- Page sections ---------------------------------------------------------
const guardrails = `<ul class="guard" aria-label="Guardrails this use case follows">
        ${['read-only-by-default', 'evidence-first', 'humans-approve-changes', 'synthetic-data-only'].map((g) => `<li>${ico('check')}${g}</li>`).join('\n        ')}
      </ul>`;

function hero(u, s, links) {
  const name = s ? `<p class="uc-name">${escapeHtml(u.name)}</p>` : '';
  const h1 = s ? txt(s.tagline) : escapeHtml(u.name);
  const chips = s ? `<ul class="chips" aria-label="Services">${s.services.map((x) => `<li>${escapeHtml(x)}</li>`).join('')}</ul>` : '';
  const figure = s?.imagePath ? `<figure class="uc-visual"><img src="../files/${encodeURI(s.imagePath)}" alt="${escapeHtml(s.image_alt)}" loading="lazy"></figure>` : '';
  return `  <section class="hero uc-hero" aria-labelledby="hero-h">
    <div class="wrap">
      <nav class="crumbs" aria-label="Breadcrumb"><a href="../">Showcase</a><span aria-hidden="true">/</span><a href="../#use-cases">Use cases</a><span aria-hidden="true">/</span><span class="mono">${u.folder}</span></nav>
      <p class="uc-badge"><span class="announce"><b>Use case ${u.number}</b>${u.kind === 'run' ? 'Runnable demo' : 'Blueprint'} · ${escapeHtml(u.agent)}</span></p>
      ${name}
      <h1 id="hero-h">${h1}</h1>
      <p class="lede">${u.whatHtml}</p>
      <div class="actions">
        <a class="btn btn-primary" href="${links.readme}">${ico('book')}Read the guide</a>
        <a class="btn" href="${links.tree}">View on GitHub</a>
      </div>
      ${chips}
      ${figure}
    </div>
  </section>`;
}

function section(id, kicker, title, lede, inner) {
  return `  <section class="sec" id="${id}" aria-labelledby="${id}-h">
    <div class="wrap">
      <p class="kicker">${kicker}</p>
      <h2 id="${id}-h">${title}</h2>
      ${lede ? `<p class="sec-lede">${lede}</p>` : ''}
      ${inner}
    </div>
  </section>`;
}

function consoleHtml(u, s) {
  const run = {
    name: u.name, kind: u.kind === 'run' ? 'Runnable' : 'Blueprint', sev: 's4', agent: s.demo.handle, sub: u.folder,
    ask: s.demo.ask, steps: s.demo.steps, title: s.demo.proposal.title, diff: s.demo.proposal.lines, applied: s.demo.applied,
    stat: [s.demo.stat.label, s.demo.stat.source, String(s.demo.stat.value)],
    evidence: s.demo.evidence.map((e) => [e.type === 'fact' ? 'fact' : 'inf', e.text]),
  };
  // `<` is escaped so README-derived text can't close the script element.
  const json = JSON.stringify([run]).replace(/</g, '\\u003c');
  return `<div class="console" id="console" role="region" aria-label="Interactive example: a sample ${escapeHtml(u.name)} run waiting for human approval">
        <div class="c-bar">
          <img src="../assets/logo.svg" alt="" width="20" height="20">
          <span class="crumb"><b>${escapeHtml(u.agent)}</b><span> / contoso / ${u.folder}</span></span>
          <span class="spacer"></span>
          <span class="state investigating" id="state" aria-live="polite">Awaiting approval</span>
        </div>
        <div class="c-body">
          <div class="c-thread">
            <div class="ask"><span class="avatar" aria-hidden="true">OP</span><div class="bubble"><span class="mention" id="agent-name"></span> <span id="ask"></span></div></div>
            <ol class="tl" id="timeline"></ol>
            <div class="proposal">
              <header><span><b>Proposal</b> · <span id="p-title"></span></span><span class="tag prop">PROPOSAL</span></header>
              <pre class="diff mono" id="diff"></pre>
              <footer>
                <button class="btn btn-primary btn-sm" type="button" id="approve">Approve</button>
                <button class="btn btn-sm" type="button" id="reject">Reject</button>
                <button class="btn btn-sm" type="button" id="replay" hidden>${ico('replay')}Replay</button>
                <span class="note" id="note"></span>
              </footer>
            </div>
          </div>
          <aside class="c-evidence" aria-label="Evidence (sample)">
            <h3>Evidence</h3>
            <div class="stat"><span class="lbl"><span id="stat-label"></span><span class="mono" id="stat-src"></span></span><b id="stat-value"></b></div>
            <ul class="ev" id="evidence"></ul>
          </aside>
        </div>
      </div>
      <p class="demo-note">Fictional sample run with Contoso data. Try <b>Approve</b> or <b>Reject</b>.</p>
      <script type="application/json" id="runs-data">${json}</script>
      <script src="../assets/console.js" defer></script>`;
}

function pager(i) {
  const prev = useCases[i - 1], next = useCases[i + 1];
  return `<nav class="pager" aria-label="Other use cases">${prev ? `<a class="prev" href="../${prev.folder}/"><small>← Previous</small>${escapeHtml(prev.name)}</a>` : ''}${next ? `<a class="next" href="../${next.folder}/"><small>Next →</small>${escapeHtml(next.name)}</a>` : ''}</nav>`;
}

function cta(u, links, i) {
  return `  <div class="wrap">
    <section class="cta-band" aria-labelledby="cta-h">
      <h2 id="cta-h">Ready to try ${escapeHtml(u.name)}?</h2>
      <p>The guide covers prerequisites, setup, safety and cleanup step by step.</p>
      <div class="actions" style="margin:0">
        <a class="btn btn-primary" href="${links.readme}">${ico('book')}Read the guide</a>
        <a class="btn" href="${links.tree}">Browse the files</a>
      </div>
    </section>
    ${pager(i)}
  </div>`;
}

function fullBody(u, s, links, i) {
  const benefits = `<ul class="benefits">${s.benefits.map((b) => `
        <li><span class="b-ico">${ico(b.icon)}</span><h3>${escapeHtml(b.title)}</h3><p>${txt(b.text)}</p></li>`).join('')}
      </ul>`;
  const steps = [['Trigger', 'pulse', s.flow.trigger], ['Analyze', 'search', s.flow.analyze], ['Approve', 'person', s.flow.approve], ['Apply', 'check', s.flow.apply]];
  const flow = `<ol class="flow">${steps.map(([t, icon, d]) => `
        <li${t === 'Approve' ? ' class="gate"' : ''}><span class="num">${ico(icon)}</span><h3>${t}</h3><p>${txt(d)}</p></li>`).join('')}
      </ol>`;
  const safety = `<div class="two">
        <div class="panel"><h3>${ico('lock')}Read-only by design</h3><ul class="ticks">${s.safety.readonly.map((x) => `<li>${ico('check')}<span>${txt(x)}</span></li>`).join('')}</ul></div>
        <div class="panel gate"><h3>${ico('person')}A human decides</h3><ul class="ticks">${s.safety.human.map((x) => `<li>${ico('person')}<span>${txt(x)}</span></li>`).join('')}</ul></div>
      </div>
      ${guardrails}`;
  const fit = `<div class="two">
        <div class="panel"><h3>Who it's for</h3><ul class="ticks">${s.audience.map((x) => `<li>${ico('check')}<span>${txt(x)}</span></li>`).join('')}</ul></div>
        <div class="panel"><h3>What you need</h3><ul class="ticks">${s.needs.map((x) => `<li>${ico('check')}<span>${txt(x)}</span></li>`).join('')}</ul></div>
      </div>
      <div class="value-card"><span class="b-ico">${ico('star')}</span><div><h3>The value</h3><p>${u.valueHtml}</p></div></div>`;
  return [
    hero(u, s, links),
    section('why', 'Why it matters', 'The problem it solves.', txt(s.problem.trim()), benefits),
    section('how', 'How it works', 'From trigger to approved change.', `The same operating model as every use case in the showcase, applied to ${escapeHtml(u.name)}.`, flow),
    section('demo', 'See it in action', 'One run, start to finish.', `${u.agent === 'Azure SRE Agent' ? 'Azure SRE Agent' : `The ${escapeHtml(u.agent)}`} does the analysis and prepares the change. You decide.`, consoleHtml(u, s)),
    section('safety', 'Safety', 'Built to keep people in control.', '', safety),
    section('fit', 'Is it for you?', 'Who it helps and what it takes.', '', fit),
    cta(u, links, i),
  ].join('\n\n');
}

function basicBody(u, links, i) {
  const facts = `<div class="two">
        <div class="panel"><h3>The value</h3><p>${u.valueHtml}</p></div>
        <div class="panel"><h3>Maintained by</h3><p>${u.ownersHtml || 'Community'}</p></div>
      </div>
      ${guardrails}`;
  return [hero(u, null, links), section('about', 'About', 'What you get.', '', facts), cta(u, links, i)].join('\n\n');
}

// --- Build -----------------------------------------------------------------
fs.rmSync(out, { recursive: true, force: true });
fs.cpSync(path.join(root, 'docs'), out, { recursive: true });

const landingPath = path.join(out, 'index.html');
let landing = fs.readFileSync(landingPath, 'utf8');
const sprite = landing.match(/<svg width="0"[\s\S]*?<\/svg>/)[0];
const template = fs.readFileSync(path.join(here, 'usecase.html'), 'utf8');
const fill = (tpl, data) => tpl.replace(/\{\{(\w+)\}\}/g, (_, k) => {
  if (!(k in data)) throw new Error(`Template value missing: ${k}`);
  return data[k];
});

const pages = [];
for (const u of useCases) {
  const readme = readmeFor(u.folder);
  if (!readme) { fail(`Tools/${u.folder} has no README.md.`); continue; }
  u.readme = readme;
  u.agent = detectAgent(fs.readFileSync(path.join(root, readme), 'utf8'));
  u.site = loadSite(u);
}
if (errors.length) {
  for (const e of errors) console.error(`::error::${e}`);
  process.exit(1);
}

for (const [i, u] of useCases.entries()) {
  const s = u.site;
  const links = { readme: `${repoUrl}/blob/${branch}/${u.readme}`, tree: `${repoUrl}/tree/${branch}/Tools/${u.folder}` };
  if (s?.imagePath) {
    fs.mkdirSync(path.dirname(path.join(out, 'files', s.imagePath)), { recursive: true });
    fs.copyFileSync(path.join(root, s.imagePath), path.join(out, 'files', s.imagePath));
  }
  const page = fill(template, {
    titleText: escapeHtml(u.name),
    descriptionText: escapeHtml(s ? s.tagline : stripTags(u.whatHtml)),
    iconSprite: sprite, repoUrl, siteUrl, pageUrl: `${siteUrl}${u.folder}/`, readmeUrl: links.readme,
    body: s ? fullBody(u, s, links, i) : basicBody(u, links, i),
  });
  fs.mkdirSync(path.join(out, u.folder), { recursive: true });
  fs.writeFileSync(path.join(out, u.folder, 'index.html'), page);
  pages.push(s ? 'full' : 'basic');
}

const cards = useCases.map((u) => `        <li data-kind="${u.kind}"><article class="repo">
          <div class="name"><svg class="ico"><use href="#i-book"/></svg><a href="${u.folder}/">${u.folder}</a><span class="pill">${u.kind === 'run' ? 'Runnable' : 'Blueprint'}</span></div>
          <p>${u.site ? txt(u.site.tagline) : u.whatHtml}</p>
          <div class="foot"><span class="agent${u.agent === 'Azure SRE Agent' ? '' : ' alt'}">${u.agent}</span><span class="mono">#${u.number}</span><span>${u.owners.join(', ')}</span></div>
        </article></li>`).join('\n');
const counts = { all: useCases.length, run: useCases.filter((u) => u.kind === 'run').length };
counts.blue = counts.all - counts.run;
landing = landing
  .replace(/(<!-- usecases:start -->\n)[\s\S]*?(<!-- usecases:end -->)/, `$1${cards}\n$2`)
  .replace(/(<span[^>]*data-uc="(all|run|blue)"[^>]*>)\d+(<\/span>)/g, (_, open, k, close) => `${open}${counts[k]}${close}`)
  .replaceAll('https://github.com/rbrunois/agentic-itops-showcase', repoUrl)
  .replaceAll('https://rbrunois.github.io/agentic-itops-showcase/', siteUrl);
fs.writeFileSync(landingPath, landing);

const full = pages.filter((p) => p === 'full').length;
console.log(`Built ${useCases.length} use case pages into ${path.relative(root, out)}/: ${full} from site.yml, ${useCases.length - full} basic (${counts.run} runnable, ${counts.blue} blueprint).`);
