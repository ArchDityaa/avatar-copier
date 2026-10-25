# Changelog

All notable changes to Avatar Copier are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.6.0 — 2026-10-25

### Reworked

- **The preview is now an anchored puppet that copies part positions
  directly.** Every preview part is anchored, and every frame the follow loop
  copies the CFrame of the matching part of your real character. The preview
  therefore reproduces your exact pose — walking, jumping, sitting, swimming,
  emotes — with no Animator, no second physics rig, and no cross-rig copying.
- `sanitizeOverlay` strips every `JointInstance` (`Motor6D`, `Weld`,
  `WeldConstraint`, `AccessoryWeld`, …), so no leftover joint solve can fight
  the puppet or the local physics.
- Pairing is by part name/class (accessory handles pair through their
  accessory), with an ordered fallback pass for non-standard rigs.

### Fixed

- The v1.5.0 Animator-track sync scrubbed `TimePosition` every frame, which
  made previews stutter, drift, or appear to fly while walking. Direct CFrame
  copying removes that failure mode entirely.

### Changed

- Version bumped to `1.6.0`.
- Headless tests grew from `150` to `151` checks per profile (mobile and
  desktop): the Animator suite was replaced by puppet assertions (no joints,
  no animation machinery, all parts anchored, part CFrames mirrored, and the
  follow loop re-hides the real character after a camera zoom).

## 1.5.0 — 2026-10-25

### Reworked

- **Animations are now mirrored through `Animator` tracks, not `Motor6D`
  transforms.** The old pose-copying approach wrote `Motor6D.Transform` values
  from your rig into the preview's joints every frame — with rigs that do not
  match (in-server clones with game-specific joints, R6 vs R15 mixes), that
  sheared body parts and looked glitchy. Now the preview's own fresh
  `Animator` replays exactly the tracks you are playing (same Animation asset,
  speed, weight, and time position), which is correct for any rig and cannot
  twist the preview apart.
- **The target's animation machinery is destroyed.** Sanitization removes the
  cloned `Animator`, `AnimationController`, `Animation`, and `AnimationTrack`
  instances from the preview, then attach builds a brand-new `Animator` that
  only ever loads tracks from your own Humanoid. Cloning the avatar of someone
  in your server can no longer carry their animation state with it.
- Copying a rig family that differs from yours (R6 target on an R15 rig or
  vice versa) skips the animation sync instead of playing mismatched tracks.

### Fixed

- The preprocessing of the real character now re-applies
  `LocalTransparencyModifier` every frame. The Roblox engine recalculates that
  property when the camera zooms, which used to make your real character fade
  back in while using the preview.
- The follow loop no longer dies silently on the first failed frame (for
  example mid-respawn): it tolerates glitches and only stops after roughly
  half a second of continuous failures, telling the status card about it.

### Added

- **Automatic re-apply after respawn.** The last typed target is remembered;
  when your character respawns, the preview is rebuilt on the new character
  without you copying again. A manual **Reset** cancels the auto re-apply.

### Changed

- Version bumped to `1.5.0`.
- Headless tests grew from `141` to `150` checks per profile (mobile and
  desktop), covering the fresh `Animator`, animation-track mirroring
  (speed/time position/stop), no target-animation leakage, and respawn
  auto re-apply plus its cancellation after Reset.

## 1.4.0 — 2026-10-25

### Fixed

- Walking with the mobile analog while an avatar preview was active no longer
  makes the character auto-jump. The preview previously shared a physics
  assembly with the real rig through a `WeldConstraint`, and the preview
  Humanoid still ran its state machine with leftover constraint movers — the
  combined assembly could inject impulses into the local Humanoid while moving.
- The preview root is now `Anchored` and follows the real character every
  `RenderStepped`; nothing is welded to the live rig anymore.
- The preview Humanoid state machine is fully disabled
  (`EvaluateStateMachine = false` plus `SetStateEnabled(false)` for every
  state), and sanitization now also strips constraint-based movers
  (`AlignPosition`, `AlignOrientation`, `LinearVelocity`, `VectorForce`,
  `Torque`, `AngularVelocity`) from the preview.

### Added

- **Minimize** button in the title bar: the window collapses to just the title
  bar (still draggable) and restores with one tap. Visibility of controls like
  the input clear button is remembered while collapsed.
- **Floating pill**: the close button (`×`) now only hides the interface while
  the avatar preview stays active. A small draggable "A" pill lets you bring
  the interface back. Full teardown (including the preview) is available from
  **Reset**, `AvatarCopier.destroy()`, and the re-execution cleanup hook.

### Changed

- Version bumped to `1.4.0`.
- Headless tests grew from `119` to `141` checks per profile (mobile and
  desktop), covering the anchored follow behavior, state machine shutdown,
  constraint-mover stripping, minimize collapse/restore, and close/pill
  lifecycle.
- READMEs updated to describe the new window controls and fault-free follow.

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
