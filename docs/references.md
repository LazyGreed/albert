# Research lineage, external references, and acknowledgements

Quintet coordinates agents through existing coding harnesses. This catalogue traces **current integrations and historical influences**, including ideas adopted while this project was still a personal Pi/Claude Code setup and later Albert. It distinguishes **integrated**, **adapted**, **historical**, and **consulted only** sources: a reference does not imply copied code, endorsement, or continued use.

## Coding harnesses and native agent interfaces

| Source | Relationship | Where it informs Quintet |
| --- | --- | --- |
| [Pi coding agent](https://github.com/earendil-works/pi) | Supported harness and API surface | `install.sh`, `docs/workflow.md` |
| [tintinweb/pi-subagents](https://github.com/tintinweb/pi-subagents) | Required Pi backend: native profiles, steering, FleetView, parallel runs, and round summaries. Quintet owns the workstream policy. | `README.md`, `install.sh`, `docs/workflow.md`; [integration](https://github.com/LazyGreed/quintet/commit/eb9230875c4ee44b4cb0a1ad3dbdd4c638e9174e) and [reporting](https://github.com/LazyGreed/quintet/commit/0503e78aa614fa6e4a3f9d9918726200281bb980) |
| [Claude Code subagents](https://code.claude.com/docs/en/sub-agents) | Supported native subagent interface | `install.sh`, `docs/workflow.md`, `agents/` |
| [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams) | Optional, harness-dependent peer communication | `docs/peer-messaging.md`; messaging only when the host exposes it |
| [Google Antigravity CLI](https://github.com/google-antigravity/antigravity-cli) and [custom subagents](https://antigravity.google/docs/subagents) | Supported native agent interface | `install.sh`, `docs/workflow.md`, `docs/peer-messaging.md` |
| [Antigravity swarm](https://antigravity.google/docs/swarm/) | Optional, host-managed peer communication | `docs/peer-messaging.md`; Quintet does not start swarms automatically |
| [Oh My Pi](https://github.com/can1357/oh-my-pi) | Compatibility/reference for peer messaging, not a dedicated installer target | `docs/peer-messaging.md`; `agent://` availability is runtime-dependent |

## Web access

| Source | Relationship | Where it informs Quintet |
| --- | --- | --- |
| [pi-web-access](https://github.com/nicobailon/pi-web-access) | External Pi package used for web search/fetch when web access is enabled | `install.sh`, `AGENTS.md` |

## Research and design inspiration

| Source | Relationship | Where it informs Quintet |
| --- | --- | --- |
| [*The Alien Space of Science: Sampling Coherent but Cognitively Unavailable Research Directions*](https://arxiv.org/abs/2603.01092) and [authors' code](https://github.com/alejandrohdez00/alien-space-of-science) | **Conceptual inspiration only**. Quintet uses a prompt-level ideation heuristic, not the paper's trained coherence or availability models. Its qualitative scores are not calibrated research measurements. | `skills/alien-science-ideation/SKILL.md`, `AGENTS.md`, `docs/workflow.md` |
| [Nusrat & Nusrat, *Weight-space programming for auditing clinical decision networks*](https://arxiv.org/abs/2611.05341v1) | **Adapted methodology** from the supplied v1 skill bundle: protocol-based black-box testing, weight-space diagnosis, sampled claim verification, minimal candidate edits, collateral regression and deployment-precision checks. The source is a preprint on small synthetic ReLU networks. It does not validate the broader workflows described in the skill file or establish clinical validity. | `skills/weight-space-network-audit/SKILL.md`, `skills/weight-space-network-audit/references/` (see `skills/weight-space-network-audit/references/research.md` for expanded references), `AGENTS.md`, `docs/workflow.md`; supplied `Weight space network audit-v1.zip`. |

## Influences adopted into the design

These are more than dependencies. Quintet's history identifies concrete ideas adopted from external work, even when the corresponding old skill files have since been consolidated.

| Original source | What Quintet adapted | Evidence and current home |
| --- | --- | --- |
| [Cursor pstack, by Lauren Tan](https://github.com/cursor/plugins/tree/main/pstack) | Blast-radius review, independent adversarial verification, and tracing *why* a design exists in addition to *how* the code works. Not the pstack router, automatic PR engine, or mandatory multi-model tournaments. | [2026-11-02 adoption commit](https://github.com/LazyGreed/quintet/commit/a1fe9997661105c54083f7ab87e513c016cd831b); `agents/nora.md`, `agents/vera.md`. |
| [Matt Pocock's engineering skills](https://github.com/mattpocock/skills) | Historical `codebase-design` and `domain-modeling` skills **explicitly credited** his work. Deep modules, module interfaces, seams, vocabulary, invariants, and change locality survive in the consolidated `architecture` and `domain-modeling` skills. | [Early skill tree](https://github.com/LazyGreed/quintet/tree/c424552f0c601fb5575278691b5b926c0f067a31/skills), [consolidation](https://github.com/LazyGreed/quintet/commit/48c0361c0fb7691dafbbb6a4ef84f410154d27cb), `skills/architecture/`, `skills/domain-modeling/`. |
| [mshumer/unslop](https://github.com/mshumer/unslop) | Historical `unslop` skill explicitly credited its underlying concept: remove model-default phrasing without losing technical facts. Adapted into current documentation-editing guidance rather than retaining a standalone skill. | [Historical unslop skill](https://github.com/LazyGreed/quintet/blob/364aa919b0f8ad6201f41a25bba5773397300464/skills/unslop/SKILL.md); `skills/documentation/references/editing.md`. |
| [miqdadbadjuber/anti-slop](https://github.com/miqdadbadjuber/anti-slop) | **Historically included** its core and specialized skills for UI, copy, comments, accessibility, and responsive/mobile design. The suite was later removed, with related general guidance retained in condensed form. Do not claim the full suite is presently installed. | [2026-10-10 skill addition](https://github.com/LazyGreed/quintet/commit/8ba96676ef189a1a0ca6f2afcdd5be378829cafb); [2026-10-15 consolidation](https://github.com/LazyGreed/quintet/commit/48c0361c0fb7691dafbbb6a4ef84f410154d27cb). |

## Earlier implementations and tool lineage

| Source | Historical relationship | Evidence |
| --- | --- | --- |
| [nathanstephenson/pi-subagents](https://github.com/nathanstephenson/pi-subagents) | Earlier Pi subagent backend, **superseded** by tintinweb's implementation. | [2026-10-15 installer](https://github.com/LazyGreed/quintet/commit/48c0361c0fb7691dafbbb6a4ef84f410154d27cb), [2026-10-18 migration](https://github.com/LazyGreed/quintet/commit/eb9230875c4ee44b4cb0a1ad3dbdd4c638e9174e). |
| [pi-warden](https://github.com/DevMortimer/pi-warden) | Included in the original Pi package list, with a `pi-warden/config.json` directory; **not** a current Quintet prerequisite. | [2026-09-28 historical tree](https://github.com/LazyGreed/quintet/tree/c424552f0c601fb5575278691b5b926c0f067a31), earlier `settings.json`. |
| [pi-blackhole](https://github.com/k0valik/pi-blackhole) | Former Pi example package and bundled compaction config. The installer does not install either or remove user-managed copies. | [Earlier configuration](https://github.com/LazyGreed/quintet/tree/c424552f0c601fb5575278691b5b926c0f067a31/pi-blackhole). |

## Consulted or compared, not verified as implemented

These sources were discussed during Quintet/Albert development, but **a review or recommendation is not evidence of a merged implementation**.

| Source | What was evaluated | Status |
| --- | --- | --- |
| [Cloudflare security-audit-skill](https://github.com/cloudflare/security-audit-skill) and [Skills CLI](https://skills.sh/) | Easier cross-harness skill distribution using `npx skills add`; a potential alternative to manual installation and `install.sh`. | **Consulted only**. No corresponding distribution workflow found in `main`. |
| [Microsoft TokenEconomizer](https://github.com/microsoft/TokenEconomizer), [research paper](https://arxiv.org/abs/2610.22732) | Efficient handoffs, adaptive delegation, avoiding repeated failed attempts, and tool-economy ideas. | **Consulted only**. No TokenEconomizer runtime or cross-session experience memory added; Quintet retains native session state rather than a new memory system. |
| `pybot-msgboard` (previous discussion; repository URL not currently verifiable) | Peer-to-peer agent coordination and messaging patterns. | **Exploratory comparison**; no standalone message board or peer broker in Quintet. `docs/peer-messaging.md` documents native host transports and fallback to the coordinator. |

## Graph coordination references

- Kanade's supplied *Quintet Graph-Aware Coordination: Final Proposal* (revision v3, targeting `6715d8d5`): design source for the v2 coordination rules on `main`; v3 is the proposal revision, not a Quintet release. The [workflow](workflow.md#dependency-graph) records the adopted prompt rules; the overlap helper and experiment branches are deferred.
- Git's [`diff`](https://git-scm.com/docs/git-diff), [`status`](https://git-scm.com/docs/git-status), and [`worktree`](https://git-scm.com/docs/git-worktree) manuals: **consulted only** for incremental path records, cleanliness checks, and isolated verification. No graph engine or Git code was imported.

## Maintenance and attribution rules

- Record meaningful influences **even after the original files are removed or consolidated**. Link a primary upstream source and the Quintet commit or historical file establishing the relationship.
- Specify the relationship: **required dependency**, **optional integration**, **direct adaptation**, **historical**, **compatibility reference**, or **consulted only**. Do not imply that reading a project means its code was reused.
- Link to the relevant Quintet implementation or configuration files. Where behavior depends on an upstream release, record the tested version or commit in the corresponding feature documentation or test.
- For copied/adapted source code or other licensed material, preserve all required copyright notices and license terms in addition to attribution here. This list is **not** a replacement for a repository license or a third-party notices file.
- Keep speculative proposals out of the adopted list. Document researched-but-unimplemented ideas separately; promote them only with a specific implementing commit and verifiable file path.

_Historical catalogue reviewed against Quintet `main` at [6a3b169](https://github.com/LazyGreed/quintet/commit/6a3b16953b5eec86cc99b9b007cc106610caefab); weight-space audit entry added 2026-11-24 from the supplied skill bundle._
