require "minitest/autorun"
require "webmock/minitest"
require_relative "../lib/seeitlive"

class ClientTest < Minitest::Test
  LIVE_KEY = "sil_live_#{'a' * 32}".freeze
  TEST_KEY = "sil_test_#{'a' * 32}".freeze

  # --- (a) construction: env inference + exactly-one-credential rule ---

  def test_infers_env_from_token_prefix
    assert_equal :test, SeeItLive::Client.new(api_key: TEST_KEY).env
    assert_equal :live, SeeItLive::Client.new(api_key: LIVE_KEY).env
  end

  def test_explicit_env_overrides_inference
    client = SeeItLive::Client.new(api_key: LIVE_KEY, env: :test)
    assert_equal :test, client.env
  end

  def test_raises_when_neither_credential_given
    assert_raises(ArgumentError) { SeeItLive::Client.new }
  end

  def test_raises_when_both_credentials_given
    assert_raises(ArgumentError) { SeeItLive::Client.new(api_key: LIVE_KEY, oauth_token: "sil_live_oauth_x") }
  end

  def test_empty_string_credential_is_treated_as_absent_symmetrically
    # Empty api_key alone -> treated as absent -> neither provided -> raise.
    assert_raises(ArgumentError) { SeeItLive::Client.new(api_key: "") }

    # Empty api_key + a real oauth_token -> exactly one effectively present -> ok.
    client = SeeItLive::Client.new(api_key: "", oauth_token: LIVE_KEY)
    assert_equal :live, client.env

    # Empty oauth_token + a real api_key -> exactly one effectively present -> ok.
    client = SeeItLive::Client.new(api_key: LIVE_KEY, oauth_token: "")
    assert_equal :live, client.env

    # Both empty -> raise.
    assert_raises(ArgumentError) { SeeItLive::Client.new(api_key: "", oauth_token: "") }
  end

  def test_default_base_url_is_used_and_trailing_slashes_are_trimmed
    stub = stub_request(:get, "https://api.seeitlive.io/v1/oauth/verify")
           .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
             valid: true, client_id: "c", team_id: "p", scopes: [],
             plan: { planKey: "free", planName: "Free", sessionLimit: nil, seatLimit: nil, concurrentLimit: nil },
             expires_at: nil,
           }.to_json)

    client = SeeItLive::Client.new(oauth_token: "sil_live_oauth_#{'a' * 40}", base_url: "https://api.seeitlive.io/v1///")
    client.oauth.verify

    assert_requested stub
  end
end
