import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { pingChosen, renderConceptSeed } from '../scripts/concept-seed.mjs';
import { renderTemplate } from '../scripts/hook-lib.mjs';
import { filterDetectionFindings } from '../scripts/lib/impeccable-config.mjs';
import { isGeneratedFile } from '../scripts/lib/is-generated.mjs';
import {
  LIVE_BROWSER_SCRIPT_PARTS,
  assembleLiveBrowserScript,
} from '../scripts/live/browser-script-parts.mjs';
import {
  LIVE_CHROME_MOUNT_CONTRACT,
  LIVE_UI_COMPONENT_IDS,
  LIVE_UI_SURFACES,
} from '../scripts/live/ui-surfaces.mjs';

const skillRoot = path.resolve(import.meta.dirname, '..');
const questionScript = path.join(skillRoot, 'scripts', 'serve-question.mjs');

test('concept registers are reproducible and fail closed on invalid use', async () => {
  const options = {
    scope: 'direction',
    key: 'deadbeef',
    reroll: 1,
    register: 'safer',
    _resolvedData: null,
  };
  const safer = await renderConceptSeed(options);
  assert.equal(safer, await renderConceptSeed(options));
  assert.match(safer, /SAFER REGISTER/);
  assert.doesNotMatch(safer, /ASSIGNED INDEX:/);

  const bolder = await renderConceptSeed({ ...options, register: 'bolder' });
  assert.match(bolder, /BOLDER REGISTER UNAVAILABLE/);
  assert.match(bolder, /ASSIGNED INDEX:/);

  assert.throws(
    () => renderConceptSeed({ ...options, register: 'middle' }),
    /must be safer or bolder/,
  );
  assert.throws(
    () => renderConceptSeed({ ...options, reroll: 0 }),
    /steers a re-roll round/,
  );
});

test('choice telemetry accepts every documented kind without leaking grounded labels', async () => {
  const priorFetch = globalThis.fetch;
  const bodies = [];
  globalThis.fetch = async (_url, init) => {
    bodies.push(JSON.parse(init.body));
    return { ok: true };
  };
  try {
    for (const kind of ['assigned', 'pick', 'canon']) {
      assert.equal(await pingChosen({ kind, key: 'deadbeef', scope: 'direction' }), true);
    }
    assert.equal(await pingChosen({
      kind: 'challenger',
      chosenId: 'catalog-world',
      register: 'bolder',
      key: 'deadbeef',
      scope: 'direction',
    }), true);
    assert.equal(await pingChosen({ kind: 'unknown', key: 'deadbeef', scope: 'direction' }), false);
  } finally {
    globalThis.fetch = priorFetch;
  }

  assert.deepEqual(bodies.map((body) => body.kind), ['assigned', 'pick', 'canon', 'challenger']);
  assert.equal(bodies[0].chosenId, undefined);
  assert.equal(bodies[3].chosenId, 'catalog-world');
  assert.equal(bodies[3].register, 'bolder');
});

test('question schema enumerates register rerolls and the follow-up lifecycle', () => {
  const output = execFileSync(process.execPath, [questionScript, '--schema'], { encoding: 'utf8' });
  const [json] = output.split('\n\nOption ids return verbatim');
  const schema = JSON.parse(json);
  assert.deepEqual(schema.reroll.registers, ['safer', 'bolder']);
  assert.equal(schema.followup, true);
});

