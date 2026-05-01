# Error Telemetry Setup

This guide covers error capture and automatic bug triage for the Agile Flow
starter app.

## Zero-Config (Default)

The app ships with a built-in error receiver. When no external monitoring
service is configured, errors are captured by the Sentry SDK and sent to
the app's own `/api/error-events` endpoint. This endpoint creates GitHub
issues labeled `bug:auto` automatically.

**Requirements:**

- `GITHUB_TOKEN` environment variable set (for creating issues)
- `GITHUB_REPOSITORY` environment variable set (e.g., `your-org/agile-flow`)
- `APP_URL` (set at deploy time via `gcloud run services update --set-env-vars`)
  must point at the public service URL so the self-DSN transport can POST
  events back to `/api/error-events`. FastAPI reads this at runtime — no
  build-time baking.

**How it works:**

1. An unhandled exception occurs in the app
2. The Sentry SDK captures it and sends an event to the app itself
3. The `/api/error-events` endpoint parses the error details
4. A GitHub issue is created with the `bug:auto` label
5. The auto-triage workflow fires and posts agent fix instructions

**Verify it works:**

```bash
curl https://your-app-xyz.us-central1.run.app/error
# Wait 10-30 seconds
gh issue list --label bug:auto
```

**Rate limiting:** The receiver creates at most one issue per unique error
message per hour to prevent flooding.

## Optional: External Sentry

If you want a full error monitoring dashboard with history, performance
monitoring, and alerting, set `SENTRY_DSN` to point at an external service.
The self-receiver is bypassed when an external DSN is configured.

### Sentry SaaS

1. Create a [Sentry](https://sentry.io) account (free tier works)
2. Create a project: **Python > FastAPI**
3. Copy the DSN from **Settings > Client Keys**
4. Add `SENTRY_DSN` to Render environment variables

### GlitchTip (Self-Hosted)

GlitchTip is an open-source, Sentry-compatible error tracker you can
deploy alongside your app. See [PLATFORM-GUIDE.md](./PLATFORM-GUIDE.md)
for setup instructions.

### GitHub Integration (External Sentry Only)

When using external Sentry, you can configure it to auto-create GitHub
issues:

1. Go to **Settings > Integrations > GitHub**
2. Click **Install** and authorize for your GitHub organization
3. Link the Sentry project to the GitHub repository
4. Create an alert rule: "A new issue is created" → "Create a GitHub issue"

This is not needed for the zero-config flow, which creates issues directly.

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `GITHUB_TOKEN` | Yes (zero-config) | API token for creating GitHub issues |
| `GITHUB_REPOSITORY` | Yes (zero-config) | Target repo (e.g., `org/agile-flow`) |
| `APP_URL` | Yes (zero-config) | App's public URL for self-DSN construction (runtime env var) |
| `SENTRY_DSN` | No | External Sentry/GlitchTip DSN (overrides self-DSN) |
| `APP_URL` | No | Runtime override for the app URL (set via `gcloud run services update`) |
