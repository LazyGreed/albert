# References and acknowledgements

Quintet began as a personal Pi and Claude Code setup and later used the name
Albert. This catalogue records active integrations, adapted ideas, former
integrations, and sources consulted during development.

## Workflow lineage

- [Archived v1][v1] contains the coordinator-sequenced workflow before the
  shared installer. The [archived v2][v2] contains the original graph-aware
  contract. Both workflows now use the same profiles and approval boundaries.
- Kanade's supplied *Quintet Graph-Aware Coordination: Final Proposal*,
  revision v3 targeting `6715d8d5`, informed the v2 readiness, invalidation,
  and join rules. The proposal's revision number is independent of the
  installer workflows. The overlap helper and experiment branches remain
  deferred. [Dependency graph](workflow.md#dependency-graph)
- The Git [`diff`][git-diff], [`status`][git-status], and
  [`worktree`][git-worktree] manuals informed path comparison, cleanliness
  checks, and trial checkouts. Quintet adopted prompt rules based on these
  operations.

## Native interfaces and web access

- [Pi coding agent][pi] is a supported harness. [tintinweb/pi-subagents][pi-agents]
  supplies the required Pi profiles, steering, FleetView, parallel runs, and
  round summaries. Quintet defines the workstream rules.
  [Integration][pi-integration] · [Reporting][pi-report]
- [Claude Code subagents][claude] supply its native profiles.
  [Claude Code agent teams][claude-teams] can also expose peer messaging.
- [Antigravity CLI][agy] supports [custom subagents][agy-agents]. An active
  [Antigravity swarm][agy-swarm] can expose optional peer messaging. Start and
  manage the swarm in Antigravity.
- [Oh My Pi][omp] is a peer messaging compatibility reference. Availability
  of `agent://` depends on the active runtime. [Peer messaging](peer-messaging.md)
- [pi-web-access][pi-web] supplies Pi search and fetch when enabled.

## Research and design influences

- *The Alien Space of Science: Sampling Coherent but Cognitively Unavailable
  Research Directions* inspired the opt-in Alien Science Ideation skill.
  Quintet uses a prompt-level heuristic with qualitative, uncalibrated
  scores. The paper's trained coherence and availability models are outside
  that integration. [Paper][alien-paper] · [Authors' code][alien-code]
- Nusrat and Nusrat's *Weight-space programming for auditing clinical decision
  networks* informed protocol-based black-box tests, weight-space diagnosis,
  sampled verification, minimal edits, regressions, and deployment-precision
  checks. Quintet drew from the supplied `Weight space network audit-v1.zip`.
  The preprint studies small synthetic ReLU networks. Broader workflows and
  clinical validity need separate evidence. [Preprint][weight-paper] ·
  [Skill references](../skills/weight-space-network-audit/references/)
- Lauren Tan's [Cursor pstack][pstack] informed blast-radius review,
  independent adversarial checks, and tracing the reasons behind a design.
  Quintet adopted those review practices. The pstack router, automatic PR
  engine, and mandatory multi-model tournaments were outside the adoption.
  [Adoption commit][pstack-adoption] · [Nora](../agents/nora.md) ·
  [Vera](../agents/vera.md)
- [Matt Pocock's engineering skills][pocock] informed the early
  `codebase-design` and `domain-modeling` skills. Deep modules, seams,
  vocabulary, invariants, and change locality remain in `architecture` and
  `domain-modeling`. [Early skill tree][early-skills] ·
  [Consolidation commit][skill-consolidation]
- [mshumer/unslop][unslop] informed the historical `unslop` skill and the
  current guidance on removing model-default phrasing while keeping technical
  facts. [Historical skill][historical-unslop] ·
  [Editing guidance](../skills/documentation/references/editing.md)
- [miqdadbadjuber/anti-slop][antislop] supplied historical UI, copy, comment,
  accessibility, and responsive design skills. The later consolidation kept
  general editing guidance. [Skill addition][antislop-addition] ·
  [Consolidation commit][skill-consolidation]

## Earlier integrations

- [nathanstephenson/pi-subagents][old-pi-agents] was the earlier Pi subagent
  backend, superseded by tintinweb's package. [Earlier installer][skill-consolidation]
  · [Backend migration][pi-integration]
- [pi-warden][warden] appeared in the original Pi package list and had a
  bundled config. Current installs do not require it. [Historical tree][early-tree]
- [pi-blackhole][blackhole] appeared as an example Pi package with bundled
  compaction config. The current installer leaves existing registrations and
  user-managed copies intact. [Earlier configuration][early-blackhole]

## Consulted sources

- [Cloudflare security-audit-skill][cloudflare] and [Skills CLI][skills-cli]
  came up when evaluating `npx skills add` as a cross-harness distribution
  path. Quintet ships its own installer.
- [Microsoft TokenEconomizer][token-code] informed discussion of handoff
  efficiency, delegation, and repeated failed attempts. Quintet uses native
  session state. [Research paper][token-paper]
- `pybot-msgboard` was discussed as a peer coordination example. Its URL
  remains unverified. Quintet uses the harness's native transports.

For new attributions, record the original source, the exact relationship,
and the Quintet revision or file that establishes it. Preserve applicable
copyright and license terms for adapted material. Add proposals to the
adopted list once an implementing commit exists.

The historical catalogue was reviewed against [Quintet at `6a3b169`][catalogue].
The weight-space audit entry was added on 2026-11-24 from the supplied bundle.

[v1]: https://github.com/LazyGreed/quintet/tree/460f9e9c4ce2d057d9fb72365489fe9a132c03af
[v2]: https://github.com/LazyGreed/quintet/tree/73742e6760a2533224f58b5e3cb1c507824c1af5
[git-diff]: https://git-scm.com/docs/git-diff
[git-status]: https://git-scm.com/docs/git-status
[git-worktree]: https://git-scm.com/docs/git-worktree
[pi]: https://github.com/earendil-works/pi
[pi-agents]: https://github.com/tintinweb/pi-subagents
[pi-integration]: https://github.com/LazyGreed/quintet/commit/eb9230875c4ee44b4cb0a1ad3dbdd4c638e9174e
[pi-report]: https://github.com/LazyGreed/quintet/commit/0503e78aa614fa6e4a3f9d9918726200281bb980
[claude]: https://code.claude.com/docs/en/sub-agents
[claude-teams]: https://code.claude.com/docs/en/agent-teams
[agy]: https://github.com/google-antigravity/antigravity-cli
[agy-agents]: https://antigravity.google/docs/subagents
[agy-swarm]: https://antigravity.google/docs/swarm/
[omp]: https://github.com/can1357/oh-my-pi
[pi-web]: https://github.com/nicobailon/pi-web-access
[alien-paper]: https://arxiv.org/abs/2603.01092
[alien-code]: https://github.com/alejandrohdez00/alien-space-of-science
[weight-paper]: https://arxiv.org/abs/2611.05341v1
[pstack]: https://github.com/cursor/plugins/tree/main/pstack
[pstack-adoption]: https://github.com/LazyGreed/quintet/commit/a1fe9997661105c54083f7ab87e513c016cd831b
[pocock]: https://github.com/mattpocock/skills
[early-skills]: https://github.com/LazyGreed/quintet/tree/c424552f0c601fb5575278691b5b926c0f067a31/skills
[skill-consolidation]: https://github.com/LazyGreed/quintet/commit/48c0361c0fb7691dafbbb6a4ef84f410154d27cb
[unslop]: https://github.com/mshumer/unslop
[historical-unslop]: https://github.com/LazyGreed/quintet/blob/364aa919b0f8ad6201f41a25bba5773397300464/skills/unslop/SKILL.md
[antislop]: https://github.com/miqdadbadjuber/anti-slop
[antislop-addition]: https://github.com/LazyGreed/quintet/commit/8ba96676ef189a1a0ca6f2afcdd5be378829cafb
[old-pi-agents]: https://github.com/nathanstephenson/pi-subagents
[warden]: https://github.com/DevMortimer/pi-warden
[early-tree]: https://github.com/LazyGreed/quintet/tree/c424552f0c601fb5575278691b5b926c0f067a31
[blackhole]: https://github.com/k0valik/pi-blackhole
[early-blackhole]: https://github.com/LazyGreed/quintet/tree/c424552f0c601fb5575278691b5b926c0f067a31/pi-blackhole
[cloudflare]: https://github.com/cloudflare/security-audit-skill
[skills-cli]: https://skills.sh/
[token-code]: https://github.com/microsoft/TokenEconomizer
[token-paper]: https://arxiv.org/abs/2610.22732
[catalogue]: https://github.com/LazyGreed/quintet/commit/6a3b16953b5eec86cc99b9b007cc106610caefab
