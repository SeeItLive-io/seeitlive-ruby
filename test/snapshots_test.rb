require "minitest/autorun"
require "webmock/minitest"
require_relative "../lib/seeitlive"

class SnapshotsTest < Minitest::Test
  LIVE_KEY = "sil_live_#{'a' * 32}".freeze
  BASE_URL = "https://api.example.com/v1".freeze

  def client
    SeeItLive::Client.new(api_key: LIVE_KEY, base_url: BASE_URL)
  end

  def test_list_gets_a_sessions_snapshots
    stub = stub_request(:get, "#{BASE_URL}/sessions/s1/snapshots")
           .with(headers: { "Authorization" => "Bearer #{LIVE_KEY}" })
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: [
               { id: "sn1", width: 1280, height: 720, capturedAt: "2026-01-01T00:00:00Z", url: "/api/v1/snapshots/sn1" },
             ].to_json,
           )

    snapshots = client.snapshots.list("s1")

    assert_requested stub
    assert_equal 1, snapshots.length
    assert_equal "sn1", snapshots.first.id
    assert_equal 1280, snapshots.first.width
    assert_equal "2026-01-01T00:00:00Z", snapshots.first.captured_at
    assert_equal "/api/v1/snapshots/sn1", snapshots.first.url
  end

  def test_get_asks_for_base64_json_rather_than_raw_png_bytes
    stub = stub_request(:get, "#{BASE_URL}/snapshots/sn1?format=base64")
           .to_return(
             status: 200,
             headers: { "Content-Type" => "application/json" },
             body: {
               id: "sn1", contentType: "image/png", width: 1280, height: 720,
               capturedAt: "2026-01-01T00:00:00Z", data: "aVZCT1J3MEs=",
             }.to_json,
           )

    image = client.snapshots.get("sn1")

    assert_requested stub
    assert_equal "image/png", image.content_type
    assert_equal "aVZCT1J3MEs=", image.data
    assert_equal 720, image.height
  end
end
