import { execFile } from "node:child_process";
import { realpath } from "node:fs/promises";
import { promisify } from "node:util";
import { type JevConfig, JevError } from "./config.js";
import {
  evaluate,
  isRecord,
  type Questions,
  validateQuestions,
} from "./evaluate.js";

const exec = promisify(execFile);
const MAX_DIFF_BYTES = 256 * 1024;
const BASE_REF = /^[A-Za-z0-9][A-Za-z0-9._/^~-]*$/;

function isOversizedDiffError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const code = "code" in error ? error.code : undefined;
  if (code === "ERR_CHILD_PROCESS_STDIO_MAXBUFFER") return true;
  const message =
    "message" in error && typeof error.message === "string"
      ? error.message
      : "";
  return /maxBuffer/i.test(message);
}

export async function evaluateDiff(
  input: { base?: string; questions: Questions },
  config: JevConfig,
  cwd: string,
  signal?: AbortSignal,
) {
  if (
    !isRecord(input) ||
    Object.keys(input).some((k) => k !== "base" && k !== "questions")
  )
    throw new JevError("k-jev: Supply optional base ref and questions.");
  validateQuestions(input.questions);
  const base = input.base ?? "HEAD";
  if (
    typeof base !== "string" ||
    base.length > 256 ||
    !BASE_REF.test(base) ||
    base.includes("..")
  )
    throw new JevError("k-jev: Invalid Git base ref.");
  let root: string;
  try {
    root = await realpath(cwd);
  } catch {
    throw new JevError("k-jev: Cannot resolve project root.");
  }
  let diff: string;
  try {
    const result = await exec(
      "git",
      [
        "-c",
        "core.pager=cat",
        "diff",
        "--no-ext-diff",
        "--no-color",
        base,
        "--",
      ],
      {
        cwd: root,
        signal,
        timeout: 10_000,
        maxBuffer: MAX_DIFF_BYTES + 1,
        encoding: "utf8",
      },
    );
    diff = result.stdout;
  } catch (error) {
    if (signal?.aborted) throw new JevError("k-jev: Cancelled.");
    if (isOversizedDiffError(error))
      throw new JevError("k-jev: Diff exceeds 256 KiB. Narrow the scope.");
    throw new JevError(
      "k-jev: Cannot read Git diff. Check ref, checkout, or size limit.",
    );
  }
  if (!diff.trim())
    throw new JevError("k-jev: No tracked-file diff against the chosen base.");
  if (Buffer.byteLength(diff) > MAX_DIFF_BYTES)
    throw new JevError("k-jev: Diff exceeds 256 KiB. Narrow the scope.");
  const result = await evaluate(
    {
      state: { base, diff },
      questions: input.questions,
    },
    config,
    signal,
  );
  return result;
}
