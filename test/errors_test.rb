require "minitest/autorun"
require "webmock/minitest"
require_relative "../lib/seeitlive"

class ErrorsTest < Minitest::Test
  LIVE_KEY = "sil_live_#{'a' * 32}".freeze
  BASE_URL = "https://api.example.com/v1".freeze

  def client
    SeeItLive::Client.new(api_key: LIVE_KEY, base_url: BASE_URL)
  end

  def stub_status(status, body, headers = {})
    stub_request(:get, "#{BASE_URL}/sessions/s1/status")
      .to_return(status: status, headers: { "Content-Type" => "application/json" }.merge(headers), body: body.to_json)
  end

  # --- (e) status -> error mapping ---

  def test_400_maps_to_validation_error_with_field_and_code
    stub_status(400, { message: "bad channel", field: "channel", code: "invalid_channel" })

    err = assert_raises(SeeItLive::ValidationError) { client.sessions.status("s1") }
    assert_kind_of SeeItLive::Error, err
    assert_equal 400, err.status_code
    assert_equal "bad channel", err.message
    assert_equal "channel", err.field
    assert_equal "invalid_channel", err.code
  end

  def test_401_maps_to_authentication_error
    stub_status(401, { message: "no auth" })

    err = assert_raises(SeeItLive::AuthenticationError) { client.sessions.status("s1") }
    assert_equal 401, err.status_code
  end

  def test_403_maps_to_permission_error
    stub_status(403, { message: "forbidden" })

    err = assert_raises(SeeItLive::PermissionError) { client.sessions.status("s1") }
    assert_equal 403, err.status_code
  end

  def test_404_maps_to_not_found_error
    stub_status(404, { message: "missing" })

    err = assert_raises(SeeItLive::NotFoundError) { client.sessions.status("s1") }
    assert_equal 404, err.status_code
  end

  def test_429_with_retry_after_12
    stub_status(429, { message: "slow down" }, { "Retry-After" => "12" })

    err = assert_raises(SeeItLive::RateLimitError) { client.sessions.status("s1") }
    assert_equal 429, err.status_code
    assert_equal 12, err.retry_after
  end

  def test_429_with_retry_after_0_is_preserved_as_zero_not_nil
    stub_status(429, { message: "slow down" }, { "Retry-After" => "0" })

    err = assert_raises(SeeItLive::RateLimitError) { client.sessions.status("s1") }
    assert_equal 0, err.retry_after
    refute_nil err.retry_after
  end

  def test_429_without_retry_after_header_is_nil
    stub_status(429, { message: "slow down" })

    err = assert_raises(SeeItLive::RateLimitError) { client.sessions.status("s1") }
    assert_nil err.retry_after
  end

  def test_other_status_maps_to_base_error
    stub_status(500, { message: "boom" })

    err = assert_raises(SeeItLive::Error) { client.sessions.status("s1") }
    assert_equal 500, err.status_code
    assert_equal "boom", err.message
  end

  def test_error_body_without_message_falls_back_to_http_status
    stub_status(500, {})

    err = assert_raises(SeeItLive::Error) { client.sessions.status("s1") }
    assert_equal "HTTP 500", err.message
  end
end
