import type { Usage } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { JevError, resolveConfig, safeError } from "./core/config.js";
import { evaluateDiff } from "./core/diff.js";
import { evaluate } from "./core/evaluate.js";
import { evaluateFiles } from "./core/files.js";
import { search } from "./core/search.js";
import type { JevUsage } from "./core/usage.js";

const text = Type.String({ minLength: 1, maxLength: 4096 });
const questionSchema = Type.Union([
  Type.Object(
    {
      type: Type.Literal("noul"),
      instructions: text,
      criteria: Type.Object(
        { true: text, false: text },
        { additionalProperties: false },
      ),
    },
    { additionalProperties: false },
  ),
  Type.Object(
    {
      type: Type.Literal("choice"),
      instructions: text,
      criteria: Type.Record(
        Type.String({ minLength: 1, maxLength: 128 }),
        text,
        { minProperties: 2, maxProperties: 64 },
      ),
    },
    { additionalProperties: false },
  ),
  Type.Object(
    {
      type: Type.Literal("score"),
      instructions: text,
      criteria: Type.Array(text, { minItems: 2, maxItems: 10 }),
    },
    { additionalProperties: false },
  ),
]);
export const evaluateSchema = Type.Object(
  {
    state: Type.Unknown({
      description:
        "JSON state to judge. Sent only to the configured Jev endpoint.",
    }),
    questions: Type.Record(
      Type.String({ minLength: 1, maxLength: 128 }),
      questionSchema,
      { minProperties: 1, maxProperties: 64 },
    ),
  },
  { additionalProperties: false },
);
const probability = Type.Number({ minimum: 0, maximum: 1 });
const metadata = {
  confidence: Type.Optional(probability),
  probabilities: Type.Optional(Type.Record(Type.String(), probability)),
};
const answerSchema = Type.Union([
  Type.Object(
    {
      type: Type.Literal("noul"),
      answer: Type.Boolean(),
      probability,
      confidence: metadata.confidence,
    },
    { additionalProperties: false },
  ),
  Type.Object(
    { type: Type.Literal("choice"), answer: Type.String(), ...metadata },
    { additionalProperties: false },
  ),
  Type.Object(
    { type: Type.Literal("score"), answer: Type.Number(), ...metadata },
    { additionalProperties: false },
  ),
]);
export const evaluateOutputSchema = Type.Object({
  answers: Type.Record(Type.String(), answerSchema),
});
export const searchSchema = Type.Object(
  {
    paths: Type.Array(Type.String({ minLength: 1, maxLength: 4096 }), {
      minItems: 1,
      maxItems: 200,
    }),
    question: Type.String({
      minLength: 1,
      maxLength: 2048,
      description:
        "Yes/no semantic question evaluated independently against each file.",
    }),
  },
  { additionalProperties: false },
);
export const searchOutputSchema = Type.Object({
  results: Type.Array(
    Type.Union([
      Type.Object(
        { path: Type.String(), result: answerSchema },
        { additionalProperties: false },
      ),
      Type.Object(
        { path: Type.String(), error: Type.String() },
        { additionalProperties: false },
      ),
    ]),
  ),
});
export const evaluateFilesOutputSchema = Type.Object({
  results: Type.Array(
    Type.Union([
      Type.Object(
        {
          path: Type.String(),
          answers: Type.Record(Type.String(), answerSchema),
        },
        { additionalProperties: false },
      ),
      Type.Object(
        { path: Type.String(), error: Type.String() },
        { additionalProperties: false },
      ),
    ]),
  ),
});
export const evaluateDiffOutputSchema = evaluateOutputSchema;

function toPiUsage(usage: JevUsage | undefined): Usage | undefined {
  if (!usage) return undefined;
  return {
    input: usage.inputTokens,
    output: usage.outputTokens,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: usage.inputTokens + usage.outputTokens,
    cost: {
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      total: usage.cost ?? 0,
    },
  };
}

