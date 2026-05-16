# Changelog

All notable changes to this package will be documented in this file.

## [1.0.1] — 2026-05-16

### Fixed
- `wheels packages add wheels-sentry` no longer leaves the client silently broken. `Sentry.cfc:79` still instantiates `new plugins.sentry.SentryClient(...)`, which only resolved when the package was hand-installed into `plugins/sentry/`. With `wheels packages add` installing to `vendor/wheels-sentry/`, the dotted path failed silently inside `initSentry()`'s try/catch and no events were ever emitted. Fixed by declaring `"mappings": {"plugins.sentry": "."}` in `package.json` so the loader (wheels-dev/wheels#2705) registers the legacy alias against the install directory. No application-side changes required. Fixes wheels-dev/wheels#2705.

### Requirements
- Wheels `>=4.0` (the `mappings` block is read by the framework's `PackageLoader.cfc` shipped in 4.0.1).

## [1.0.0] — 2026-04-23

### Added
- Initial standalone release, extracted from the Wheels monorepo at `packages/sentry`.
- Git history preserved from the monorepo's package directory.
- Published to the `wheels-dev/wheels-packages` registry for installation via `wheels packages install` (coming in Wheels 4.1).
