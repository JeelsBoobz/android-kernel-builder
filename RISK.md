# Risk register: every modification vs stock GKI

Scale: **LOW** = in-tree mature code, or additive + verified, off the boot
path. **MEDIUM** = out-of-tree or boot-adjacent, but toggleable and
fleet-tested. **HIGH** = nothing shipped (see rejected list). Grades are
revisited whenever a build proves otherwise.

## Kconfig fragments (all built-in posture)

| # | Fragment | Grade | Why |
|---|---|---|---|
| 1 | metamodule (OVERLAY_FS, FUSE_FS, TMPFS*, SECURITYFS, CONFIGFS_FS) | LOW | Mature VFS primitives; module tooling needs them, nothing auto-loads |
| 2 | bbr (ADVANCED=y, BBR=y, BIC/WESTWOOD/HTCP off) | LOW | BBR mature; default CC stays CUBIC; stragglers explicitly off |
| 3 | wireguard | RETIRED | Stock =y on all six trees (verified defconfigs) — fragment is a no-op, parked permanently |
| 4 | cake | LOW | Dep-less qdisc, tc opt-in only |
| 5 | cifs (+XATTR, POSIX) | LOW | In-tree SMB client, mount-gated; 6.12 module-list handled at build time |
| 6 | ipset family | LOW | Mature netfilter, no auto-path, no boot-insmod (verified zero defaults) |
| 7 | usb-mass-storage (CONFIGFS gadget) | RETIRED | Sole symbol stock =y everywhere — fragment was a proven no-op, deleted |
| 8 | usb-serial (5.10 only, =y) | LOW | build.sh era has no module-outs check; 5.15+ stays =m (Kleaf staging) |
| 9 | zswap (6.6 only) | MEDIUM | Core-mm adjacent but mature code; KMI/module-outs block all other trees, non-6.6 copies dropped |
| 23 | udf (common) | LOW | CIFS-shaped: dormant till mount, selects core only, zero module-outs on 6.12/6.18 |
| 24 | ntsync (6.18-only) | LOW | Dep-less tristate, sole-tree symbol, dormant char device, no interaction with any integration |

## Dropped (queue stopped here; files deleted, rationale kept)

| # | Fragment | Why dropped |
|---|---|---|
| P1 | usb-rndis | ACTIVATED (live, green across the matrix) — no longer parked |
| P2 | ntfs3 per-branch (5.15+) | ACTIVATED (live, pending green run) — no longer parked |
| P3 | ntsync 6.18-only | Never attempted; queue stopped before it |
| — | zswap/zbud/frontswap (non-6.6) | KMI allowlist (5.10/5.15/6.1) + module-outs (6.12) block them per-tree; 6.6 copy live |
| — | mtk-ufs (5.10) | Unproven experiment; stock boots via vendor UFS modules, premise never validated |

## Out-of-tree sources

| # | Integration | Grade | Why |
|---|---|---|---|
| 10 | KernelSU-Next driver | MEDIUM | Privileged hook surface (execve/kallsyms/SEPolicy), but huge fleet, toggleable (`ksu=false`), version-churn contained (6.18 policydb) |
| 11 | NoMount VFS redirection | MEDIUM | Path interposition, RAM-only, smaller fleet than KSU, toggleable |
| 12 | Partition Guard LSM | LOW | Own ~400-line deny-only LSM; audited per tree (5.10→6.18 API table); fail-open; narrow scope (NVRAM/persist/EFS) |
| 22 | SuSFS root hiding | MEDIUM | Experimental, default-off; 23-file VFS hook surface but payload byte-identical across versions + version-matched 50_ patch; KSU side carried by dev-susfs (no 10_ patch); drift includes dropped-then-restored (tree needs what patch base removed); 6.18 + 6.6 + 6.12 KSU-only via suppression (no branch / SELinux _with_policy predates tree; pinning to pre-API parents rejected) |

## Build-time tree mutations

| # | Mutation | Grade | Why |
|---|---|---|---|
| 13 | KSU version bake (Kbuild fallback sed) | LOW | Values only, upstream warnings untouched, fail-fast verification |
| 14 | drop-stale-module-outs (6.12 netfs.ko) | LOW | One-line delete, version- + selector-gated, missing-entry fails fast (method: WildKernels) |
| 15 | Makefile/Kconfig hooks + LSM list append | LOW | Additive, idempotent, verified present |
| 16 | Tree commit before compile (anti `-dirty`) | LOW | No semantic change, version string only |
| 17 | magiskboot v30.7 (AK3 tools refresh) | LOW | Upstream binary, runs at flash time only |
| 18 | AK3 template + raw `Image` | LOW | `BLOCK=boot` (kernel always in boot on userspace) slot-aware; raw image (compressed panics at decompress) |

## Process risks

| # | Item | Grade | Why |
|---|---|---|---|
| 19 | KSU `dev` tracking on 6.18 | MEDIUM | Moving target, but contained to one tree; source sha now logged per build |
| 20 | `_dist` strictness (our choice) | MITIGATION | Fails loud (module-outs, check_defconfig, KMI) where Image-only pipelines stay green-and-wrong |
| 21 | Whole-disk/GPT writes vs guard | ACCEPTED | Partition-node guard by design; whole-LUN offsets out of scope (documented, containment offered) |

## Considered and rejected (would-be HIGH)

- CloudFox `MODULE_SKIP_BUILTIN` loader shim — global loader semantics, per-tree `module.c` patch. Stayed `=m`.
- lz4kd/lz4kdr zram rework — 3k-line out-of-tree compression stack. Parked.
- BBRv3 backport, scheduler tweaks, SukiSU — API drift / review burden.
- NTFS3 in common — absent on 5.10, cannot be shared.
- CIFS as `=m` anywhere — its `.ko` is undeclared everywhere; `=y` or off.
