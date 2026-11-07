import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Run-state store + shared board/evidence page with sticky navigation and a Settings panel (design + light/dark/system mode).
// Writers (main.mts) call setStage(); each call writes <stateDir>/<key>.json and regenerates
// .sandcastle/board.html (data embedded, reloads itself every 10s, opens from disk). The always-on service
// (board-server.mts) serves the same page over HTTP from the same state dir.
// stateDir: $SANDCASTLE_STATE_DIR, else .sandcastle/state in the current repo. Set the variable to
// one shared folder (the service's) so a single board shows runs from every project and worktree.

export type Stage = "queued" | "waiting" | "setup" | "implementing" | "verifying" | "posting" | "pushing" | "ci" | "done" | "stopped";
export const TERMINAL: Stage[] = ["done", "stopped"];
// Not running and not finished: the dispatcher re-evaluates these every pass. "queued" = not started
// (the note says why), "waiting" = the implementer reported a blocker. Neither counts against capacity.
export const PARKED: Stage[] = ["queued", "waiting"];

export interface RunState {
  iid: string;
  project?: string;
  title?: string;
  ticketUrl?: string;
  branch?: string;
  base?: string;
  stage: Stage;
  stageSince: string;
  startedAt: string;
  updatedAt: string;
  pid: number;
  verdict?: string;
  mr?: string;
  note?: string;
  evidenceDir?: string;
  ticketHash?: string; // content hash of the ticket the run was built from
  parentIid?: string; // set when the ticket is a GitLab Task; the Task is closed once its branch merges
  mergedAt?: string; // when the dispatcher saw the MR merged and closed the Task or moved the ticket on
}

export interface BoardRun extends RunState {
  key: string;
  evidenceUrl?: string;
}

const expand = (p: string) => (p.startsWith("~/") ? resolve(homedir(), p.slice(2)) : resolve(p));
export const stateDir = () => expand(process.env.SANDCASTLE_STATE_DIR || ".sandcastle/state");
const boardFile = () => resolve(".sandcastle/board.html");
const templateFile = resolve(dirname(fileURLToPath(import.meta.url)), "board.template.html");
const now = () => new Date().toISOString();

let project: string | undefined;
/** Name this process's runs by project so one shared board can tell repos apart. */
export function setProject(name: string): void {
  project = name;
}
export const keyFor = (iid: string, proj?: string) => (proj ? `${proj.replace(/[^A-Za-z0-9._-]+/g, "_")}--${iid}` : iid);

function write(file: string, text: string) {
  const tmp = `${file}.${process.pid}.tmp`;
  writeFileSync(tmp, text);
  renameSync(tmp, file);
}

function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export function setStage(iid: string, patch: Partial<RunState>): void {
  mkdirSync(stateDir(), { recursive: true });
  const file = resolve(stateDir(), `${keyFor(iid, project)}.json`);
  let cur: Partial<RunState> = {};
  if (existsSync(file)) {
    try {
      cur = JSON.parse(readFileSync(file, "utf8"));
    } catch {
      /* corrupt or mid-write: start fresh */
    }
  }
  const stageChanged = patch.stage && patch.stage !== cur.stage;
  const next = {
    startedAt: now(),
    ...cur,
    ...patch,
    iid,
    project,
    pid: process.pid,
    updatedAt: now(),
    stageSince: stageChanged || !cur.stageSince ? now() : cur.stageSince,
  } as RunState;
  write(file, JSON.stringify(next, null, 2));
  renderBoard();
}

/** Delete a run record (the dispatcher clears parked records for tickets that left the queue). */
export function removeRun(iid: string): void {
  rmSync(resolve(stateDir(), `${keyFor(iid, project)}.json`), { force: true });
  renderBoard();
}

/** Read every run. A run whose process is gone without a terminal stage crashed: mark it washed away. */
export function readRuns(): BoardRun[] {
  if (!existsSync(stateDir())) return [];
  const runs: BoardRun[] = [];
  for (const f of readdirSync(stateDir()).filter((n) => n.endsWith(".json"))) {
    try {
      const file = resolve(stateDir(), f);
      const s: RunState = JSON.parse(readFileSync(file, "utf8"));
      if (!TERMINAL.includes(s.stage) && !PARKED.includes(s.stage) && s.pid !== process.pid && !alive(s.pid)) {
        s.note = `process ${s.pid} exited without finishing (last stage: ${s.stage})`;
        s.stage = "stopped";
        s.stageSince = now();
        write(file, JSON.stringify(s, null, 2));
      }
      runs.push({ ...s, key: f.replace(/\.json$/, "") });
    } catch {
      /* skip unreadable file */
    }
  }
  return runs.sort((a, b) => a.startedAt.localeCompare(b.startedAt));
}

/** Build the page. mode "http" links evidence through the service's /evidence route; "file" links the folder directly. */
export function buildPage(mode: "file" | "http"): string {
  const runs = readRuns().map((r) => ({
    ...r,
    evidenceUrl: !r.evidenceDir ? undefined : mode === "http" ? `/evidence/${encodeURIComponent(r.key)}/` : `file://${r.evidenceDir}/`,
  }));
  const data = JSON.stringify({ runs, generatedAt: now() }).replace(/</g, "\\u003c");
  return readFileSync(templateFile, "utf8").replace("/*__DATA__*/null", data);
}

/** Render evidence using the board's shell. Evidence never auto-refreshes while media is playing. */
export function buildEvidencePage(run: BoardRun, files: { name: string; kind: string; url: string; text?: string; truncated?: boolean }[]): string {
  const data = JSON.stringify({ evidence: { run, files, url: `/evidence/${encodeURIComponent(run.key)}/` } }).replace(/</g, "\\u003c");
  return readFileSync(templateFile, "utf8")
    .replace('<meta name="sandcastle-refresh" content="10">', '')
    .replace("/*__DATA__*/null", data);
}

export function renderBoard(): void {
  mkdirSync(dirname(boardFile()), { recursive: true });
  write(boardFile(), buildPage("file"));
}
