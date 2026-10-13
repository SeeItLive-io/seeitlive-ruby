# seeitlive-sdk

Official SeeItLive SDK for Ruby — an idiomatic port of the reference
`@seeitlive/sdk` Node client. Same behaviour, same wire contract, Ruby
conventions.

## Install

```bash
gem install seeitlive-sdk
```

Or in a `Gemfile`:

```ruby
gem "seeitlive-sdk"
```

From source:

```bash
cd packages/client-ruby
bundle install
bundle exec rake test
```

Requires Ruby >= 3.0. Runtime dependencies: none — HTTP via stdlib
`Net::HTTP`, JSON via stdlib `json`. Tests use `minitest`, `webmock`,
and `rake` (development-only).

## Quick start

```ruby
require "seeitlive"

client = SeeItLive::Client.new(api_key: ENV["SEEITLIVE_API_KEY"])

# SMS channel requires recipient_phone + sms_consent (the recipient agreed
# to receive a text; carrier fees may apply)
session = client.sessions.create(channel: "sms", recipient_phone: "+15551234567", sms_consent: true)

# email channel requires recipient_email
client.sessions.create(channel: "email", recipient_email: "customer@example.com")

# link channel needs neither -- just returns a shareable link
link_session = client.sessions.create(channel: "link")

puts "#{session.invite_url} #{session.invite_code}"

status = client.sessions.status(session.id)
puts "#{status.status} #{status.producer_count} #{status.has_video}"
```

The client infers `env` (`:live` or `:test`) from the API key's prefix
(`sil_test_...` -> `:test`, otherwise `:live`). Override with the `env:`
keyword, and override the API base URL with `base_url:` (default:
`https://api.seeitlive.io/v1`; paths are relative to this, e.g.
`/sessions`, not `/api/v1/sessions`).

Provide **exactly one** of `api_key:` or `oauth_token:` — passing both,
or neither, raises `ArgumentError`. An **empty string counts as "not
provided"** for both credentials (symmetric): this lets a blank
environment variable fall through safely instead of producing a bogus
`Bearer ` header.

### `sessions.create` / `sessions.status`

`sessions.create(**params)` sends `POST /sessions`. It never sends a
team id — the team is implicit from the API key / OAuth token.
Accepted keyword params (all but `channel:` optional; `nil` values are
omitted from the request body, and any other keyword is generically
camelCased so the SDK stays forward-compatible with new API fields):

| Ruby keyword | Wire key |
| --- | --- |
| `channel:` (`"sms"` \| `"email"` \| `"link"`, required) | `channel` |
| `recipient_phone:` | `recipientPhone` |
| `recipient_email:` | `recipientEmail` |
| `note:` | `note` |
| `ttl_minutes:` | `ttlMinutes` |
| `sms_consent:` (required `true` for `sms`) | `smsConsent` |
| `metadata:` (a `Hash` of `String => String`, arbitrary attribution key/values echoed back on the session) | `metadata` |
| `short_link:` | `shortLink` |

The API requires `recipient_phone` for the `sms` channel and
`recipient_email` for the `email` channel; the SDK forwards whatever is
given and lets the API validate — it does not re-implement that rule.

Both calls return small `Struct` value objects (the session/status wire
format is camelCase; fields are mapped to idiomatic snake_case
accessors):

- `sessions.create` -> `SeeItLive::Session`: `id, status, invite_code,
  invite_url, invite_short_url, agent_view_url, metadata, expires_at`
  (`metadata` is a nullable `Hash` of `String => String`)
- `sessions.status(id)` -> `SeeItLive::SessionStatus`: `id, status,
  started_at, ended_at, producer_count, has_video`

### Reading a session

`sessions.get` returns a stored session, including how its invitation was
delivered — useful when re-opening a session an integration created earlier:

```ruby
s = client.sessions.get(session.id)
puts s.status, s.metadata, s.invitation&.channel, s.invitation&.recipient
```

### Guest protection

A session can require the customer to enter a secret before their camera is
shared — a static password, or a rotating code. Read the current one to them:

```ruby
p = client.sessions.get_protection(session.id)
puts p.password if p.type == "password"
puts "#{p.code} (#{p.seconds_remaining}s left)" if p.type == "totp"
```

Change it after creation — including adding one to a session that had none.
Omit `protection_secret:` and one is generated for you:

```ruby
added = client.sessions.set_protection(session.id, protection: "password")
puts added.password # read this to the customer

# Clearing also clears any lockout the customer triggered.
client.sessions.set_protection(session.id, protection: "none")
```

Five wrong answers lock the guest out. Clear the lockout — rotation is opt-in,
since the usual cause is a mistyped secret:

```ruby
client.sessions.reset_protection(session.id)
fresh = client.sessions.reset_protection(session.id, rotate: true) # new secret too
```

For `totp`, `get_protection` returns the **current code**, never the seed — the
seed leaves the server only once, in the create response.

### Embedded viewer tokens

`sessions.create_agent_token` mints a fresh agent-view grant so your own UI can
embed the live viewer. Tokens expire after 120 minutes — mint another to
re-open a viewer:

```ruby
viewer = client.sessions.create_agent_token(session.id, label: "Odoo — crm.lead 42")
puts viewer.agent_view_url
```

### Snapshots

