// Checks the review panel: renders items, submits only ticked items with edited
// text to submissions/round-<n>, locks a submitted round, approves on a second click.
// Run from a directory that has jsdom installed (npm install jsdom in a scratch dir):
//   node /path/to/test_review_panel.mjs
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const { JSDOM } = createRequire(join(process.cwd(), '/'))('jsdom');
const here = dirname(fileURLToPath(import.meta.url));
const panel = readFileSync(join(here, 'review-panel.html'), 'utf8');

const items = {
  pr: 'sohonet/cvr-client#600',
  items: [
    { id: 'r1-1', round: 1, severity: 'should-fix', path: 'src/a.ts', line: 10, body: 'first comment' },
    { id: 'r1-2', round: 1, severity: 'nit', path: 'src/b.ts', line: 20, body: 'second comment' },
  ],
};

const writes = {};
const listeners = {};
const fakeDb = {
  doc(path) {
    return {
      path,
      async set(data) { writes[path] = data; },
      onSnapshot(next) { listeners[path] = next; next({ exists: false, data: () => undefined }); return () => {}; },
    };
  },
  collection(path) {
    return {
      onSnapshot(next) { listeners[path] = next; next({ docs: [], empty: true }); return () => {}; },
    };
  },
};

const html = `<!doctype html><html><body>${panel.replace('__REVIEW_ITEMS__', JSON.stringify(items))}</body></html>`;
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  url: 'https://example.test/',
  beforeParse(window) {
    window.claude = { use: async (name) => (name === 'db' ? fakeDb : null) };
  },
});
const { document } = dom.window;
const tick = () => new Promise((r) => setTimeout(r, 20));
await tick();

const rows = document.querySelectorAll('.rp-item');
assert.equal(rows.length, 2, 'renders one row per item');

rows[1].querySelector('input[type=checkbox]').click();
const ta = rows[0].querySelector('textarea');
ta.value = 'first comment, edited';
ta.dispatchEvent(new dom.window.Event('input', { bubbles: true }));

document.querySelector('[data-submit-round="1"]').click();
await tick();
// Objects built inside the jsdom realm have a different prototype, so compare as plain JSON.
assert.deepEqual(JSON.parse(JSON.stringify(writes['submissions/round-1'].comments)), [
  { id: 'r1-1', path: 'src/a.ts', line: 10, body: 'first comment, edited', reply_to: null },
], 'submits only ticked items with the edited text');
assert.ok(writes['submissions/round-1'].submitted_at, 'stamps the submission');

listeners['submissions']({ docs: [{ id: 'round-1', data: () => writes['submissions/round-1'] }], empty: false });
await tick();
assert.ok(rows[0].querySelector('textarea').disabled, 'locks a submitted round');
assert.equal(document.querySelector('[data-submit-round="1"]'), null, 'removes the submit button once submitted');

const approve = document.querySelector('#rp-approve');
approve.click();
assert.equal(writes['review/approval'], undefined, 'first click only arms approve');
approve.click();
await tick();
assert.equal(writes['review/approval'].approve, true, 'second click writes the approval');

console.log('review panel ok');
