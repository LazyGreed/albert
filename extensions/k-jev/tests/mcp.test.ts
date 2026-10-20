import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { createServer as httpServer } from "node:http";
import { homedir, tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { type TestContext, test } from "node:test";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";
import type { JevConfig } from "../dist/core/config.js";
import { evaluate, type Questions } from "../dist/core/evaluate.js";
import { search } from "../dist/core/search.js";

const script = fileURLToPath(new URL("../dist/mcp.js", import.meta.url));
const questions: Questions = {
  match: {
    type: "noul",
    instructions: "Relevant?",
    criteria: { true: "Yes", false: "No" },
  },
  route: {
    type: "choice",
    instructions: "Classify",
    criteria: { auth: "Auth", network: "Network" },
  },
  rubric: {
    type: "score",
    instructions: "Severity",
    criteria: ["Low", "High"],
  },
};
const reply = {
  answers: {
    match: { type: "noul", noul: 0.9, explanation: "PRIVATE_SENTINEL" },
    route: {
      type: "choice",
      choice: "auth",
      probabilities: { auth: 0.9, network: 0.1 },
    },
    rubric: { type: "score", score: 0.5, confidence: 0.8 },
  },
  usage: { input_tokens: 10, output_tokens: 2, cost: 0.01 },
};
async function fixture(t: TestContext, stall = false) {
  const base = await mkdtemp(join(tmpdir(), "k-jev-mcp-"));
  const root = join(base, "project");
  const other = join(base, "project-sibling");
  await mkdir(root);
  await mkdir(other);
  await writeFile(join(root, "file.ts"), "PRIVATE_SENTINEL");
  await writeFile(join(other, "secret.ts"), "OUTSIDE_SENTINEL");
  let calls = 0;
  const uploaded: unknown[] = [];
  let started!: () => void;
  let closed!: () => void;
  const requestStarted = new Promise<void>((resolve) => {
    started = resolve;
  });
  const requestClosed = new Promise<void>((resolve) => {
    closed = resolve;
  });
  const server = httpServer(async (request, response) => {
    assert.equal(request.headers.authorization, "Bearer placeholder");
    let body = "";
    for await (const chunk of request) body += chunk;
    const payload = JSON.parse(body);
    calls++;
    uploaded.push(payload.state);
    if (stall) {
      response.on("close", closed);
      started();
    } else {
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify(reply));
    }
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.ok(address && typeof address === "object");
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rm(base, { recursive: true, force: true });
  });
  return {
    root,
    other,
    uploaded,
    requestStarted,
    requestClosed,
    calls: () => calls,
    config: {
      baseUrl: `http://127.0.0.1:${address.port}/decisions`,
      model: "test",
      apiKey: "placeholder",
    },
  };
}
const configEnv = (config: JevConfig) => ({
  K_JEV_BASE_URL: config.baseUrl,
  K_JEV_MODEL: config.model,
  K_JEV_API_KEY: config.apiKey,
});
async function launch(
  t: TestContext,
  config: JevConfig,
  cwd: string,
  root?: string,
) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [script],
    cwd,
    env: {
      ...configEnv(config),
      ...(root === undefined ? {} : { CLAUDE_PROJECT_DIR: root }),
    },
    stderr: "pipe",
  });
  let stderr = "";
  transport.stderr?.on("data", (chunk) => {
    stderr += chunk;
  });
  const client = new Client({ name: "k-jev-test", version: "1.0.0" });
  t.after(async () => {
    await client.close();
    assert.equal(stderr, "");
  });
  await client.connect(transport);
  return client;
}
function data(result: Awaited<ReturnType<Client["callTool"]>>) {
  assert.ok(!result.isError, JSON.stringify(result));
  const text = result.content[0];
  assert.equal(text.type, "text");
  assert.deepEqual(JSON.parse(text.text), result.structuredContent);
  assert.ok(!JSON.stringify(result).includes("PRIVATE_SENTINEL"));
  assert.ok(!JSON.stringify(result).includes("usage"));
  return result.structuredContent;
}

test("MCP lists exactly four tools without endpoint calls", {
  timeout: 10000,
}, async (t) => {
  const f = await fixture(t);
  const client = await launch(t, f.config, f.other, f.root);
  const listing = await client.listTools();
  assert.deepEqual(
    listing.tools.map((tool) => tool.name),
    ["jev_evaluate", "jev_search", "jev_evaluate_files", "jev_evaluate_diff"],
  );
  assert.equal(f.calls(), 0);
});

test("MCP evaluate matches core for all question types and sanitizes errors", {
  timeout: 10000,
}, async (t) => {
  const f = await fixture(t);
  const client = await launch(t, f.config, f.other, f.root);
  const input = { state: [{ status: 401 }, null, false], questions };
  const { usage: _, ...expected } = await evaluate(input, f.config);
  assert.deepEqual(
    data(await client.callTool({ name: "jev_evaluate", arguments: input })),
    expected,
  );
  const invalid = await client.callTool({
    name: "jev_evaluate",
    arguments: { state: null, questions: {} },
  });
  assert.equal(invalid.isError, true);
  assert.equal(f.calls(), 2);
});

test("MCP search matches core using CLAUDE_PROJECT_DIR instead of process cwd", {
  timeout: 10000,
}, async (t) => {
  const f = await fixture(t);
  const client = await launch(t, f.config, f.other, f.root);
  const input = { paths: ["file.ts", "missing.ts"], question: "Relevant?" };
  const { usage: _, ...expected } = await search(
    input,
    f.config,
    f.root,
    undefined,
    { allowedRoot: f.root },
  );
  assert.deepEqual(
    data(await client.callTool({ name: "jev_search", arguments: input })),
    expected,
  );
  assert.equal(f.calls(), 2);
});

