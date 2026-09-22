/**
 * wheels-sentry — Wheels package for Sentry error tracking.
 *
 * Provides automatic SDK initialization, controller mixin methods for
 * capturing errors/messages with Wheels context, and breadcrumb support.
 *
 * Mixin methods available in controllers:
 *   sentryCapture(exception, [level], [additionalData])
 *   sentryMessage(message, [level])
 *   sentrySetUser(userStruct)
 *   sentryAddBreadcrumb(message, [category], [data], [level])
 */
component mixin="controller" output="false" {

	function init() {
		this.version = "3.0";
		initSentry();
		return this;
	}

	/**
	 * Auto-initialize the Sentry SDK if a DSN is available.
	 * Reads from: (1) Wheels setting sentryDSN, (2) SENTRY_DSN env var.
	 * Stores the client in application.sentry.
	 */
	private void function initSentry() {
		if (structKeyExists(application, "sentry"))
			return;

		lock name="wheelsSentryInit" type="exclusive" timeout="10" {

		if (structKeyExists(application, "sentry"))
			return;

		try {
			var dsn = "";
			// `get()` is deliberately NOT used here. A package CFC does not inherit
			// wheels.Global ("Children inherit them; there is no per-instance mixin
			// copy" — vendor/wheels/global/settings.cfm), so `get("sentryDSN")`
			// throws "No matching function [GET] found" straight into the catch
			// below and EVERY setting silently took its default. That is why the
			// documented `set(sentryDSN="...")` appeared to be ignored, and why the
			// package could log a clean load while never emitting an event.
			dsn = Trim(ToString($sentrySetting("sentryDSN", "")));

			if (!len(dsn)) {
				var javaEnv = createObject("java", "java.lang.System").getenv("SENTRY_DSN");
				if (!isNull(javaEnv) && len(trim(javaEnv)))
					dsn = javaEnv;
			}

			if (!len(trim(dsn)))
				return;

			// Determine environment and release
			var appKey = structKeyExists(application, "wheels") ? "wheels" : "$wheels";
			var env = "development";
			if (structKeyExists(application, appKey) && structKeyExists(application[appKey], "environment"))
				env = application[appKey].environment;

			var rel = "unknown";
			try {
				var javaAppVersion = createObject("java", "java.lang.System").getenv("APP_VERSION");
				if (!isNull(javaAppVersion) && len(trim(javaAppVersion)))
					rel = javaAppVersion;
			} catch (any e) {}

			// Read scope settings with defaults
			var scopeSettings = {
				"sendDefaultPii":       $sentrySetting("sentrySendDefaultPii", false),
				"includeHeaders":       $sentrySetting("sentryIncludeHeaders", true),
				"includeServerContext":  $sentrySetting("sentryIncludeServerContext", true),
				"includeUser":          false,
				"includeSession":       false,
				"includeCookies":       false
			};

			// PII settings: individual overrides take precedence, otherwise follow sendDefaultPii
			var pii = scopeSettings.sendDefaultPii;
			scopeSettings.includeUser    = $sentrySetting("sentryIncludeUser", pii);
			scopeSettings.includeSession = $sentrySetting("sentryIncludeSession", pii);
			scopeSettings.includeCookies = $sentrySetting("sentryIncludeCookies", pii);

			var built = $buildClient(
				dsn = dsn,
				environment = env,
				release = rel,
				scopeSettings = scopeSettings
			);
			application.sentry = built.client;

			writeLog(
				text="wheels-sentry initialized (env=#env#, release=#rel#, pii=#pii#, client=#built.via#)",
				type="information",
				file="wheels-sentry"
			);
		} catch (any e) {
			writeLog(
				text="wheels-sentry initialization failed: #e.message#",
				type="error",
				file="wheels-sentry"
			);
		}

		} // end lock
	}

	/**
	 * Read a Wheels setting, with a fallback default.
	 *
	 * `get()` CANNOT be used here. A package CFC does not inherit wheels.Global
	 * ("Children inherit them; there is no per-instance mixin copy" —
	 * vendor/wheels/global/settings.cfm), so the framework helper is undefined
	 * inside this component. The previous implementation called it anyway, the
	 * throw was swallowed by the catch, and EVERY setting returned its default:
	 * `set(sentryDSN="...")` looked ignored and the package loaded cleanly
	 * without ever creating a client. This reads the same struct get() reads.
	 *
	 * PUBLIC so a spec can prove configured settings reach the package — this is
	 * the seam that was broken.
	 */
	public any function $sentrySetting(required string name, required any defaultValue) {
		// BOTH keys, in order. The framework builds settings in application.$wheels
		// (vendor/wheels/events/onapplicationstart.cfc:34) and mirrors them to
		// application.wheels only at the very end of application start (:450) —
		// while packages load in between (:426), so which struct holds the value
		// depends on WHEN this is called. Measured 2026-09-21: at package load
		// application.wheels existed but was EMPTY of settings, and reading only
		// that key returned the default for every setting (dsnLen=0 at boot,
		// 95 once the app was serving).
		for (local.appKey in ["$wheels", "wheels"]) {
			try {
				if (
					structKeyExists(application, local.appKey)
					&& structKeyExists(application[local.appKey], arguments.name)
				) {
					local.value = application[local.appKey][arguments.name];
					if (isBoolean(local.value)) {
						return local.value;
					}
					if (isSimpleValue(local.value) && len(trim(local.value))) {
						return local.value;
					}
				}
			} catch (any e) {
				// an unreadable settings scope must still yield the documented default
			}
		}
		return arguments.defaultValue;
	}

	/**
	 * Build the transport client and report WHICH component path resolved.
	 *
	 * WHY TWO RUNGS. The package declares `mappings: {"plugins.sentry": "."}`,
	 * and that alias is tried first: it works when the application also declares
	 * it in this.mappings, and on engines that honour a mapping registered at
	 * runtime. Lucee 7 does not — the loader writes the entry into
	 * application.mappings and the engine never consults it (wheels-dev/wheels
	 * #3639) — so the second rung uses the install path `wheels packages add`
	 * guarantees. Without this the package compiled a `new plugins.sentry.*`
	 * reference that only resolved for hand-installed copies, and the failure
	 * vanished into the initSentry() catch.
	 *
	 * `via` is logged so a "no events" report can be diagnosed from the log
	 * alone. PUBLIC so a spec can assert both rungs exist and the fallback works.
	 */
	public struct function $buildClient(
		required string dsn,
		required string environment,
		required string release,
		required struct scopeSettings
	) {
		local.args = {
			DSN: arguments.dsn,
			environment: arguments.environment,
			release: arguments.release,
			serverName: cgi.server_name,
			scopeSettings: arguments.scopeSettings
		};

		try {
			return {
				client: new plugins.sentry.lib.SentryClient(argumentCollection = local.args),
				via: "plugins.sentry.lib.SentryClient"
			};
		} catch (any mappingMiss) {
			// CreateObject takes the path as a STRING, so the hyphenated install
			// directory is fine here — a `new vendor.wheels-sentry.…` EXPRESSION is
			// a parse error ("Closing [}] not found"), which is exactly the kind of
			// failure this second rung exists to avoid.
			local.client = CreateObject("component", "vendor.wheels-sentry.lib.SentryClient");
			return {
				client: local.client.init(argumentCollection = local.args),
				via: "vendor.wheels-sentry.lib.SentryClient"
			};
		}
	}

	/**
	 * Capture an exception with Wheels controller/action context.
	 *
	 * @exception      The exception struct to capture.
	 * @level          Sentry level (default: "error").
	 * @additionalData Optional struct of extra data to attach.
	 */
	public void function sentryCapture(
		required any exception,
		string level = "error",
		any additionalData
	) {
		if (!structKeyExists(application, "sentry"))
			return;

		var eventTags = {};
		if (structKeyExists(variables, "params")) {
			var p = variables.params;
			if (structKeyExists(p, "controller"))
				eventTags["wheels.controller"] = p.controller;
			if (structKeyExists(p, "action"))
				eventTags["wheels.action"] = p.action;

			application.sentry.setRequestContext(
				controller: structKeyExists(p, "controller") ? p.controller : "",
				action: structKeyExists(p, "action") ? p.action : "",
				params: p
			);
		}

		var captureArgs = {
			exception: arguments.exception,
			level: arguments.level,
			useThread: true,
			showJavaStackTrace: true,
			userInfo: $sentryGetUser(),
			tags: eventTags
		};

		if (!isNull(arguments.additionalData))
			captureArgs["additionalData"] = arguments.additionalData;

		application.sentry.captureException(argumentCollection: captureArgs);
	}

	/**
	 * Capture a message with Wheels controller/action context.
	 *
	 * @message The message string to send to Sentry.
	 * @level   Sentry level (default: "info").
	 */
	public void function sentryMessage(
		required string message,
		string level = "info"
	) {
		if (!structKeyExists(application, "sentry"))
			return;

		var eventTags = {};
		if (structKeyExists(variables, "params")) {
			var p = variables.params;
			if (structKeyExists(p, "controller"))
				eventTags["wheels.controller"] = p.controller;
			if (structKeyExists(p, "action"))
				eventTags["wheels.action"] = p.action;

			application.sentry.setRequestContext(
				controller: structKeyExists(p, "controller") ? p.controller : "",
				action: structKeyExists(p, "action") ? p.action : "",
				params: p
			);
		}

		application.sentry.captureMessage(
			message: arguments.message,
			level: arguments.level,
			useThread: true,
			userInfo: $sentryGetUser(),
			tags: eventTags
		);
	}

	/**
	 * Set the Sentry user context for the current request.
	 * Call this in a before filter to attach user identity to all events.
	 *
	 * @userStruct Struct with id, email, username, ip_address, etc.
	 */
	public void function sentrySetUser(required struct userStruct) {
		request.sentryUserOverride = arguments.userStruct;
	}

	/**
	 * Add a breadcrumb for the current request.
	 *
	 * @message  Breadcrumb message.
	 * @category Category string (default: "controller").
	 * @data     Optional struct of extra data.
	 * @level    Sentry level (default: "info").
	 */
	public void function sentryAddBreadcrumb(
		required string message,
		string category = "controller",
		struct data = {},
		string level = "info"
	) {
		if (!structKeyExists(application, "sentry"))
			return;

		application.sentry.addBreadcrumb(
			message: arguments.message,
			category: arguments.category,
			data: arguments.data,
			level: arguments.level
		);
	}

	/**
	 * Build user info from request override. Returns empty struct if
	 * no user has been set via sentrySetUser() or if user inclusion is
	 * disabled. Applications should call sentrySetUser() in a before
	 * filter to attach user identity.
	 */
	private struct function $sentryGetUser() {
		if (structKeyExists(request, "sentryUserOverride"))
			return request.sentryUserOverride;
		return {};
	}
}
