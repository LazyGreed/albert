# Research lineage, external references, and acknowledgements

Quintet coordinates agents through existing coding harnesses. This catalogue traces **current integrations and historical influences**, including ideas adopted while this project was a personal Pi/Claude Code setup and later Albert. It distinguishes **integrated**, **adapted**, **historical**, and **consulted only** sources: listing a reference does not imply copied code, endorsement, or continued use.

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
| [*The Alien Space of Science: Sampling Coherent but Cognitively Unavailable Research Directions*](https://arxiv.org/abs/2603.01092) and [authors' code](https://github.com/alejandrohdez00/alien-space-of-science) | **Conceptual inspiration only.** Quintet uses a prompt-level ideation heuristic, not the paper's trained coherence or availability models. Its qualitative scores are not calibrated research measurements. Quintet loads the heuristic only on an explicit user request. | `skills/alien-science-ideation/SKILL.md`, `AGENTS.md`, `docs/workflow.md` |
| [Nusrat & Nusrat, *Weight-space programming for auditing clinical decision networks*](https://arxiv.org/abs/2611.05341v1) | **Adapted methodology** from the supplied v1 skill bundle: protocol-based black-box testing, weight-space diagnosis, sampled claim verification, minimal candidate edits, collateral regression, and deployment-precision checks. The source is a preprint on small synthetic ReLU networks; this is a procedural skill, not a general LLM weight-editing method or clinical validation. | `skills/weight-space-network-audit/SKILL.md`, `skills/weight-space-network-audit/references/` (see `references/research.md`), `AGENTS.md`, `docs/workflow.md`; supplied `Weight space network audit-v1.zip` |

## Influences adopted into the design

These ideas were adapted from external work into Quintet's design, even after earlier skill files were consolidated.

| Original source | What Quintet adapted | Evidence and current home |
| --- | --- | --- |
| [Cursor pstack, by Lauren Tan](https://github.com/cursor/plugins/tree/main/pstack) | Blast-radius review, independent adversarial verification, and tracing *why* a design exists alongside *how* the code works. Excludes the pstack router, automatic PR engine, and mandatory multi-model tournaments. | [2026-11-02 adoption commit](https://github.com/LazyGreed/quintet/commit/a1fe9997661105c54083f7ab87e513c016cd831b); `agents/nora.md`, `agents/vera.md` |
| [Matt Pocock's engineering skills](https://github.com/mattpocock/skills) | Historical `codebase-design` and `domain-modeling` skills explicitly credited his work. Deep modules, seams, vocabulary, invariants, and change locality remain in `architecture` and `domain-modeling`. | [Early skill tree](https://github.com/LazyGreed/quintet/tree/c424552f0c601fb5575278691b5b926c0f067a31/skills), [consolidation](https://github.com/LazyGreed/quintet/commit/48c0361c0fb7691dafbbb6a4ef84f410154d27cb), `skills/architecture/`, `skills/domain-modeling/` |
| [mshumer/unslop](https://github.com/mshumer/unslop) | Historical `unslop` skill credited its core rule: remove model-default phrasing without losing technical facts. Folded into documentation-editing guidance rather than a standalone skill. | [Historical unslop skill](https://github.com/LazyGreed/quintet/blob/364aa919b0f8ad6201f41a25bba5773397300464/skills/unslop/SKILL.md); `skills/documentation/references/editing.md` |
| [miqdadbadjuber/anti-slop](https://github.com/miqdadbadjuber/anti-slop) | **Historically included** core and specialized skills for UI, copy, comments, accessibility, and responsive design; later removed with condensed general guidance retained. Do not claim the full suite is installed. | [2026-10-10 skill addition](https://github.com/LazyGreed/quintet/commit/8ba96676ef189a1a0ca6f2afcdd5be378829cafb); [2026-10-15 consolidation](https://github.com/LazyGreed/quintet/commit/48c0361c0fb7691dafbbb6a4ef84f410154d27cb) |

## Earlier implementations and tool lineage

| Source | Historical relationship | Evidence |
| --- | --- | --- |
| [nathanstephenson/pi-subagents](https://github.com/nathanstephenson/pi-subagents) | Earlier Pi subagent backend, **superseded** by tintinweb's implementation. | [2026-10-15 installer](https://github.com/LazyGreed/quintet/commit/48c0361c0fb7691dafbbb6a4ef84f410154d27cb), [2026-10-18 migration](https://github.com/LazyGreed/quintet/commit/eb9230875c4ee44b4cb0a1ad3dbdd4c638e9174e) |
| [pi-warden](https://github.com/DevMortimer/pi-warden) | Included in the original Pi package list with a `pi-warden/config.json` directory; **not** a current Quintet prerequisite. | [2026-09-28 historical tree](https://github.com/LazyGreed/quintet/tree/c424552f0c601fb5575278691b5b926c0f067a31), earlier `settings.json` |
| [pi-blackhole](https://github.com/k0valik/pi-blackhole) | Former Pi example package and bundled compaction config. The installer does not install either or remove user-managed copies. | [Earlier configuration](https://github.com/LazyGreed/quintet/tree/c424552f0c601fb5575278691b5b926c0f067a31/pi-blackhole) |

## Consulted or compared, not verified as implemented

> [!NOTE]
> These sources were discussed during Quintet/Albert development, but **a review or recommendation is not evidence of a merged implementation**.

| Source | What was evaluated | Status |
| --- | --- | --- |
| [Cloudflare security-audit-skill](https://github.com/cloudflare/security-audit-skill) and [Skills CLI](https://skills.sh/) | Cross-harness skill distribution using `npx skills add` as an alternative to `install.sh`. | **Consulted only.** No corresponding distribution workflow exists. |
| [Microsoft TokenEconomizer](https://github.com/microsoft/TokenEconomizer), [research paper](https://arxiv.org/abs/2610.22732) | Handoff efficiency, adaptive delegation, avoiding repeated failed attempts, and tool economy. | **Consulted only.** No TokenEconomizer runtime or cross-session memory system added; Quintet uses native session state. |
| `pybot-msgboard` (previous discussion; URL not verifiable) | Peer-to-peer agent coordination and messaging patterns. | **Exploratory comparison.** No standalone message board or peer broker in Quintet; `docs/peer-messaging.md` covers native host transports. |

## Maintenance and attribution rules

- Record meaningful influences **even after the original files are removed or consolidated**, linking a primary upstream source and the Quintet commit or historical file establishing the relationship.
- Specify the exact relationship (**required dependency**, **optional integration**, **direct adaptation**, **historical**, **compatibility reference**, or **consulted only**) without implying code reuse where none occurred.
- Link to relevant Quintet implementation or configuration files, and record tested upstream versions/commits where behavior depends on them.
- Preserve all required copyright notices and license terms for copied or adapted material; this catalogue does not replace a repository license or third-party notices file.
- Keep speculative proposals out of the adopted list until backed by an implementing commit and verifiable file path.

---

_Historical catalogue reviewed against Quintet `main` at [6a3b169](https://github.com/LazyGreed/quintet/commit/6a3b16953b5eec86cc99b9b007cc106610caefab); weight-space audit entry added 2026-11-24 from the supplied skill bundle._
