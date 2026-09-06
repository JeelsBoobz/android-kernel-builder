# Build variants (build-kernel.yml)

Each file is the full model for a fleet: global toggles under `defaults`
plus one record per version under `branches` (branch, LTS fallback,
manifest, build era, KSU ref). The workflow only executes what the JSON
says — no branch list lives in YAML.

| Variant | susfs | bbrv3 | use |
|---|---|---|---|
| `plain` | off | on | clock (6h validation fleet) |
| `susfs` | on | on | manual SuSFS validation + releases |

Dispatch has 4 inputs: `variant`, `branch` (default `all`), `release`
(artifacts-only vs GitHub Release), `forward` (Telegram forward, default
off). `release` and Telegram are never in the JSON: every release posts
to Telegram, always. `detect-upstream` dispatches `susfs` + `release=true`
on new upstream tips.
