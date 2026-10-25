# Changelog

All notable changes to Avatar Copier are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
