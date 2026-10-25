# Changelog

All notable changes to Avatar Copier are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.3.0 — 2026-10-25

### Fixed

- Copying an avatar no longer calls `ApplyDescription*` on the LocalPlayer's
  real Humanoid. Roblox restricts that API to the backend server for
  server-owned characters, which caused the reported `Humanoid::ApplyDescription()
  can only be called by the backend server` error. Avatar Copier now builds a
  client-only preview rig and never touches the real Humanoid.
- Handled preview failures are now copied to the clipboard automatically. Fetch,
  model-build, and attach failures produce a report with the target, resolved
  user ID, avatar source, attempted methods, error, UTC timestamp, and
  traceback. Previously only unexpected Lua errors were copied.
- Reset and destroy now restore `LocalTransparencyModifier`, `Decal.Transparency`,
  Humanoid display settings, and effect visibility even when the old property
  value was unset.
- Re-executing the script now calls the previous instance's cleanup hook, so
  old UserInputService connections and overlay models do not leak.

### Added

- Client-only overlay preview built from an in-server character clone, a
  `HumanoidDescription` model, a user-ID model, a local-rig clone with
  `ApplyDescription`, or a partial appearance copy, in that fallback order.
- Overlay sanitization: scripts, sounds, tools, prompts, billboards, body movers,
  collisions, touches, raycast hits, walking, jumping, and name/health displays
  are disabled.
- The overlay is welded to the real `HumanoidRootPart` and mirrors matching
  `Motor6D.Transform` values every `RenderStepped`.
- The real character is hidden locally without changing replicated
  `Transparency`.
- `CharacterAdded` cleanup, stale-overlay cleanup on startup, and full teardown
  from **Reset**, the close button, and `AvatarCopier.destroy()`.
- Programmatic `AvatarCopier.isPreviewing()` and `AvatarCopier.getTarget()`.
- Headless tests cover the overlay, weld, sanitization, pose mirroring, hide and
  restore, fallback chain, partial preview, clipboard diagnostics, respawn, and
  destroy cleanup (`119` checks per profile).

### Changed

- Version bumped to `1.3.0`.
- UI footer now says `Local preview — other players can't see it.`
- Success status is `Previewing <name> (local only)`; reset says
  `Back to your own avatar.`
- Cooldown now throttles every attempt, including failed lookups.
- README and Indonesian README describe the overlay architecture, fallbacks,
  new API members, error-report behavior, and updated limitations.

## 1.2.0 — 2026-10-25

### Added

- Automatic crash reports: unexpected Luau errors are caught during startup,
  GUI construction, button handlers, copy/reset operations, and API calls.
- Reports include the script version, UTC timestamp, failure context, error
  message, and stack trace, then are copied with `setclipboard`,
  `toclipboard`, or `writeclipboard`.
- Console fallback and a clear warning when the executor has no clipboard API.
- The status card reports that details were copied, and controls recover from
  an unexpected error instead of staying stuck in the busy state.
- Headless tests cover clipboard output, context, traceback, status recovery,
  and a failed copy pipeline (`57` checks per profile).

## 1.1.0 — 2026-10-25

### Added

- Redesigned interface: header with logo tile and version pill, labelled target
  field, search icon, clear button, dedicated status card, privacy footer, and an
  accent focus ring on the input.
- Responsive `UIScale` that keeps the window inside small viewports.
- Colour-coded status states (idle, loading, success, warning, error) with a
  tinted status card and indicator dot.
- Disabled controls while a copy is running, with a `Copying...` label.
- `docs/preview.svg` interface preview.
- Indonesian README (`README.id.md`) and this changelog.

### Changed

- Window dimensions increased from `300×196` to `320×272` with larger touch
  targets (close button `32×32`, action buttons `40` px tall).
- The input no longer clears itself on focus; the clear button handles that
  explicitly.
- Reset is blocked while a copy is in progress to avoid conflicting applies.
- README rewritten with quick start, compatibility, API, architecture, privacy,
  FAQ, and roadmap sections.

### Fixed

- Closing the interface no longer assumes the `ScreenGui` still exists.
- The copy flow re-checks the destroyed state after the character lookup.

## 1.0.1

### Fixed

- Parented the window to the `ScreenGui` instead of leaving the panel detached
  (v1.0.0 regression).
- Added explicit feedback when a copy is blocked and improved parent-attach
  diagnostics.

### Added

- Headless Luau mock harness, Selene configuration, and CI.

## 1.0.0

- Initial release: copy a Roblox avatar by username, user ID, or profile URL and
  apply it locally.
