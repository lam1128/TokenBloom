# Privacy

Token Bloom is designed as a local macOS utility. It does not operate a Token Bloom account system, analytics backend, advertising SDK, or telemetry service.

## Data accessed on your Mac

- Codex authentication data from two configured `CODEX_HOME/auth.json` files.
- Local process activity used to determine which Codex account is currently active.
- Approximate device location, only after macOS grants location permission.

## Network requests

- Codex quota requests are sent directly to OpenAI's service using each local Codex session.
- Coordinates are sent to Open-Meteo for current weather. If the user explicitly provides an `AMAP_WEBSERVICE_KEY`, coordinates may instead be sent to AMap for reverse geocoding and weather.

Token Bloom does not send authentication credentials to weather providers and does not send location coordinates to OpenAI's quota endpoints beyond information already included by their own network stack.

## Storage and logging

Token Bloom does not copy authentication tokens into its preferences or logs. System logs contain operational status and may include the resolved place name and location accuracy, but not raw coordinates or tokens.

## Revoking access

Location access can be revoked in System Settings → Privacy & Security → Location Services. Login-at-startup can be disabled in Token Bloom Settings or System Settings → General → Login Items.

Security issues involving credentials should be reported privately according to [SECURITY.md](SECURITY.md).
