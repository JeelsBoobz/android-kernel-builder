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

Pins: none — parity lives in the records. `nomount_ref`/`guard_ref`
must be identical on all 8 branches (single upstream repos; the resolve
job fails otherwise). `ksu_ref` is the pinned SHA everywhere except
6.6/6.18, which stay on plain-dev SHA (proven combo, no SuSFS hooks
needed). `susfs_ref` empty = per-version branch tip (one SHA can't span
5.10→6.12 branches).
