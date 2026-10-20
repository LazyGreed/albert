import assert from "node:assert/strict";
import { execFile as execFileCallback } from "node:child_process";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer, type ServerResponse } from "node:http";
import { homedir, tmpdir } from "node:os";
import { join, relative } from "node:path";
import { afterEach, test } from "node:test";
import { promisify } from "node:util";

const execFile = promisify(execFileCallback);

import type {
  ExtensionAPI,
  ExtensionContext,
  ExtensionToolContext,
  ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import { Check } from "typebox/value";
import { judge, MAX_REQUEST_BYTES } from "../dist/core/client.js";
import { resolveConfig } from "../dist/core/config.js";
import { evaluateDiff } from "../dist/core/diff.js";
import {
  compactAnswer,
  evaluate,
  type Questions,
} from "../dist/core/evaluate.js";
import { evaluateFiles } from "../dist/core/files.js";
import { CONCURRENCY, MAX_FILE_BYTES, search } from "../dist/core/search.js";
import kJev, {
  evaluateDiffOutputSchema,
  evaluateFilesOutputSchema,
  evaluateOutputSchema,
  searchOutputSchema,
} from "../dist/pi.js";

const cleanups: (() => Promise<void>)[] = [];
afterEach(async () => {
  await Promise.all(cleanups.splice(0).map((cleanup) => cleanup()));
});
const env = {
  PI_JEV_BASE_URL: "http://127.0.0.1:1234/custom/decisions",
  PI_JEV_MODEL: "custom/decision-model",
  PI_JEV_API_KEY: "placeholder",
};
const questions: Questions = {
  match: {
    type: "noul",
    instructions: "Does this implement credential rotation?",
    criteria: {
      true: "Implements rotation",
      false: "Does not implement rotation",
    },
  },
};
type Payload = { model: string; state: unknown; questions: Questions };
type Handler = (
  payload: Payload,
  response: ServerResponse,
) => void | Promise<void>;
const send = (response: ServerResponse, data: unknown) => {
  response.setHeader("Content-Type", "application/json");
  response.end(JSON.stringify(data));
};
const noulResponse = (probability = 0.9) => ({
  answers: { match: { type: "noul", noul: probability } },
  usage: { input_tokens: 10, output_tokens: 2, cost: 0.01 },
});
async function endpoint(handler: Handler, unauthenticated = false) {
  const server = createServer(async (request, response) => {
    try {
      assert.equal(request.method, "POST");
      assert.equal(request.url, "/custom/decisions");
      if (!unauthenticated)
        assert.equal(request.headers.authorization, "Bearer placeholder");
      let text = "";
      for await (const chunk of request) text += chunk;
      await handler(JSON.parse(text), response);
    } catch {
      response.statusCode = 500;
      response.end();
    }
  });
  await new Promise<void>((done) => server.listen(0, "127.0.0.1", done));
  const address = server.address();
  assert.ok(address && typeof address === "object");
  cleanups.push(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
  });
  return resolveConfig({
    ...env,
    PI_JEV_BASE_URL: `http://127.0.0.1:${address.port}/custom/decisions`,
  });
}
async function candidates(
  count = 1,
  content = "export function rotateCredentials() {}",
) {
  const cwd = await mkdtemp(join(tmpdir(), "k-jev-"));
  cleanups.push(() => rm(cwd, { recursive: true, force: true }));
  const paths = Array.from({ length: count }, (_, i) => `file-${i}.ts`);
  await Promise.all(paths.map((path) => writeFile(join(cwd, path), content)));
  return { cwd, paths };
}
const delay = (ms: number) => new Promise((done) => setTimeout(done, ms));

test("env-only resolution preserves custom endpoint/model and trims exports", () => {
  assert.deepEqual(
    resolveConfig({ ...env, PI_JEV_MODEL: ` ${env.PI_JEV_MODEL} ` }),
    {
      baseUrl: env.PI_JEV_BASE_URL,
      model: env.PI_JEV_MODEL,
      apiKey: env.PI_JEV_API_KEY,
    },
  );
});

