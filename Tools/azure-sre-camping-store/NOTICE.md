# Attribution and provenance

Adapted from [aj-enns/sre-agent-camping-store](https://github.com/aj-enns/sre-agent-camping-store)
at commit `bdae0e522379bbf1f6ba0c0fac2e772157fe65b4`: Camping Store application,
tests, infrastructure, and SRE custom-agent definitions. The source history
describes the package as based on Microsoft's starter lab.

The storefront, product photography, product-detail experience, presentation
server, and its regression tests were subsequently restored from source main
commit `9e8e03b01b0b8994198c34ac814d5f9a108cb3f6`. The initial snapshot above
was a stale local checkout and did not contain the current original UI.

Upstream: [microsoft/sre-agent, labs/starter-lab](https://github.com/microsoft/sre-agent/tree/6c6c48b4ff558f6b6858e2eb6a3a34198f3f6bc0/labs/starter-lab).
The Microsoft MIT notice is retained verbatim in [LICENSE-MICROSOFT](LICENSE-MICROSOFT).
That commit identifies the upstream/license snapshot inspected during integration,
not a claim that every imported file exactly matches that upstream revision.

The source repository did not contain a license. Its owner explicitly authorized
contributing their original Camping Store additions under MIT on 2026-11-17;
see [LICENSE](LICENSE). No license file was added to or changed in the source
checkout. Dependencies retain their respective licenses through NuGet/npm.
Bundled photographs are **not relicensed under MIT**: see the original
[image credits](src/frontend/IMAGE-CREDITS.md) for Pexels and Unsplash sources
and license links. Preserve those credits when redistributing the photos.

Showcase adaptations: resource-group read-only agent RBAC, disabled-by-default
memory fault, separated approval-gated operator commands, optional explicit
GitHub target, curated knowledge, documentation, and offline validation. The
original autonomous GitHub write/scheduled triage flows are intentionally not
enabled. Presentation-generation tooling and source-specific workshop handouts
are not included.
