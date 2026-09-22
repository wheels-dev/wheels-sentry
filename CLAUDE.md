# wheels-sentry

## What This Is

A Wheels framework package for [Sentry](https://sentry.io) error tracking. Provides automatic SDK initialization, controller mixin methods for exception capture/messaging/breadcrumbs, configurable scope capture, and PII controls.

This package is part of the Wheels first-party package collection, hosted in the main Wheels repository under `packages/sentry/`. Install with `wheels packages add wheels-sentry` (into `vendor/wheels-sentry/`).

## Package Architecture

Standard Wheels package with two CFCs:
- `Sentry.cfc` — main package CFC with controller mixin methods (`sentryCapture`, `sentryMessage`, `sentrySetUser`, `sentryAddBreadcrumb`)
- `lib/SentryClient.cfc` — HTTP transport layer that sends events to the Sentry API (kept OUT of the package root: the loader resolves a package's entry point from the root CFCs, and two of them made that choice filesystem-dependent — wheels-dev/wheels#3639)

PackageLoader discovers this via `package.json` (`"main": "Sentry"`) and injects public methods from `Sentry.cfc` into controllers.

## File Structure

```
packages/sentry/
├── CLAUDE.md              # This file
├── Sentry.cfc             # Main package CFC — controller mixins
├── lib/SentryClient.cfc   # HTTP client for Sentry API
├── package.json           # Package manifest (mixins: controller)
├── index.cfm              # Package info page (Wheels debug panel)
├── box.json               # CommandBox package metadata
├── README.md              # User-facing documentation
└── tests/
    └── SentrySpec.cfc     # WheelsTest BDD specs
```

## Configuration

All settings via `set()` in `config/settings.cfm`:

```cfml
set(sentryDSN="https://your-key@o123.ingest.us.sentry.io/456");
set(sentrySendDefaultPii=false);      // master PII toggle
set(sentryIncludeHeaders=true);       // HTTP headers
set(sentryIncludeServerContext=true);  // server name, port, etc.
set(sentryIncludeUser=false);         // follows sentrySendDefaultPii
set(sentryIncludeSession=false);      // follows sentrySendDefaultPii
set(sentryIncludeCookies=false);      // follows sentrySendDefaultPii
```

## Controller Mixin Methods

- `sentryCapture(exception, level, additionalData)` — capture an exception
- `sentryMessage(message, level)` — send a message event
- `sentrySetUser(struct)` — set user context (`id`, `email`, `username`)
- `sentryAddBreadcrumb(message, category, data)` — add a breadcrumb

## Testing

Tests verify mixin method signatures and DSN parsing. No live Sentry connection needed.