test("all three variables required, including API key for local endpoints", () => {
  for (const name of Object.keys(env)) {
    for (const value of [undefined, "", "   "]) {
      assert.throws(
        () => resolveConfig({ ...env, [name]: value }),
        new RegExp(`${name.replace(/^PI_/, "K_")} is required`),
      );
    }
  }
});

test("invalid configuration errors never contain secret values", () => {
  for (const url of [
    "not-a-url",
    "file:///tmp/a",
    "http://user:SECRET@example.org/",
    "https://example.org/#SECRET",
  ]) {
    assert.throws(
      () => resolveConfig({ ...env, PI_JEV_BASE_URL: url }),
      (error: Error) => !error.message.includes("SECRET"),
    );
  }
  assert.throws(
    () => resolveConfig({ ...env, PI_JEV_API_KEY: "SECRET\nBAD" }),
    /K_JEV_API_KEY must/,
  );
  assert.throws(
    () => resolveConfig({ ...env, PI_JEV_MODEL: "bad\nmodel" }),
    /K_JEV_MODEL is invalid/,
  );
});

test("unauthenticated local endpoint accepts a mandatory placeholder key", async () => {
  const config = await endpoint(
    (_payload, response) => send(response, noulResponse()),
    true,
  );
  const result = await evaluate({ state: "anything", questions }, config);
  assert.deepEqual(result.answers.match, {
    type: "noul",
    answer: true,
    probability: 0.9,
  });
});

test("jev_evaluate sends arbitrary JSON, custom model, and typed questions; projects compact results", async () => {
  const typed: Questions = {
    ...questions,
    route: {
      type: "choice",
      instructions: "Classify failure",
      criteria: { auth: "Authentication", network: "Network" },
    },
    rubric: {
      type: "score",
      instructions: "Rate severity",
      criteria: ["Minor", "Major", "Blocking"],
    },
  };
  const state = [{ status: 401 }, "Unauthorized", null, 4, false];
  const config = await endpoint((payload, response) => {
    assert.equal(payload.model, env.PI_JEV_MODEL);
    assert.deepEqual(payload.state, state);
    assert.deepEqual(payload.questions, typed);
    send(response, {
      answers: {
        match: {
          type: "noul",
          noul: 0.1,
          confidence: 0.8,
          explanation: "SECRET",
        },
        route: {
          type: "choice",
          choice: "auth",
          confidence: 0.8,
          probabilities: { auth: 0.9, network: 0.1 },
          explanation: "SECRET",
        },
        rubric: {
          type: "score",
          score: 1.75,
          confidence: 0.7,
          probabilities: { "0": 0, "1": 0.25, "2": 0.75 },
          legend: { "2": "SECRET" },
        },
        extra: "SECRET",
      },
      usage: { input_tokens: 12, output_tokens: 5, cost: 0.003 },
    });
  });
  const { answers, usage } = await evaluate(
    { state, questions: typed },
    config,
  );
  assert.equal(answers.match.answer, false);
  assert.equal(answers.route.answer, "auth");
  assert.equal(answers.rubric.answer, 1.75);
  assert.equal((usage?.inputTokens ?? 0) + (usage?.outputTokens ?? 0), 17);
  assert.equal(usage?.cost, 0.003);
  assert.ok(Check(evaluateOutputSchema, { answers }));
  assert.ok(!JSON.stringify(answers).includes("SECRET"));
});

test("invalid questions and oversized/non-serializable states fail before network", async () => {
  const config = resolveConfig(env);
  await assert.rejects(
    evaluate({ state: null, questions: {} }, config),
    /Invalid questions/,
  );
  await assert.rejects(
    evaluate(
      {
        state: null,
        questions: {
          bad: { type: "choice", instructions: "?", criteria: { only: "One" } },
        },
      },
      config,
    ),
    /Invalid questions/,
  );
  await assert.rejects(
    evaluate({ state: "x".repeat(MAX_REQUEST_BYTES), questions }, config),
    /exceeds 1 MiB/,
  );
  const circular: Record<string, unknown> = {};
  circular.self = circular;
  await assert.rejects(
    evaluate({ state: circular, questions }, config),
    /JSON-serializable/,
  );
});

