# Official SeeItLive SDK for Ruby -- an idiomatic port of the reference
# @seeitlive/sdk Node client. Same behaviour, same wire contract, Ruby
# conventions.
#
#   require "seeitlive"
#
#   client = SeeItLive::Client.new(api_key: ENV["SEEITLIVE_API_KEY"])
#   session = client.sessions.create(channel: "link")
#   puts session.invite_url

require_relative "seeitlive/version"
require_relative "seeitlive/errors"
require_relative "seeitlive/signing"
require_relative "seeitlive/http"
require_relative "seeitlive/sessions"
require_relative "seeitlive/snapshots"
require_relative "seeitlive/oauth"
require_relative "seeitlive/client"

module SeeItLive
  # Result of SeeItLive.exchange_code. The wire response is snake_case
  # (access_token, token_type, ...); this struct just gives it a
  # documented, idiomatic Ruby shape.
  TokenResponse = Struct.new(:access_token, :token_type, :client_id, :team_id, :scopes, :plan, keyword_init: true)

  # Standalone module-level function (NOT a Client instance method)
  # because it is called *before* any token exists, and needs no bearer
  # auth: it authenticates via the confidential client's `client_id` +
  # `client_secret` in the POST body instead, per
  # `POST {base_url}/oauth/token`.
  #
  # `code_verifier:` (PKCE) is omitted from the request body entirely
  # when `nil` or an empty string.
  def self.exchange_code(code:, client_id:, client_secret:, redirect_uri:, code_verifier: nil, base_url: nil)
    resolved_base_url = (base_url || DEFAULT_BASE_URL).sub(%r{/+\z}, "")
    http = HTTPClient.new(resolved_base_url, nil)

    body = {
      "grant_type" => "authorization_code",
      "code" => code,
      "client_id" => client_id,
      "client_secret" => client_secret,
      "redirect_uri" => redirect_uri,
    }
    body["code_verifier"] = code_verifier if code_verifier && !code_verifier.empty?

    raw = http.request("/oauth/token", method: :post, body: body)
    TokenResponse.new(
      access_token: raw["access_token"],
      token_type: raw["token_type"],
      client_id: raw["client_id"],
      team_id: raw["team_id"],
      scopes: raw["scopes"],
      plan: OAuth.plan_from(raw["plan"]),
    )
  end
end
