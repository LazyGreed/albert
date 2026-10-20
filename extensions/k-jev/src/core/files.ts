import { realpath } from "node:fs/promises";
import { type JevConfig, JevError, safeError } from "./config.js";
import {
  evaluate,
  isRecord,
  isText,
  type Questions,
  validateQuestions,
} from "./evaluate.js";
import { readCandidate } from "./search.js";
import { addUsage, type JevUsage } from "./usage.js";

export const MAX_EVALUATION_FILES = 20;

export async function evaluateFiles(
  input: { paths: string[]; questions: Questions },
  config: JevConfig,
  cwd: string,
  signal?: AbortSignal,
) {
  if (
    !isRecord(input) ||
    Object.keys(input).length !== 2 ||
    !Array.isArray(input.paths) ||
    input.paths.length < 1 ||
    input.paths.length > MAX_EVALUATION_FILES ||
    Array.from(input.paths).some((p) => !isText(p, 4096))
  )
    throw new JevError("k-jev: Supply 1-20 UTF-8 file paths and questions.");
  validateQuestions(input.questions);
  let root: string;
  try {
    root = await realpath(cwd);
  } catch {
    throw new JevError("k-jev: Cannot resolve project root.");
  }
  const results: Array<
    | { path: string; answers: Awaited<ReturnType<typeof evaluate>>["answers"] }
    | { path: string; error: string }
  > = new Array(input.paths.length);
  let index = 0;
  let usage: JevUsage | undefined;
  async function run() {
    while (index < input.paths.length) {
      signal?.throwIfAborted();
      const i = index++;
      const path = input.paths[i];
      try {
        const content = await readCandidate(path, root, signal, root);
        const judgment = await evaluate(
          {
            state: { path, content },
            questions: input.questions,
          },
          config,
          signal,
        );
        results[i] = { path, answers: judgment.answers };
        usage = addUsage(usage, judgment.usage);
      } catch (error) {
        if (signal?.aborted) throw new JevError("k-jev: Cancelled.");
        const code =
          error && typeof error === "object" && "code" in error
            ? error.code
            : undefined;
        const message =
          code === "ENOENT"
            ? "k-jev: File not found."
            : code === "EACCES" || code === "EPERM"
              ? "k-jev: Cannot read file (permission denied)."
              : safeError(error);
        results[i] = { path, error: message };
      }
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(4, input.paths.length) }, run),
  );
  return { results, usage };
}
