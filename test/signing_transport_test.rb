require "minitest/autorun"
require "webmock/minitest"
require_relative "../lib/seeitlive"

class SigningTransportTest < Minitest::Test
  LIVE_KEY = "sil_live_#{'a' * 32}".freeze
  BASE_URL = "https://api.example.com/v1".freeze
  SECRET = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef".freeze

  def test_signs_every_request_when_a_signing_secret_is_configured
    client = SeeItLive::Client.new(api_key: LIVE_KEY, base_url: BASE_URL, signing_secret: SECRET)

    stub = stub_request(:post, "#{BASE_URL}/sessions")
           .with(headers: { "X-Seeitlive-Signature" => /^sha256=[0-9a-f]{64}$/, "X-Seeitlive-Timestamp" => /^\d+$/ })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { id: "s1", status: "pending", inviteCode: "x", inviteUrl: "u", agentViewUrl: "a", expiresAt: nil }.to_json,
           )

    client.sessions.create(channel: "link")

    assert_requested stub
  end

  def test_signs_get_requests_with_no_body_too
    client = SeeItLive::Client.new(api_key: LIVE_KEY, base_url: BASE_URL, signing_secret: SECRET)

    stub = stub_request(:get, "#{BASE_URL}/sessions/s1/status")
           .with(headers: { "X-Seeitlive-Signature" => /^sha256=[0-9a-f]{64}$/, "X-Seeitlive-Timestamp" => /^\d+$/ })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { id: "s1", status: "live", startedAt: nil, endedAt: nil, producerCount: 0, hasVideo: false }.to_json,
           )

    client.sessions.status("s1")

    assert_requested stub
  end

  def test_does_not_sign_requests_when_no_signing_secret_is_configured
    client = SeeItLive::Client.new(api_key: LIVE_KEY, base_url: BASE_URL)

    stub = stub_request(:post, "#{BASE_URL}/sessions")
           .with { |req| !req.headers.key?("X-Seeitlive-Signature") && !req.headers.key?("X-Seeitlive-Timestamp") }
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { id: "s1", status: "pending", inviteCode: "x", inviteUrl: "u", agentViewUrl: "a", expiresAt: nil }.to_json,
           )

    client.sessions.create(channel: "link")

    assert_requested stub
  end

  def test_does_not_sign_when_signing_secret_is_the_empty_string
    client = SeeItLive::Client.new(api_key: LIVE_KEY, base_url: BASE_URL, signing_secret: "")

    stub = stub_request(:post, "#{BASE_URL}/sessions")
           .with { |req| !req.headers.key?("X-Seeitlive-Signature") }
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { id: "s1", status: "pending", inviteCode: "x", inviteUrl: "u", agentViewUrl: "a", expiresAt: nil }.to_json,
           )

    client.sessions.create(channel: "link")

    assert_requested stub
  end

  def test_signature_matches_the_pure_helper_for_the_exact_body_sent
    client = SeeItLive::Client.new(api_key: LIVE_KEY, base_url: BASE_URL, signing_secret: SECRET)

    expected_signature = nil
    stub = stub_request(:post, "#{BASE_URL}/sessions")
           .with { |req|
             timestamp = req.headers["X-Seeitlive-Timestamp"]
             expected_headers = SeeItLive::Signing.sign_request(SECRET, "POST", "/sessions", req.body, timestamp.to_i)
             expected_signature = expected_headers["X-SeeItLive-Signature"]
             req.headers["X-Seeitlive-Signature"] == expected_signature
           }
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: { id: "s1", status: "pending", inviteCode: "x", inviteUrl: "u", agentViewUrl: "a", expiresAt: nil }.to_json,
           )

    client.sessions.create(channel: "link")

    assert_requested stub
    refute_nil expected_signature
  end
end