test("single-file search reads internally and returns no file/provider prose", async () => {
  const sentinel = "PRIVATE_FILE_CONTENT_SENTINEL";
  const { cwd, paths } = await candidates(1, sentinel);
  const config = await endpoint((payload, response) => {
    assert.deepEqual(payload.state, { path: paths[0], content: sentinel });
    send(response, {
      answers: {
        match: {
          type: "noul",
          noul: 0.95,
          explanation: sentinel,
          content: sentinel,
        },
      },
      state: sentinel,
    });
  });
  const result = await search(
    { paths, question: "Does it rotate credentials?" },
    config,
    cwd,
  );
  assert.deepEqual(result.results, [
    {
      path: paths[0],
      result: { type: "noul", answer: true, probability: 0.95 },
    },
  ]);
  assert.ok(!JSON.stringify(result).includes(sentinel));
  assert.ok(Check(searchOutputSchema, { results: result.results }));
});

test("50-file search is parallel, bounded to four workers, and ordered despite completion order", async () => {
  const { cwd, paths } = await candidates(50);
  let active = 0;
  let peak = 0;
  const completions: string[] = [];
  const config = await endpoint(async (payload, response) => {
    const { path } = payload.state as { path: string };
    active++;
    peak = Math.max(peak, active);
    await delay(path === paths[0] ? 100 : 10);
    active--;
    completions.push(path);
    send(response, noulResponse());
  });
  const result = await search(
    { paths, question: "Does this rotate credentials?" },
    config,
    cwd,
  );
  assert.equal(peak, CONCURRENCY);
  assert.notEqual(completions[0], paths[0]);
  assert.deepEqual(
    result.results.map((r) => r.path),
    paths,
  );
  assert.equal(result.results.filter((r) => "result" in r).length, 50);
  assert.equal(result.usage?.inputTokens, 500);
  assert.ok(Math.abs((result.usage?.cost ?? 0) - 0.5) < 1e-10);
});

test("unrestricted core preserves Pi absolute and home-expanded paths outside cwd", async () => {
  const { cwd, paths } = await candidates();
  const config = await endpoint((_payload, response) =>
    send(response, noulResponse()),
  );
  const candidatesPaths = [
    join(cwd, paths[0]),
    `~/${relative(homedir(), join(cwd, paths[0]))}`,
  ];
  const result = await search(
    { paths: candidatesPaths, question: "Relevant?" },
    config,
    "/",
  );
  assert.deepEqual(
    result.results.map((item) => item.path),
    candidatesPaths,
  );
  assert.ok(result.results.every((item) => "result" in item));
});

test("partial file and API failures do not fail the batch or leak error bodies", async () => {
  const { cwd, paths } = await candidates(2);
  const config = await endpoint((payload, response) => {
    const { path } = payload.state as { path: string };
    if (path === paths[1]) {
      response.statusCode = 500;
      response.end("PRIVATE_FILE_CONTENT_SENTINEL placeholder");
    } else send(response, noulResponse());
  });
  const result = await search(
    { paths: [paths[0], "missing.ts", paths[1]], question: "Relevant?" },
    config,
    cwd,
  );
  assert.ok("result" in result.results[0]);
  assert.match(
    (result.results[1] as { error: string }).error,
    /File not found/,
  );
  assert.match((result.results[2] as { error: string }).error, /HTTP 500/);
  assert.ok(!JSON.stringify(result).includes("PRIVATE_FILE_CONTENT_SENTINEL"));
});

test("directories, binary, invalid UTF-8, and oversized files are per-file failures", async () => {
  const { cwd } = await candidates(0);
  await writeFile(join(cwd, "binary"), Buffer.from([0, 1]));
  await writeFile(join(cwd, "utf8"), Buffer.from([0xff]));
  await writeFile(join(cwd, "large"), "x".repeat(MAX_FILE_BYTES + 1));
  const result = await search(
    { paths: [".", "binary", "utf8", "large"], question: "Relevant?" },
    resolveConfig(env),
    cwd,
  );
  assert.equal(result.results.filter((r) => "error" in r).length, 4);
  await assert.rejects(
    search({ paths: [], question: "?" }, resolveConfig(env), cwd),
    /1-200 paths/,
  );
});

