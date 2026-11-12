import { test } from "node:test";
import assert from "node:assert/strict";
import { AGENT as PERSONAL_AGENT, GRAPH as PERSONAL_GRAPH } from "./config.mts";
import { MERGE, SUBTASKS, TRACKER } from "./config.mts";
import { disallowedModels, piAnalysisArgs, piEnvFor, subscriptionPreflight, ticketModel } from "./models.mts";

// Run: node --test .sandcastle/models.test.mts

const SONNET = "pi-claude-subscription/claude-sonnet-5-5";
const OPUS = "pi-claude-subscription/claude-opus-5-5";
const labels = { "model:sonnet": SONNET, "model:opus": OPUS };

test("ticket model: exactly one model label selects the subscription model", () => {
  assert.deepEqual(ticketModel(["ready-for-agent", "model:sonnet"], labels, "x"), { model: SONNET });
  assert.deepEqual(ticketModel(["model:opus"], labels, "x"), { model: OPUS });
  assert.ok("error" in ticketModel(["ready-for-agent"], labels, "x"), "no label: not started, no GPT fallback");
  assert.ok("error" in ticketModel(["model:sonnet", "model:opus"], labels, "x"));
  assert.ok("error" in ticketModel(["model:sol"], labels, "x"), "an unconfigured label is not a model label");
  assert.deepEqual(ticketModel([], {}, "fixed"), { model: "fixed" }, "no model labels configured: the fixed model");
});

test("only the labelled models may be configured", () => {
  assert.equal(disallowedModels(labels, [SONNET, OPUS]), undefined);
  assert.match(disallowedModels(labels, [OPUS, "openai/gpt-5.5"]) ?? "", /gpt-5\.5/);
  assert.equal(disallowedModels({}, ["anything"]), undefined);
});

test("personal reference config: labels, verifier and analysis models, provider", () => {
  assert.deepEqual(PERSONAL_AGENT.modelLabels, labels);
  assert.equal(PERSONAL_AGENT.model, OPUS);
  assert.equal(PERSONAL_GRAPH.model, SONNET);
  assert.equal(PERSONAL_AGENT.provider, "pi");
  assert.equal(disallowedModels(PERSONAL_AGENT.modelLabels, [PERSONAL_AGENT.model, PERSONAL_GRAPH.model]), undefined);
  assert.match(disallowedModels(PERSONAL_AGENT.modelLabels, ["openai/gpt-6.1-sol", PERSONAL_GRAPH.model]) ?? "", /gpt-6\.1-sol/, "a stray fixed model is rejected");
});

test("Convoke uses GitHub sub-issues and automatic squash merge", () => {
  assert.equal(TRACKER.kind, "github");
  assert.equal(TRACKER.project, "markdlabrecque/convoke");
  assert.equal(SUBTASKS.enabled, true);
  assert.equal(MERGE.auto, true);
  assert.equal(MERGE.method, "squash");
});

test("container env: subscription models need no OpenAI credential; openai models still mint one", () => {
  const mint = () => {
    throw new Error("must not ask for an OpenAI credential");
  };
  assert.deepEqual(piEnvFor(SONNET, mint), {});
  assert.deepEqual(piEnvFor(OPUS, mint), {});
  assert.deepEqual(piEnvFor("openai/gpt-6.1-sol", () => "tok"), { OPENAI_API_KEY: "tok" });
});

test("host analysis loads only the provider extension, explicitly", () => {
  const env = { HOME: "/h" };
  const args = piAnalysisArgs(SONNET, env, () => true);
  assert.ok(args.includes("--no-extensions"));
  assert.deepEqual(args.slice(args.indexOf("-e")), ["-e", "/h/.pi/agent/extensions/pi-claude-subscription/index.ts"]);
  assert.deepEqual(args.slice(args.indexOf("--model"), args.indexOf("--model") + 2), ["--model", SONNET]);
  assert.equal(piAnalysisArgs(SONNET, { HOME: "/h", FACTORY_PI_SUBSCRIPTION_EXTENSION: "/x/index.ts" }, () => true).at(-1), "/x/index.ts");
  assert.throws(() => piAnalysisArgs(SONNET, env, () => false), /extension not found/);
  assert.ok(!piAnalysisArgs("openai/gpt-6.1-sol", env, () => false).includes("-e"));
});

test("subscription preflight checks claude and the provider, never OpenAI or a credential", () => {
  const calls: string[] = [];
  const run = (cmd: string, args: string[]) => {
    calls.push([cmd, ...args].join(" "));
    if (cmd === "claude") return '{ "loggedIn": true }';
    return "provider model\npi-claude-subscription claude-sonnet-5-5\npi-claude-subscription claude-opus-5-5\n";
  };
  const base = { models: [SONNET, OPUS, OPUS], env: { HOME: "/h" }, exists: () => true };
  assert.deepEqual(subscriptionPreflight({ ...base, run }), []);
  assert.ok(calls.every((c) => !/openai|token|api-key/i.test(c)), calls.join("\n"));
  assert.deepEqual(subscriptionPreflight({ ...base, models: ["openai/gpt-6.1-sol"], run: () => { throw new Error("unused"); } }), []);
  assert.match(subscriptionPreflight({ ...base, exists: () => false, run })[0], /extension not found/);
  const loggedOut = (cmd: string, args: string[]) => (cmd === "claude" ? '{ "loggedIn": false }' : run(cmd, args));
  assert.match(subscriptionPreflight({ ...base, run: loggedOut }).join("\n"), /claude auth login/);
  const noOpus = (cmd: string, args: string[]) => (cmd === "claude" ? run(cmd, args) : "pi-claude-subscription claude-sonnet-5-5");
  assert.match(subscriptionPreflight({ ...base, run: noOpus }).join("\n"), /claude-opus-5-5/);
});