test('detached questions keep the table for a follow-up and close after the terminal pick', async () => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'impeccable-question-'));
  const firstPayload = path.join(cwd, 'first.json');
  const secondPayload = path.join(cwd, 'second.json');
  fs.writeFileSync(firstPayload, JSON.stringify({
    title: 'First round',
    question: 'Choose a direction',
    options: [{ id: 'assigned', label: 'Assigned direction' }],
    followup: true,
  }));
  fs.writeFileSync(secondPayload, JSON.stringify({
    title: 'Second round',
    question: 'Choose an execution contract',
    options: [{ id: 'contract', label: 'Execution contract' }],
  }));

  let key = null;
  try {
    const started = execFileSync(process.execPath, [
      questionScript, '--start', '--no-open', '--payload', firstPayload,
    ], { cwd, encoding: 'utf8' });
    key = started.match(/^QUESTION KEY: (.+)$/m)?.[1]?.trim();
    const url = started.match(/^QUESTION URL: (.+)$/m)?.[1]?.trim();
    assert.ok(key && url, started);

    await fetch(`${url}answer`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ optionId: 'assigned' }),
    });
    const firstAnswer = execFileSync(process.execPath, [questionScript, '--wait', '--key', key], {
      cwd,
      encoding: 'utf8',
    });
    assert.match(firstAnswer, /"optionId":"assigned"/);
    assert.match(firstAnswer, /"followup":true/);

    execFileSync(process.execPath, [questionScript, '--update', '--key', key, '--payload', secondPayload], {
      cwd,
      encoding: 'utf8',
    });
    const refreshed = await fetch(url).then((response) => response.text());
    assert.match(refreshed, /Execution contract/);

    await fetch(`${url}answer`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ optionId: 'contract' }),
    });
    const secondAnswer = execFileSync(process.execPath, [questionScript, '--wait', '--key', key], {
      cwd,
      encoding: 'utf8',
    });
    assert.match(secondAnswer, /"optionId":"contract"/);
    assert.doesNotMatch(secondAnswer, /"followup":true/);
    key = null;
  } finally {
    if (key) {
      try {
        execFileSync(process.execPath, [questionScript, '--stop', '--key', key], { cwd, stdio: 'ignore' });
      } catch { /* best-effort fixture cleanup */ }
    }
  }
});

test('CSS color ignores compare equivalent syntaxes', () => {
  const finding = [{ antipattern: 'design-system-color', value: 'hsl(0.5turn 100% 50% / 50%)' }];
  const config = { ignoreValues: [{ rule: 'design-system-color', value: '#00ffff80' }] };
  assert.deepEqual(filterDetectionFindings(finding, config), []);
  assert.equal(filterDetectionFindings(finding, {
    ignoreValues: [{ rule: 'design-system-color', value: 'rgb(255 0 255)' }],
  }).length, 1);
});

test('hook suggestions single-quote hostile POSIX shell values', () => {
  const output = renderTemplate([{
    antipattern: 'design-system-font',
    value: "$(touch pwned) O'Brien",
    name: 'Unapproved font',
    description: 'Use an approved family.',
  }], 'src/example.css', null, { cwd: process.cwd() });
  assert.match(output, /'\$\(touch pwned\) O'\\''Brien'/);
  assert.doesNotMatch(output, /"\$\(touch pwned\)/);
});

test('generated-file checks pass hostile filenames to git without a shell', () => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'impeccable-generated-'));
  execFileSync('git', ['init', '--quiet'], { cwd });
  const hostile = path.join(cwd, '$(touch pwned).js');
  fs.writeFileSync(hostile, 'export const safe = true;\n');
  assert.equal(isGeneratedFile(hostile, { cwd }), false);
  assert.equal(fs.existsSync(path.join(cwd, 'pwned')), false);
});

test('Live browser assembly injects the canonical UI inventory', () => {
  const parts = LIVE_BROWSER_SCRIPT_PARTS.map((part) => ({ ...part, source: `/* ${part.name} */` }));
  const script = assembleLiveBrowserScript({
    token: 'fixture-token',
    port: 1234,
    vocabulary: [],
    appRoot: '/fixture/app',
    parts,
  });
  assert.match(script, /window\.__IMPECCABLE_LIVE_UI_SURFACES__/);
  assert.match(script, /window\.__IMPECCABLE_LIVE_MOUNT_CONTRACT__/);
  for (const surface of LIVE_UI_SURFACES) assert.match(script, new RegExp(surface.key));
  for (const part of LIVE_BROWSER_SCRIPT_PARTS) assert.match(script, new RegExp(part.name));
  assert.equal(new Set(LIVE_UI_COMPONENT_IDS).size, LIVE_UI_COMPONENT_IDS.length);
  assert.deepEqual(LIVE_CHROME_MOUNT_CONTRACT, ['root', 'transport', 'state', 'actions']);
});
