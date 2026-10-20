# k-jev

Shared semantic evaluation and content-free file search for Pi and Claude Code.
One agent-independent core, a Pi extension, and an MCP v2 stdio server. Calls are explicit; Jev returns evidence, not authority.

## Install

Requires Node.js 22.18+ and npm.

```sh
cd /path/to/this/repo/extensions/k-jev
npm ci --ignore-scripts
npm run build

pi install "$PWD"
claude mcp add --scope user --transport stdio k-jev -- node "$PWD/dist/mcp.js"
claude mcp get k-jev
```

Pi loads the source adapter through the package manifest. Claude launches the compiled server as a local child process. No plugin, hook, daemon, or HTTP server.

## Configuration

Export these in the shell that launches either agent. Keep secrets out of MCP configuration:

```fish
set -Ux K_JEV_BASE_URL 'https://your-service.example/decisions'
set -Ux K_JEV_MODEL 'your-model'
set -Ux K_JEV_API_KEY 'your-key'
```

For POSIX shells, use `export NAME='value'` instead. Restart the agents after changing exports.
Each `K_JEV_*` variable takes precedence over its legacy `PI_JEV_*` counterpart; legacy exports still work. An empty canonical value fails validation rather than falling back.

The base URL is the full POST decision endpoint; no path is appended. It must accept `{model,state,questions}` and return Jev-compatible `{answers,usage?}` JSON. A nonempty key is required even for unauthenticated local endpoints; use `placeholder`. Requests send `Authorization: Bearer ...`. Never embed credentials in the URL.

## Tools

`jev_evaluate` judges JSON state using named questions:

```json
{
  "state": {"status": 401},
  "questions": {
    "retryable": {
      "type": "noul",
      "instructions": "Would retrying unchanged credentials succeed?",
      "criteria": {"true": "Transient failure", "false": "Credentials need correction"}
    }
  }
}
```

`noul` returns a yes probability and a boolean using a 0.5 threshold. `choice` takes a label-to-criterion object; `score` takes an ordered criteria array and returns a fractional zero-based score. Results retain available confidence and probabilities, never provider explanations.

Discover candidate paths first, then call `jev_search`:

```json
{
  "paths": ["src/auth/rotation.ts", "src/auth/session.ts"],
  "question": "Does this file implement credential rotation?"
}
```

Search sends file contents to the configured endpoint, but returns only ordered paths with typed answers or individual errors. No excerpts reach the calling model. Read promising files normally to verify.

- Pi and MCP both confine `jev_search` (and `jev_evaluate_files`) to the project root: Pi uses the session cwd (`allowedRoot: ctx.cwd`); MCP uses `CLAUDE_PROJECT_DIR`, falling back to process cwd. Only files within that canonical root are allowed, including symlink targets. Absolute paths and `~/` work only when they resolve inside that root. MCP roots and Claude `--add-dir` are not supported yet.
- This is a search path policy, not an OS sandbox. Explicit `jev_evaluate` state can contain any JSON supplied by the caller.

## Limits and development

Search accepts 1-200 UTF-8 regular files, at most 256 KiB each, with four workers per call. Binary and invalid UTF-8 files fail individually.
Evaluation accepts 1-64 questions, 2-64 choice labels, or 2-10 score levels. Requests are limited to 1 MiB and responses to 256 KiB. Each HTTP request has a 30-second timeout; no retries. Cancellation stops remaining work.
Pi reports available token usage and total cost; MCP excludes usage from model-visible results. Provider error bodies and extra response fields are discarded.

```sh
npm run check
npm test
npx @modelcontextprotocol/inspector node dist/mcp.js
```

Core owns validation independently of adapter schemas. Keep Pi, MCP, tool registration, and UI dependencies out of `src/core/`.

## Added semantic tools (Albert opt-in)

- `jev_evaluate_files`: Evaluate 1-20 UTF-8 text files against a common set of typed questions. Each file is evaluated independently; responses contain answers and paths, never file text. Files must resolve beneath the project root. Per-file read/judgment errors are reported independently.
- `jev_evaluate_diff`: Evaluate the tracked Git diff against `HEAD` or a supplied base ref with typed questions. Includes staged and unstaged changes to tracked files; **does not include untracked files**. Diff size limit: 256 KiB. No changes to Git state.
- Existing `jev_evaluate` and `jev_search` remain available and retain their schemas. Pi `jev_search` is now project-root confined like the MCP version.
- New tools reuse the same configured Jev endpoint and same question/answer types. Judgment is probabilistic, not a deterministic verifier. Read relevant source and execute checks normally.
- Enabling Jev sends source text/diffs to the configured endpoint. Exclude credentials, tokens, private customer documents, and proprietary code unless the endpoint and transmission are approved. Jev is never mandatory for reviews or acceptance.

The agent adapter does not require Jev to launch. With opt-in, install/build the extension, configure `K_JEV_*` environment variables, and reload Pi or Claude. Node.js >=22.18 is required by the existing `k-jev` package.
