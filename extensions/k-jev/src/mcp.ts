import { McpServer } from "@modelcontextprotocol/server";
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import * as z from "zod/v4";
import { resolveConfig, safeError } from "./core/config.js";
import { evaluateDiff } from "./core/diff.js";
import { evaluate } from "./core/evaluate.js";
import { evaluateFiles } from "./core/files.js";
import { search } from "./core/search.js";

const text = z.string().min(1).max(4096);
const name = z.string().min(1).max(128);
const boundedRecord = <T extends z.ZodType>(
  value: T,
  min: number,
  max: number,
) =>
  z.record(name, value).refine((record) => {
    const count = Object.keys(record).length;
    return count >= min && count <= max;
  }, `Expected ${min}-${max} entries`);
const questionSchema = z.discriminatedUnion("type", [
  z.strictObject({
    type: z.literal("noul"),
    instructions: text,
    criteria: z.strictObject({ true: text, false: text }),
  }),
  z.strictObject({
    type: z.literal("choice"),
    instructions: text,
    criteria: boundedRecord(text, 2, 64),
  }),
  z.strictObject({
    type: z.literal("score"),
    instructions: text,
    criteria: z.array(text).min(2).max(10),
  }),
]);
export const evaluateSchema = z.strictObject({
  state: z.json(),
  questions: boundedRecord(questionSchema, 1, 64),
});
export const searchSchema = z.strictObject({
  paths: z.array(z.string().min(1).max(4096)).min(1).max(200),
  question: z.string().min(1).max(2048),
});
const annotations = {
  readOnlyHint: true,
  destructiveHint: false,
  openWorldHint: true,
};
const failure = (error: unknown) => ({
  isError: true,
  content: [{ type: "text" as const, text: safeError(error) }],
});

export function createServer() {
  const server = new McpServer({ name: "k-jev", version: "1.0.0" });
  server.registerTool(
    "jev_evaluate",
    {
      description:
        "Bounded semantic judgment of JSON state using named noul (yes/no probability), choice (fixed labels), or score (fractional zero-based rubric) questions. Supply instructions and criteria. Use when deterministic checks are insufficient. Returns evidence, not authority; verify important conclusions. Sends supplied state and questions to the configured Jev endpoint.",
      inputSchema: evaluateSchema,
      annotations,
    },
    async (input, ctx) => {
      try {
        const { usage: _, ...result } = await evaluate(
          input,
          resolveConfig(),
          ctx.mcpReq.signal,
        );
        return {
          content: [{ type: "text", text: JSON.stringify(result) }],
          structuredContent: result,
        };
      } catch (error) {
        return failure(error);
      }
    },
  );
  server.registerTool(
    "jev_search",
    {
      description:
        "Evaluate a yes/no semantic question against 1-200 candidate UTF-8 files, at most 256 KiB each, without adding their contents to your context. Sends file contents to the configured Jev endpoint. Only files beneath the project root (CLAUDE_PROJECT_DIR, otherwise process cwd), including resolved symlink targets, are allowed. Relative paths use that root. Returns ordered paths and typed answers or individual errors, no excerpts. Find candidates first; read promising files normally to verify.",
      inputSchema: searchSchema,
      annotations,
    },
    async (input, ctx) => {
      try {
        const cwd = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
        const { usage: _, ...result } = await search(
          input,
          resolveConfig(),
          cwd,
          ctx.mcpReq.signal,
          { allowedRoot: cwd },
        );
        return {
          content: [{ type: "text", text: JSON.stringify(result) }],
          structuredContent: result,
        };
      } catch (error) {
        return failure(error);
      }
    },
  );
  server.registerTool(
    "jev_evaluate_files",
    {
      description:
        "Evaluate 1-20 UTF-8 project-root files independently against typed questions. Sends file contents to configured Jev endpoint. Returns judgments only, never excerpts.",
      inputSchema: z.strictObject({
        paths: z.array(z.string().min(1).max(4096)).min(1).max(20),
        questions: boundedRecord(questionSchema, 1, 64),
      }),
      annotations,
    },
    async (input, ctx) => {
      try {
        const cwd = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
        const { usage: _, ...result } = await evaluateFiles(
          input,
          resolveConfig(),
          cwd,
          ctx.mcpReq.signal,
        );
        return {
          content: [{ type: "text", text: JSON.stringify(result) }],
          structuredContent: result,
        };
      } catch (error) {
        return failure(error);
      }
    },
  );
  server.registerTool(
    "jev_evaluate_diff",
    {
      description:
        "Evaluate tracked-file Git diff against base (default HEAD) using typed questions. Sends diff to configured endpoint; no untracked files.",
      inputSchema: z.strictObject({
        base: z.string().min(1).max(256).optional(),
        questions: boundedRecord(questionSchema, 1, 64),
      }),
      annotations,
    },
    async (input, ctx) => {
      try {
        const cwd = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
        const { usage: _, ...result } = await evaluateDiff(
          input,
          resolveConfig(),
          cwd,
          ctx.mcpReq.signal,
        );
        return {
          content: [{ type: "text", text: JSON.stringify(result) }],
          structuredContent: result,
        };
      } catch (error) {
        return failure(error);
      }
    },
  );
  return server;
}

if (import.meta.main) void serveStdio(createServer);
