# Changelog

All notable changes to this package will be documented in this file.

## [1.0.2] — 2026-09-21

### Fixed
- **The package can now actually initialise.** `initSentry()` read its configuration with `get("sentryDSN")`, but a package CFC does not inherit `wheels.Global`, so that helper is undefined inside this component: the call threw, the surrounding `catch` swallowed it, and **every** setting returned its default. `set(sentryDSN="...")` therefore looked ignored and the package logged a clean load while never creating a client or emitting an event. Settings are now read from the same struct `get()` reads (`application.wheels` / `application.$wheels`), via `$sentrySetting()`.
- **The entry point is declared.** `package.json` now carries `"main": "Sentry"`, and the HTTP transport moved from the package root to `lib/SentryClient.cfc`. Both exist because package loading resolved the entry point as "`<dirName>.cfc`, else the FIRST `*.cfc` from an unsorted directory listing" (wheels-dev/wheels#3639): with two root CFCs, `wheels-sentry` booted whichever one the filesystem returned first — on Lucee that was `SentryClient.cfc`, whose `init()` requires arguments, so the package failed with `The parameter [release] to function [init] is required but was not passed in`. `main` fixes it on a fixed loader, and the single root CFC fixes it on Wheels 4.0–4.1.1 as well.
- **The transport resolves without a mapping.** `new plugins.sentry.SentryClient(...)` only ever resolved when the legacy `plugins.sentry` mapping existed — and on Lucee a mapping the loader registers at runtime does not resolve at all (the entry is written to `application.mappings` and never consulted). `$buildClient()` now tries the declared alias first (for engines and applications that do declare it) and falls back to the install path `wheels packages add` guarantees, logging which rung was used.

### Changed
- `$sentrySetting()` and `$buildClient()` are public so specs can prove configuration reaches the package.
- Tests cover the settings read, the boolean setting read and the two-rung transport resolution, and the transport references moved to `plugins.sentry.lib.SentryClient`.

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