test("HTTP failures are useful but never expose upstream body or API key", async () => {
  for (const status of [400, 401, 403, 404, 429, 500]) {
    const config = await endpoint((_payload, response) => {
      response.statusCode = status;
      response.end("PRIVATE_FILE_CONTENT_SENTINEL placeholder");
    });
    await assert.rejects(
      evaluate({ state: "secret", questions }, config),
      (error: Error) => {
        assert.match(error.message, new RegExp(`HTTP ${status}`));
        assert.ok(!error.message.includes("PRIVATE_FILE_CONTENT_SENTINEL"));
        assert.ok(!error.message.includes("placeholder"));
        return true;
      },
    );
  }
});

test("timeouts cover headers and body; network failures and cancellation are sanitized", async () => {
  for (const headersFirst of [false, true]) {
    const config = await endpoint((_payload, response) => {
      if (headersFirst) {
        response.writeHead(200);
        response.write('{"answers":');
      }
      // Deliberately never finish the response.
    });
    await assert.rejects(
      judge(config, "secret", questions, undefined, 40),
      /timed out/,
    );
  }
  const config = await endpoint((_payload, response) =>
    send(response, noulResponse()),
  );
  const controller = new AbortController();
  controller.abort(new Error("PRIVATE_FILE_CONTENT_SENTINEL"));
  await assert.rejects(
    evaluate({ state: "secret", questions }, config, controller.signal),
    /Cancelled/,
  );
  await assert.rejects(
    evaluate(
      { state: "secret", questions },
      { ...config, baseUrl: "http://127.0.0.1:1/" },
    ),
    /network request failed/,
  );
});

test("malformed, mismatched, out-of-range and injected answers are rejected without echoing", async () => {
  const invalid = [
    null,
    { answers: {} },
    {
      answers: {
        match: { type: "choice", choice: "PRIVATE_FILE_CONTENT_SENTINEL" },
      },
    },
    { answers: { match: { type: "noul", noul: 2 } } },
    {
      answers: {
        match: {
          type: "noul",
          noul: 0.9,
          confidence: "PRIVATE_FILE_CONTENT_SENTINEL",
        },
      },
    },
  ];
  for (const data of invalid) {
    const config = await endpoint((_payload, response) => send(response, data));
    await assert.rejects(
      evaluate({ state: "secret", questions }, config),
      (error: Error) =>
        !error.message.includes("PRIVATE_FILE_CONTENT_SENTINEL"),
    );
  }
  const config = await endpoint((_payload, response) => {
    response.end("not JSON PRIVATE_FILE_CONTENT_SENTINEL");
  });
  await assert.rejects(
    evaluate({ state: "secret", questions }, config),
    /invalid JSON/,
  );
  const big = await endpoint((_payload, response) => {
    response.end("x".repeat(256 * 1024 + 1));
  });
  await assert.rejects(
    evaluate({ state: "secret", questions }, big),
    /response exceeds/,
  );
});

test("choice and score validate labels, distributions, ranges; optional metadata stays absent", () => {
  const choice = {
    type: "choice" as const,
    instructions: "Classify",
    criteria: { auth: "Auth", network: "Network" },
  };
  const score = {
    type: "score" as const,
    instructions: "Severity",
    criteria: ["Low", "High"],
  };
  assert.deepEqual(compactAnswer({ type: "choice", choice: "auth" }, choice), {
    type: "choice",
    answer: "auth",
  });
  assert.deepEqual(compactAnswer({ type: "score", score: 0.5 }, score), {
    type: "score",
    answer: 0.5,
  });
  for (const raw of [
    { type: "choice", choice: "PRIVATE_FILE_CONTENT_SENTINEL" },
    { type: "choice", choice: "auth", probabilities: { unexpected: 0.9 } },
    { type: "choice", choice: "auth", probabilities: { auth: -1 } },
    { type: "choice", choice: "auth", confidence: 2 },
  ])
    assert.throws(() => compactAnswer(raw, choice), /Invalid Jev answer/);
  for (const value of [-1, 2, Infinity, NaN, "PRIVATE_FILE_CONTENT_SENTINEL"]) {
    assert.throws(
      () => compactAnswer({ type: "score", score: value }, score),
      /Invalid Jev answer/,
    );
  }
});