Frames the agent captured during a session. Both calls require a plan with
snapshot history:

```ruby
require "base64"

snapshots = client.snapshots.list(session.id) # newest first
image = client.snapshots.get(snapshots.first.id)

# `data` is base64 PNG — the endpoint's raw-bytes mode is not used by the SDK.
File.binwrite("frame.png", Base64.decode64(image.data))
```

## OAuth usage

For OAuth-based (multi-tenant / marketplace) integrations, exchange an
authorization code for an access token using the standalone
`SeeItLive.exchange_code` module method (this is **not** a `Client`
instance method — it's called *before* any token exists, and
authenticates via your client credentials in the POST body, not a
bearer token, so it must only ever run in a trusted server-side
context):

```ruby
require "seeitlive"

token = SeeItLive.exchange_code(
  code: authorization_code_from_redirect,
  client_id: ENV["SEEITLIVE_CLIENT_ID"],
  client_secret: ENV["SEEITLIVE_CLIENT_SECRET"],
  redirect_uri: "https://your-app.example.com/oauth/callback",
  code_verifier: pkce_verifier, # optional; omitted entirely when nil/empty
)
# token => SeeItLive::TokenResponse (access_token, token_type, client_id,
#          team_id, scopes, plan)

client = SeeItLive::Client.new(oauth_token: token.access_token)

info = client.oauth.verify
# info => SeeItLive::TokenInfo (valid, client_id, team_id, scopes,
#         plan, expires_at)
puts "#{info.client_id} #{info.team_id} #{info.scopes.join(',')}"
```

`plan` (in both `oauth.verify` and `exchange_code` results) is itself a
`SeeItLive::Plan` struct: `plan_key, plan_name, session_limit,
seat_limit, concurrent_limit` (unlimited tiers report `nil` for the
limit fields). `scopes` is an array of colon-form strings (e.g.
`"sessions:write"`).

## Request signing

Set `signing_secret:` in the client constructor to have every outgoing
request HMAC-signed automatically. When set, each request carries two
extra headers:

- `X-SeeItLive-Signature: sha256=<hex>` —
  `HMAC_SHA256(signing_secret, "<unix_ts>.<METHOD>.<path>.<sha256hex(raw_body)>")`,
  where `path` is the request path only (e.g. `/sessions`, no base URL
  and no `/api/v1` prefix) and `raw_body` is the exact bytes sent
  (hashed as the empty string when there is no body).
- `X-SeeItLive-Timestamp: <unix_ts>` — unix seconds.

`path` is signed **including any query string** the SDK sends (e.g.
`/snapshots/<id>?format=base64`) — the server verifies path *and* query,
so the two must match exactly.

```ruby
client = SeeItLive::Client.new(
  api_key: ENV["SEEITLIVE_API_KEY"],
  signing_secret: ENV["SEEITLIVE_SIGNING_SECRET"],
)
```

A present-but-empty `signing_secret:` is treated the same as absent, so
requests are unsigned by default and enabling signing is fully
backwards-compatible. The `SeeItLive.exchange_code` call is never
signed.

## Errors

Every non-2xx API response is raised as a `SeeItLive::Error` (or one of
its subclasses below). Each carries `status_code` and `code` (the API's
machine-readable error code, when present); `message` falls back to
`"HTTP <status>"` when the API sent none.

| Status | Class | Extra accessor |
| --- | --- | --- |
| 400 | `SeeItLive::ValidationError` | `field` — the invalid field name, when present |
| 401 | `SeeItLive::AuthenticationError` | |
| 403 | `SeeItLive::PermissionError` | |
| 404 | `SeeItLive::NotFoundError` | |
| 429 | `SeeItLive::RateLimitError` | `retry_after` — seconds from the `Retry-After` header |
| other non-2xx | `SeeItLive::Error` | |

```ruby
begin
  client.sessions.status("missing")
rescue SeeItLive::RateLimitError => e
  # retry_after may legitimately be 0 (retry immediately) -- that is
  # distinct from nil (no Retry-After header was sent at all). Check
  # explicitly; do not treat nil as "no need to wait".
  puts "retry after #{e.retry_after.inspect} seconds"
rescue SeeItLive::Error => e
  puts "#{e.status_code} #{e.message} #{e.code}"
end
```

Network/transport failures (DNS, connection refused, timeouts, etc.)
are **not** wrapped — they surface as Ruby's natural `Net::HTTP` /
`SystemCallError` exceptions.

## Testing without network

This gem's own test suite (`test/*_test.rb`) stubs all HTTP via
[`webmock`](https://github.com/bblimke/webmock) — no live network calls
are made. Run it with:

```bash
bundle exec rake test
```

## Security

- **Never log API keys, OAuth access tokens, or refresh tokens.**
- **Never ship `client_secret` to a browser or mobile app.**
  `SeeItLive.exchange_code` is a confidential-client operation and must
  only be called from a trusted server-side context. Client-side code
  should redirect the user through your own backend, which performs the
  code exchange and hands the browser a short-lived session, never the
  raw OAuth token or client secret.
- The default `base_url` is HTTPS; the SDK does not disable TLS
  verification (`Net::HTTP#use_ssl` is set from the URL scheme).
- Credentials are only ever sent via the `Authorization` header (or,
  for `exchange_code`, the POST body over TLS) — never in a URL.
