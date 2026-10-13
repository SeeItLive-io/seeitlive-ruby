require_relative "http"
require_relative "sessions"
require_relative "snapshots"
require_relative "oauth"

module SeeItLive
  # The SeeItLive API client. Construct with `SeeItLive::Client.new`.
  class Client
    attr_reader :env, :sessions, :snapshots, :oauth

    # Exactly one of `api_key:` / `oauth_token:` must be given -- an
    # empty string counts as "not provided" (symmetric for both
    # credentials), so a blank environment variable never produces a
    # bogus `Bearer ` header. Providing neither, or both (after that
    # normalization), raises ArgumentError.
    #
    # `env` is inferred from the token prefix (a token starting
    # `sil_test_` -> `:test`, else `:live`) unless `env:` is given
    # explicitly. `base_url` defaults to
    # `https://api.seeitlive.io/v1`; trailing slashes are trimmed.
    #
    # `signing_secret:` is optional; an empty string counts as "not
    # provided" (same convention as `api_key`/`oauth_token`). When set,
    # every request is HMAC-signed (see Signing.sign_request); leaving it
    # unset is fully backwards-compatible.
    def initialize(api_key: nil, oauth_token: nil, base_url: nil, env: nil, signing_secret: nil)
      api_key = nil if api_key == ""
      oauth_token = nil if oauth_token == ""

      if api_key.nil? && oauth_token.nil?
        raise ArgumentError, "Either api_key or oauth_token must be provided"
      end
      if api_key && oauth_token
        raise ArgumentError, "Provide only one of api_key or oauth_token"
      end

      token = api_key || oauth_token
      @env = env || (token.start_with?("sil_test_") ? :test : :live)

      resolved_base_url = (base_url || DEFAULT_BASE_URL).sub(%r{/+\z}, "")
      http = HTTPClient.new(resolved_base_url, "Bearer #{token}", signing_secret)
      @sessions = Sessions.new(http)
      @snapshots = Snapshots.new(http)
      @oauth = OAuth.new(http)
    end
  end
end
