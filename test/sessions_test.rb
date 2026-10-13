require "minitest/autorun"
require "webmock/minitest"
require_relative "../lib/seeitlive"

class SessionsTest < Minitest::Test
  LIVE_KEY = "sil_live_#{'a' * 32}".freeze
  BASE_URL = "https://api.example.com/v1".freeze

  def client
    SeeItLive::Client.new(api_key: LIVE_KEY, base_url: BASE_URL)
  end

  # --- (b) sessions.create request shape + response parse ---

  def test_create_posts_bearer_json_with_no_team_id_and_parses_camel_case
    stub = stub_request(:post, "#{BASE_URL}/sessions")
           .with(
             headers: { "Authorization" => "Bearer #{LIVE_KEY}", "Content-Type" => "application/json" },
             body: { "channel" => "link" },
           )
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: {
               id: "s1", status: "pending", inviteCode: "abc",
               inviteUrl: "https://example.com/i/abc", inviteShortUrl: "https://sitl.cc/s/aB3xK9",
               agentViewUrl: "https://example.com/a/abc",
               expiresAt: "2026-01-01T00:00:00Z",
             }.to_json,
           )

    session = client.sessions.create(channel: "link")

    assert_requested stub
    assert_equal "s1", session.id
    assert_equal "pending", session.status
    assert_equal "abc", session.invite_code
    assert_equal "https://example.com/i/abc", session.invite_url
    assert_equal "https://sitl.cc/s/aB3xK9", session.invite_short_url
    assert_equal "https://example.com/a/abc", session.agent_view_url
    assert_equal "2026-01-01T00:00:00Z", session.expires_at
  end

  def test_create_maps_snake_case_ruby_params_to_camel_case_wire_and_omits_nils
    stub = stub_request(:post, "#{BASE_URL}/sessions")
           .with(body: { "channel" => "sms", "recipientPhone" => "+15551234567" })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { id: "s2", status: "pending", inviteCode: "x", inviteUrl: "u", agentViewUrl: "a", expiresAt: nil }.to_json,
           )

    client.sessions.create(channel: "sms", recipient_phone: "+15551234567", recipient_email: nil, note: nil)

    assert_requested stub
  end

  def test_create_maps_ttl_minutes_and_note
    stub = stub_request(:post, "#{BASE_URL}/sessions")
           .with(body: { "channel" => "email", "recipientEmail" => "a@example.com", "note" => "hi", "ttlMinutes" => 30 })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { id: "s3", status: "pending", inviteCode: "x", inviteUrl: "u", agentViewUrl: "a", expiresAt: nil }.to_json,
           )

    client.sessions.create(channel: "email", recipient_email: "a@example.com", note: "hi", ttl_minutes: 30)

    assert_requested stub
  end

  # --- (c) sessions.status path + parse ---

  def test_status_gets_expected_path_and_parses
    stub = stub_request(:get, "#{BASE_URL}/sessions/s1/status")
           .with(headers: { "Authorization" => "Bearer #{LIVE_KEY}" })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { id: "s1", status: "live", startedAt: "2026-01-01T00:00:00Z", endedAt: nil, producerCount: 1, hasVideo: true }.to_json,
           )

    status = client.sessions.status("s1")

    assert_requested stub
    assert_equal "s1", status.id
    assert_equal "live", status.status
    assert_equal "2026-01-01T00:00:00Z", status.started_at
    assert_nil status.ended_at
    assert_equal 1, status.producer_count
    assert_equal true, status.has_video
  end

  def test_status_percent_encodes_the_id_in_the_path
    stub = stub_request(:get, "#{BASE_URL}/sessions/s%2Fweird%20id/status")
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { id: "s1", status: "live", startedAt: nil, endedAt: nil, producerCount: 0, hasVideo: false }.to_json,
           )

    client.sessions.status("s/weird id")

    assert_requested stub
  end
  # --- (d) guest protection ---

  def test_get_protection_gets_expected_path_and_parses
    stub = stub_request(:get, "#{BASE_URL}/sessions/s1/protection")
           .with(headers: { "Authorization" => "Bearer #{LIVE_KEY}" })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { type: "totp", password: nil, code: "418205", secondsRemaining: 17, locked: false, failedAttempts: 0 }.to_json,
           )

    info = client.sessions.get_protection("s1")

    assert_requested stub
    assert_equal "totp", info.type
    assert_nil info.password
    assert_equal "418205", info.code
    assert_equal 17, info.seconds_remaining
    assert_equal false, info.locked
    assert_equal 0, info.failed_attempts
  end

  def test_set_protection_puts_expected_path_and_body
    stub = stub_request(:put, "#{BASE_URL}/sessions/s1/protection")
           .with(
             headers: { "Authorization" => "Bearer #{LIVE_KEY}" },
             body: { protection: "password", protectionSecret: "K7QMX2RT" }.to_json,
           )
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { type: "password", password: "K7QMX2RT", code: nil, secondsRemaining: nil, locked: false, failedAttempts: 0 }.to_json,
           )

    info = client.sessions.set_protection("s1", protection: "password", protection_secret: "K7QMX2RT")

    assert_requested stub
    assert_equal "K7QMX2RT", info.password
  end

  # Absence is what tells the API to generate a secret, so a nil must not be
  # sent as an explicit null.
  def test_set_protection_omits_the_secret_when_not_given
    stub = stub_request(:put, "#{BASE_URL}/sessions/s1/protection")
           .with(body: { protection: "password" }.to_json)
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { type: "password", password: "GENERATED", code: nil, secondsRemaining: nil, locked: false, failedAttempts: 0 }.to_json,
           )

    client.sessions.set_protection("s1", protection: "password")

    assert_requested stub
  end

  def test_set_protection_clears_with_none
    stub = stub_request(:put, "#{BASE_URL}/sessions/s1/protection")
           .with(body: { protection: "none" }.to_json)
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { type: "none", password: nil, code: nil, secondsRemaining: nil, locked: false, failedAttempts: 0 }.to_json,
           )

    info = client.sessions.set_protection("s1", protection: "none")

    assert_requested stub
    assert_equal "none", info.type
  end

  # --- session read / lockout reset / agent-view token ---

  def test_get_reads_a_session_with_its_invitation
    stub = stub_request(:get, "#{BASE_URL}/sessions/s1")
           .with(headers: { "Authorization" => "Bearer #{LIVE_KEY}" })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: {
               id: "s1", teamId: "t1", env: "live", status: "active",
               createdByClientId: nil, createdByApiKeyId: "k1", note: nil,
               metadata: { "ticket" => "42" },
               startedAt: "2026-01-01T00:00:00Z", endedAt: nil, createdAt: "2026-01-01T00:00:00Z",
               invitation: {
                 code: "abc123", channel: "sms", recipient: "+15145551234",
                 expiresAt: "2026-01-01T01:00:00Z", openedAt: nil,
               },
             }.to_json,
           )

    session = client.sessions.get("s1")

    assert_requested stub
    assert_equal "t1", session.team_id
    assert_equal "k1", session.created_by_api_key_id
    assert_equal({ "ticket" => "42" }, session.metadata)
    assert_equal "abc123", session.invitation.code
    assert_equal "sms", session.invitation.channel
    assert_equal "+15145551234", session.invitation.recipient
    assert_nil session.invitation.opened_at
  end

  def test_get_tolerates_a_session_without_an_invitation
    stub_request(:get, "#{BASE_URL}/sessions/s1").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { id: "s1", teamId: "t1", env: "live", status: "ended", invitation: nil }.to_json,
    )

    assert_nil client.sessions.get("s1").invitation
  end

  def test_reset_protection_posts_and_rotates_only_when_asked
    rotating = stub_request(:post, "#{BASE_URL}/sessions/s1/protection/reset")
               .with(body: { "rotate" => true })
               .to_return(
                 status: 200,
                 headers: { "Content-Type" => "application/json" },
                 body: { type: "password", password: "NEWSECRET", code: nil, secondsRemaining: nil, locked: false, failedAttempts: 0 }.to_json,
               )

    info = client.sessions.reset_protection("s1", rotate: true)

    assert_requested rotating
    assert_equal "NEWSECRET", info.password
    assert_equal false, info.locked
  end

  def test_reset_protection_omits_rotate_when_not_given
    # Clearing a lockout is the common case and must not rotate by accident.
    stub = stub_request(:post, "#{BASE_URL}/sessions/s1/protection/reset")
           .with(body: {})
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { type: "password", password: "K7QMX2RT", code: nil, secondsRemaining: nil, locked: false, failedAttempts: 0 }.to_json,
           )

    client.sessions.reset_protection("s1")

    assert_requested stub
  end

  def test_create_agent_token_posts_the_label_and_parses_the_viewer_url
    stub = stub_request(:post, "#{BASE_URL}/sessions/s1/agent-token")
           .with(body: { "label" => "Odoo - crm.lead 42" })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { code: "vw1", token: "tok", agentViewUrl: "https://app.seeitlive.io/v/vw1#tok" }.to_json,
           )

    token = client.sessions.create_agent_token("s1", label: "Odoo - crm.lead 42")

    assert_requested stub
    assert_equal "vw1", token.code
    assert_equal "tok", token.token
    assert_equal "https://app.seeitlive.io/v/vw1#tok", token.agent_view_url
  end

  def test_create_agent_token_omits_the_label_so_the_api_defaults_it
    stub = stub_request(:post, "#{BASE_URL}/sessions/s1/agent-token")
           .with(body: {})
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { code: "vw1", token: "tok", agentViewUrl: "u" }.to_json,
           )

    client.sessions.create_agent_token("s1")

    assert_requested stub
  end

  def test_reshare_posts_expected_path_and_body
    stub = stub_request(:post, "#{BASE_URL}/sessions/s1/reshare")
           .with(
             headers: { "Authorization" => "Bearer #{LIVE_KEY}" },
             body: { mode: "new", channel: "sms", recipient: "+15145550199", smsConsent: true }.to_json,
           )
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { expiresAt: "2026-01-02T00:00:00Z", inviteShortUrl: "https://sitl.cc/s/aB3xK9", resend: "sent", rotated: true }.to_json,
           )

    result = client.sessions.reshare("s1", mode: "new", channel: "sms", recipient: "+15145550199", sms_consent: true)

    assert_requested stub
    assert_equal true, result.rotated
    assert_equal "sent", result.resend
    assert_equal "https://sitl.cc/s/aB3xK9", result.invite_short_url
  end

  # Absence is what tells the API to reuse what was recorded, so an omitted
  # keyword must not be sent as an explicit null.
  def test_reshare_omits_unset_options
    stub = stub_request(:post, "#{BASE_URL}/sessions/s1/reshare")
           .with(body: {}.to_json)
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { expiresAt: "2026-01-02T00:00:00Z", inviteShortUrl: nil, resend: "not_requested", rotated: false }.to_json,
           )

    result = client.sessions.reshare("s1")

    assert_requested stub
    assert_nil result.invite_short_url
  end

  def test_reshare_percent_encodes_the_id_in_the_path
    stub = stub_request(:post, "#{BASE_URL}/sessions/sess%2F..%2Fevil/reshare")
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { expiresAt: "2026-01-02T00:00:00Z", inviteShortUrl: nil, resend: "not_requested", rotated: false }.to_json,
           )

    client.sessions.reshare("sess/../evil")

    assert_requested stub
  end

end