test("startup validates env without API calls and gives UI/non-UI errors", async () => {
  let start:
    | ((event: unknown, ctx: ExtensionContext) => Promise<void>)
    | undefined;
  kJev({
    registerTool() {},
    on(event: string, handler: typeof start) {
      if (event === "session_start") start = handler;
    },
  } as unknown as ExtensionAPI);
  assert.ok(start);
  const keys = Object.keys(env).flatMap((key) => [
    key,
    key.replace(/^PI_/, "K_"),
  ]);
  const previous = Object.fromEntries(
    keys.map((key) => [key, process.env[key]]),
  );
  for (const key of keys) delete process.env[key];
  Object.assign(process.env, env);
  delete process.env.PI_JEV_API_KEY;
  try {
    const notifications: string[] = [];
    await start({}, {
      hasUI: true,
      ui: {
        notify(message: string) {
          notifications.push(message);
        },
      },
    } as unknown as ExtensionContext);
    assert.equal(notifications.length, 1);
    assert.match(notifications[0], /K_JEV_API_KEY is required/);
    await assert.rejects(
      start({}, { hasUI: false } as ExtensionContext),
      /K_JEV_API_KEY is required/,
    );
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("registered Pi tools expose only compact content/details/structuredContent and no automatic requests", async () => {
  const sentinel = "PRIVATE_FILE_CONTENT_SENTINEL";
  let calls = 0;
  const config = await endpoint((_payload, response) => {
    calls++;
    send(response, { ...noulResponse(), explanation: sentinel });
  });
  const keys = Object.keys(env).flatMap((key) => [
    key,
    key.replace(/^PI_/, "K_"),
  ]);
  const previous = Object.fromEntries(
    keys.map((key) => [key, process.env[key]]),
  );
  for (const key of keys) delete process.env[key];
  Object.assign(process.env, {
    PI_JEV_BASE_URL: config.baseUrl,
    PI_JEV_MODEL: config.model,
    PI_JEV_API_KEY: config.apiKey,
  });
  try {
    const tools = new Map<string, ToolDefinition>();
    const events: string[] = [];
    kJev({
      registerTool(tool: ToolDefinition) {
        tools.set(tool.name, tool);
      },
      on(event: string) {
        events.push(event);
      },
    } as unknown as ExtensionAPI);
    assert.deepEqual(
      [...tools.keys()],
      ["jev_evaluate", "jev_search", "jev_evaluate_files", "jev_evaluate_diff"],
    );
    assert.deepEqual(events, ["session_start"]);
    assert.equal(calls, 0);
    const { cwd, paths } = await candidates(1, sentinel);
    const ctx = { cwd } as ExtensionToolContext;
    const searchTool = tools.get("jev_search");
    const evaluateTool = tools.get("jev_evaluate");
    const filesTool = tools.get("jev_evaluate_files");
    const diffTool = tools.get("jev_evaluate_diff");
    assert.ok(searchTool && evaluateTool && filesTool && diffTool);
    assert.ok(filesTool.outputSchema);
    assert.ok(diffTool.outputSchema);
    assert.ok(Check(evaluateFilesOutputSchema, { results: [] }));
    assert.equal(evaluateDiffOutputSchema, evaluateOutputSchema);
    const fileResult = await searchTool.execute(
      "s",
      { paths, question: "Relevant?" },
      undefined,
      undefined,
      ctx,
    );
    assert.ok(!JSON.stringify(fileResult).includes(sentinel));
    assert.deepEqual(
      JSON.parse(
        fileResult.content[0].type === "text"
          ? fileResult.content[0].text
          : "null",
      ),
      fileResult.structuredContent,
    );
    assert.deepEqual(fileResult.details, fileResult.structuredContent);
    assert.ok(Check(searchOutputSchema, fileResult.structuredContent));
    const evaluation = await evaluateTool.execute(
      "e",
      { state: "Relevant", questions },
      undefined,
      undefined,
      ctx,
    );
    assert.ok(Check(evaluateOutputSchema, evaluation.structuredContent));
    delete process.env.PI_JEV_API_KEY;
    await assert.rejects(
      evaluateTool.execute(
        "e",
        { state: "Relevant", questions },
        undefined,
        undefined,
        ctx,
      ),
      /K_JEV_API_KEY is required/,
    );
    assert.equal(evaluation.usage?.totalTokens, 12);
    assert.equal(evaluation.usage?.cost.total, 0.01);
    assert.equal(calls, 2);
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("evaluateFiles primary path, ENOENT and EACCES edges stay specific", async () => {
  const sentinel = "PRIVATE_FILE_CONTENT_SENTINEL";
  const { cwd, paths } = await candidates(1, sentinel);
  const config = await endpoint((payload, response) => {
    assert.deepEqual(payload.state, { path: paths[0], content: sentinel });
    send(response, noulResponse());
  });
  const result = await evaluateFiles(
    { paths: [paths[0], "missing.ts"], questions },
    config,
    cwd,
  );
  assert.equal(result.results.length, 2);
  assert.ok("answers" in result.results[0]);
  assert.match(
    (result.results[1] as { error: string }).error,
    /File not found/,
  );
  assert.ok(!JSON.stringify(result).includes(sentinel));
  assert.ok(Check(evaluateFilesOutputSchema, { results: result.results }));
  await assert.rejects(
    evaluateFiles(
      {
        paths: Object.assign([], { length: 1 }) as string[],
        questions,
      },
      config,
      cwd,
    ),
    /1-20 UTF-8 file paths/,
  );
  const denied = join(cwd, "denied.ts");
  await writeFile(denied, sentinel);
  await chmod(denied, 0);
  try {
    if (process.getuid?.() !== 0) {
      const deniedResult = await evaluateFiles(
        { paths: ["denied.ts"], questions },
        config,
        cwd,
      );
      assert.equal(deniedResult.results.length, 1);
      assert.match(
        (deniedResult.results[0] as { error: string }).error,
        /permission denied/,
      );
    }
  } finally {
    await chmod(denied, 0o600);
  }
});

test("evaluateDiff accepts hyphenated refs and reports oversized diffs", async () => {
  const repo = await mkdtemp(join(tmpdir(), "k-jev-diff-"));
  cleanups.push(() => rm(repo, { recursive: true, force: true }));
  await execFile("git", ["init"], { cwd: repo });
  await execFile("git", ["config", "user.email", "test@example.com"], {
    cwd: repo,
  });
  await execFile("git", ["config", "user.name", "test"], { cwd: repo });
  await writeFile(join(repo, "tracked.txt"), "base\n");
  await execFile("git", ["add", "tracked.txt"], { cwd: repo });
  await execFile("git", ["commit", "-m", "base"], { cwd: repo });
  await execFile("git", ["branch", "feat/foo-bar"], { cwd: repo });
  await writeFile(join(repo, "tracked.txt"), `changed\n${"x".repeat(40)}\n`);
  const config = await endpoint((payload, response) => {
    const state = payload.state as { base: string; diff: string };
    assert.equal(state.base, "feat/foo-bar");
    assert.match(state.diff, /changed/);
    send(response, noulResponse());
  });
  const result = await evaluateDiff(
    { base: "feat/foo-bar", questions },
    config,
    repo,
  );
  assert.deepEqual(result.answers.match, {
    type: "noul",
    answer: true,
    probability: 0.9,
  });
  assert.ok(Check(evaluateDiffOutputSchema, { answers: result.answers }));
  for (const base of ["bad..ref", "-bad", "a".repeat(257)]) {
    await assert.rejects(
      evaluateDiff({ base, questions }, config, repo),
      /Invalid Git base ref/,
    );
  }
  await writeFile(join(repo, "tracked.txt"), `${"y".repeat(300 * 1024)}\n`);
  await assert.rejects(
    evaluateDiff({ questions }, resolveConfig(env), repo),
    /Diff exceeds 256 KiB/,
  );
});
