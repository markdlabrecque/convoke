#!/usr/bin/env node
// Capture screenshots + a video of a flow, headless Chromium.
// node /opt/sandcastle/evidence.cjs --label before|after --steps steps.cjs --out /home/agent/evidence/<iid>
// steps.cjs: module.exports = async ({ page, shot, login, baseUrl }) => { await page.goto(baseUrl + '/x'); await shot('name'); };
// Writes <out>/<label>-<name>.png (full page) and <out>/<label>.webm. Same viewport every run so before/after compare.
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith('--') ? [...a, [v.slice(2), all[i + 1]]] : a), []));
for (const k of ['label', 'steps', 'out']) if (!args[k]) { console.error(`missing --${k}`); process.exit(2); }
const { chromium } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'));
const baseUrl = process.env.BASE_URL || 'http://127.0.0.1';

(async () => {
  fs.mkdirSync(args.out, { recursive: true });
  const tmp = path.join(args.out, `.video-${args.label}`);
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, recordVideo: { dir: tmp, size: { width: 1280, height: 800 } } });
  const page = await context.newPage();
  const shot = async (name) => { await page.screenshot({ path: path.join(args.out, `${args.label}-${name}.png`), fullPage: true }); };
  const login = async () => {
    const url = execSync(`vendor/bin/drush user:login --uri=${baseUrl} --no-browser`, { cwd: '/home/agent/workspace' }).toString().trim();
    await page.goto(url);
  };
  let failed = null;
  try { await require(path.resolve(args.steps))({ page, shot, login, baseUrl }); } catch (e) { failed = e; await shot('error').catch(() => {}); }
  const video = page.video();
  await context.close();
  if (video) fs.renameSync(await video.path(), path.join(args.out, `${args.label}.webm`));
  fs.rmSync(tmp, { recursive: true, force: true });
  await browser.close();
  if (failed) { console.error(failed); process.exit(1); }
})();