test("MCP cancellation aborts upstream evaluate and search requests", {
  timeout: 10000,
}, async (t) => {
  for (const name of ["jev_evaluate", "jev_search"]) {
    const f = await fixture(t, true);
    const client = await launch(t, f.config, f.other, f.root);
    const controller = new AbortController();
    const input =
      name === "jev_evaluate"
        ? { state: null, questions }
        : { paths: ["file.ts"], question: "Relevant?" };
    const pending = client.callTool(
      { name, arguments: input },
      { signal: controller.signal },
    );
    const rejected = assert.rejects(pending);
    await f.requestStarted;
    controller.abort();
    await rejected;
    await f.requestClosed;
    assert.equal(f.calls(), 1);
  }
});

test("MCP confines relative, absolute, home and symlink paths; cwd fallback works", {
  timeout: 10000,
}, async (t) => {
  const f = await fixture(t);
  await symlink(join(f.root, "file.ts"), join(f.root, "inside.ts"));
  await symlink(join(f.other, "secret.ts"), join(f.root, "escape.ts"));
  await symlink(f.other, join(f.root, "escape-dir"));
  const client = await launch(t, f.config, f.other, f.root);
  const paths = [
    "file.ts",
    join(f.root, "file.ts"),
    "inside.ts",
    "../project-sibling/secret.ts",
    join(f.other, "secret.ts"),
    "escape.ts",
    "escape-dir/secret.ts",
    `~/${relative(homedir(), join(f.other, "secret.ts"))}`,
  ];
  const result = data(
    await client.callTool({
      name: "jev_search",
      arguments: { paths, question: "Relevant?" },
    }),
  );
  assert.ok(
    result &&
      typeof result === "object" &&
      "results" in result &&
      Array.isArray(result.results),
  );
  assert.deepEqual(
    result.results.map((item: { path: string }) => item.path),
    paths,
  );
  assert.ok(
    result.results.slice(0, 3).every((item: object) => "result" in item),
  );
  assert.ok(
    result.results
      .slice(3)
      .every((item: { error: string }) =>
        /outside the allowed project root/.test(item.error),
      ),
  );
  assert.equal(f.calls(), 3);
  assert.ok(!JSON.stringify(f.uploaded).includes("OUTSIDE_SENTINEL"));
  const fallback = await launch(t, f.config, f.root);
  data(
    await fallback.callTool({
      name: "jev_search",
      arguments: { paths: ["file.ts"], question: "Relevant?" },
    }),
  );
  assert.equal(f.calls(), 4);
  const alias = join(dirname(f.root), "project-alias");
  await symlink(f.root, alias);
  const aliased = await launch(t, f.config, f.other, alias);
  const aliasResult = data(
    await aliased.callTool({
      name: "jev_search",
      arguments: {
        paths: [
          "file.ts",
          join(alias, "file.ts"),
          `~/${relative(homedir(), join(f.root, "file.ts"))}`,
        ],
        question: "Relevant?",
      },
    }),
  );
  assert.ok(
    aliasResult &&
      typeof aliasResult === "object" &&
      "results" in aliasResult &&
      Array.isArray(aliasResult.results),
  );
  assert.ok(aliasResult.results.every((item: object) => "result" in item));
  assert.equal(f.calls(), 7);
});

test("stdio stdout is protocol only, including legacy clients and configuration errors", {
  timeout: 10000,
}, async (t) => {
  const child = spawn(process.execPath, [script], {
    cwd: dirname(script),
    env: { K_JEV_BASE_URL: "", K_JEV_MODEL: "", K_JEV_API_KEY: "" },
    stdio: ["pipe", "pipe", "pipe"],
  });
  t.after(() => {
    child.kill();
  });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => {
    stdout += chunk;
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });
  const messages: Record<string, unknown>[] = [];
  let buffer = "";
  let next!: () => void;
  child.stdout.on("data", (chunk) => {
    buffer += chunk;
    while (true) {
      const newline = buffer.indexOf("\n");
      if (newline < 0) break;
      messages.push(JSON.parse(buffer.slice(0, newline)));
      buffer = buffer.slice(newline + 1);
      next?.();
    }
  });
  async function request(id: number, method: string, params: unknown) {
    const arrived = new Promise<void>((resolve) => {
      next = resolve;
    });
    child.stdin.write(
      `${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`,
    );
    await arrived;
    assert.equal(messages.at(-1)?.id, id);
  }
  await request(1, "initialize", {
    protocolVersion: "2025-11-25",
    capabilities: {},
    clientInfo: { name: "test", version: "1" },
  });
  child.stdin.write(
    `${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`,
  );
  await request(2, "tools/list", {});
  await request(3, "tools/call", {
    name: "jev_evaluate",
    arguments: { state: null, questions: { match: questions.match } },
  });
  const ended = once(child, "exit");
  child.stdin.end();
  const [code] = await ended;
  assert.equal(code, 0);
  assert.equal(stderr, "");
  assert.equal(buffer, "");
  assert.equal(stdout.trim().split("\n").length, 3);
  assert.ok(messages.every((message) => message.jsonrpc === "2.0"));
  assert.match(JSON.stringify(messages[2]), /K_JEV_BASE_URL is required/);
});
