require_relative "http"

module SeeItLive
  # Plan limits nested in OAuth responses (oauth.verify and
  # SeeItLive.exchange_code). Wire format is camelCase; unlimited tiers
  # report `nil` for the limit fields.
  Plan = Struct.new(:plan_key, :plan_name, :session_limit, :seat_limit, :concurrent_limit, keyword_init: true)

  # Result of OAuth#verify. The wire response is snake_case already
  # (client_id, team_id, expires_at); this struct just gives it a
  # documented, idiomatic Ruby shape.
  TokenInfo = Struct.new(:valid, :client_id, :team_id, :scopes, :plan, :expires_at, keyword_init: true)

  # The `oauth` resource: `verify`. Accessed as `client.oauth`; only
  # meaningful when the client was constructed with an `oauth_token`.
  class OAuth
    def initialize(http)
      @http = http
    end

    # GET /oauth/verify, using the client's bearer token.
    def verify
      raw = @http.request("/oauth/verify")
      TokenInfo.new(
        valid: raw["valid"],
        client_id: raw["client_id"],
        team_id: raw["team_id"],
        scopes: raw["scopes"],
        plan: self.class.plan_from(raw["plan"]),
        expires_at: raw["expires_at"],
      )
    end

    # Shared by #verify and the standalone SeeItLive.exchange_code, both
    # of which receive the same camelCase `plan` sub-object on the wire.
    def self.plan_from(raw)
      return nil if raw.nil?

      Plan.new(
        plan_key: raw["planKey"],
        plan_name: raw["planName"],
        session_limit: raw["sessionLimit"],
        seat_limit: raw["seatLimit"],
        concurrent_limit: raw["concurrentLimit"],
      )
    end
  end
end