export default function kJev(pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    try {
      resolveConfig();
    } catch (error) {
      if (ctx.hasUI) ctx.ui.notify(safeError(error), "warning");
      else throw new JevError(safeError(error));
    }
  });

  pi.registerTool(
    defineTool({
      name: "jev_evaluate",
      label: "Jev evaluate",
      description:
        "Bounded semantic judgment of JSON state using named typed questions: noul (yes/no probability), choice (fixed labels), score (ordered rubric, fractional zero-based score). Supply instructions and criteria. Returns compact typed evidence, not authority; verify important conclusions with normal tools/tests. Sends only the supplied state and questions to the configured Jev endpoint. Invoked only when you choose to call it.",
      parameters: evaluateSchema,
      outputSchema: evaluateOutputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: true,
      },
      async execute(_id, input, signal) {
        try {
          const { usage, ...data } = await evaluate(
            input,
            resolveConfig(),
            signal,
          );
          return {
            content: [{ type: "text", text: JSON.stringify(data) }],
            details: data,
            structuredContent: data,
            usage: toPiUsage(usage),
          };
        } catch (error) {
          throw new JevError(safeError(error));
        }
      },
    }),
  );

  pi.registerTool(
    defineTool({
      name: "jev_search",
      label: "Jev search",
      description:
        "Evaluate a yes/no semantic question against 1-200 candidate UTF-8 files (each at most 256 KiB). Reads files internally and sends contents to the configured Jev endpoint, never into your context. Uses four workers per call; returns only paths, typed answers/probabilities, or individual errors, in input order. Relative paths resolve from Pi's cwd; ~/ is supported. No excerpts. Jev is evidence, not authority: read promising files normally to verify. Find candidates first with normal path-discovery tools.",
      parameters: searchSchema,
      outputSchema: searchOutputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: true,
      },
      async execute(_id, input, signal, _onUpdate, ctx) {
        try {
          const { usage, ...data } = await search(
            input,
            resolveConfig(),
            ctx.cwd,
            signal,
            { allowedRoot: ctx.cwd },
          );
          return {
            content: [{ type: "text", text: JSON.stringify(data) }],
            details: data,
            structuredContent: data,
            usage: toPiUsage(usage),
          };
        } catch (error) {
          throw new JevError(safeError(error));
        }
      },
    }),
  );
  pi.registerTool(
    defineTool({
      name: "jev_evaluate_files",
      label: "Jev evaluate files",
      description:
        "Evaluate 1-20 project-root files independently against typed questions. Sends contents to configured Jev service. Returns answers per path, no excerpts.",
      parameters: Type.Object(
        {
          paths: Type.Array(Type.String({ minLength: 1, maxLength: 4096 }), {
            minItems: 1,
            maxItems: 20,
          }),
          questions: evaluateSchema.properties.questions,
        },
        { additionalProperties: false },
      ),
      outputSchema: evaluateFilesOutputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: true,
      },
      async execute(_id, input, signal, _onUpdate, ctx) {
        try {
          const { usage, ...data } = await evaluateFiles(
            input,
            resolveConfig(),
            ctx.cwd,
            signal,
          );
          return {
            content: [{ type: "text", text: JSON.stringify(data) }],
            details: data,
            structuredContent: data,
            usage: toPiUsage(usage),
          };
        } catch (error) {
          throw new JevError(safeError(error));
        }
      },
    }),
  );

  pi.registerTool(
    defineTool({
      name: "jev_evaluate_diff",
      label: "Jev evaluate diff",
      description:
        "Judge the tracked Git diff against HEAD or base with typed questions. Sends diff to configured Jev service. Does not include untracked files.",
      parameters: Type.Object(
        {
          base: Type.Optional(Type.String({ minLength: 1, maxLength: 256 })),
          questions: evaluateSchema.properties.questions,
        },
        { additionalProperties: false },
      ),
      outputSchema: evaluateDiffOutputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: true,
      },
      async execute(_id, input, signal, _onUpdate, ctx) {
        try {
          const { usage, ...data } = await evaluateDiff(
            input,
            resolveConfig(),
            ctx.cwd,
            signal,
          );
          return {
            content: [{ type: "text", text: JSON.stringify(data) }],
            details: data,
            structuredContent: data,
            usage: toPiUsage(usage),
          };
        } catch (error) {
          throw new JevError(safeError(error));
        }
      },
    }),
  );
}
