require "minitest/autorun"
require "webmock/minitest"
require "json"
require_relative "../lib/seeitlive"

class OAuthTest < Minitest::Test
  OAUTH_TOKEN = "sil_live_oauth_#{'a' * 40}".freeze
  BASE_URL = "https://api.example.com/v1".freeze

  def plan_wire
    { planKey: "free", planName: "Free", sessionLimit: nil, seatLimit: nil, concurrentLimit: nil }
  end

  # --- (d) oauth.verify maps snake_case wire (already snake) into the TokenInfo struct ---

  def test_verify_maps_wire_fields_onto_token_info
    stub = stub_request(:get, "#{BASE_URL}/oauth/verify")
           .with(headers: { "Authorization" => "Bearer #{OAUTH_TOKEN}" })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: {
               valid: true, client_id: "c1", team_id: "p1",
               scopes: ["sessions:write", "sessions:read"], plan: plan_wire,
               expires_at: "2026-06-01T00:00:00Z",
             }.to_json,
           )

    client = SeeItLive::Client.new(oauth_token: OAUTH_TOKEN, base_url: BASE_URL)
    info = client.oauth.verify

    assert_requested stub
    assert_equal true, info.valid
    assert_equal "c1", info.client_id
    assert_equal "p1", info.team_id
    assert_equal ["sessions:write", "sessions:read"], info.scopes
    assert_equal "free", info.plan.plan_key
    assert_equal "Free", info.plan.plan_name
    assert_nil info.plan.session_limit
    assert_equal "2026-06-01T00:00:00Z", info.expires_at
  end

  # --- (f) exchange_code: standalone, no bearer, maps token ---

  def test_exchange_code_posts_oauth_token_without_bearer_and_maps_token
    stub = stub_request(:post, "#{BASE_URL}/oauth/token")
           .with { |request| !request.headers.key?("Authorization") }
           .with(body: {
             "grant_type" => "authorization_code", "code" => "code123",
             "client_id" => "client-1", "client_secret" => "secret-1",
             "redirect_uri" => "https://app.example.com/callback",
           })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: {
               access_token: "sil_live_oauth_x", token_type: "Bearer",
               client_id: "client-1", team_id: "p1", scopes: ["sessions:write"], plan: plan_wire,
             }.to_json,
           )

    token = SeeItLive.exchange_code(
      code: "code123", client_id: "client-1", client_secret: "secret-1",
      redirect_uri: "https://app.example.com/callback", base_url: BASE_URL,
    )

    assert_requested stub
    assert_equal "sil_live_oauth_x", token.access_token
    assert_equal "Bearer", token.token_type
    assert_equal "client-1", token.client_id
    assert_equal "p1", token.team_id
    assert_equal ["sessions:write"], token.scopes
    assert_equal "free", token.plan.plan_key
  end

  def test_exchange_code_includes_code_verifier_when_present
    stub = stub_request(:post, "#{BASE_URL}/oauth/token")
           .with(body: {
             "grant_type" => "authorization_code", "code" => "code123",
             "client_id" => "client-1", "client_secret" => "secret-1",
             "redirect_uri" => "https://app.example.com/callback", "code_verifier" => "verifier-1",
           })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: {
               access_token: "t", token_type: "Bearer", client_id: "client-1",
               team_id: "p1", scopes: [], plan: plan_wire,
             }.to_json,
           )

    SeeItLive.exchange_code(
      code: "code123", client_id: "client-1", client_secret: "secret-1",
      redirect_uri: "https://app.example.com/callback", code_verifier: "verifier-1", base_url: BASE_URL,
    )

    assert_requested stub
  end

  def test_exchange_code_omits_code_verifier_when_nil_or_empty
    stub = stub_request(:post, "#{BASE_URL}/oauth/token")
           .with { |request| !JSON.parse(request.body).key?("code_verifier") }
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: {
               access_token: "t", token_type: "Bearer", client_id: "client-1",
               team_id: "p1", scopes: [], plan: plan_wire,
             }.to_json,
           )

    SeeItLive.exchange_code(
      code: "code123", client_id: "client-1", client_secret: "secret-1",
      redirect_uri: "https://app.example.com/callback", code_verifier: nil, base_url: BASE_URL,
    )
    SeeItLive.exchange_code(
      code: "code123", client_id: "client-1", client_secret: "secret-1",
      redirect_uri: "https://app.example.com/callback", code_verifier: "", base_url: BASE_URL,
    )

    assert_requested stub, times: 2
  end
end
