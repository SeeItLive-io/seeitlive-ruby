require "minitest/autorun"
require_relative "../lib/seeitlive"

class SigningTest < Minitest::Test
  SECRET = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef".freeze

  def test_matches_known_answer_vector_for_a_post_with_a_body
    headers = SeeItLive::Signing.sign_request(SECRET, "POST", "/sessions", '{"channel":"demo"}', 1800000000)

    assert_equal(
      {
        "X-SeeItLive-Signature" => "sha256=a59401f3e80ae2e50f4b2517c8e4708de856bb93eadb1f4cfc59100db2b6e7f7",
        "X-SeeItLive-Timestamp" => "1800000000",
      },
      headers,
    )
  end

  def test_matches_known_answer_vector_for_a_get_with_no_body
    headers = SeeItLive::Signing.sign_request(SECRET, "GET", "/sessions/x/status", nil, 1800000000)

    assert_equal "sha256=3499dfb7f9581f996d537dfb108f775cb329f1f3f490f3bcb791820b4d81d5ea", headers["X-SeeItLive-Signature"]
    assert_equal "1800000000", headers["X-SeeItLive-Timestamp"]
  end

  def test_upper_cases_the_method_so_lower_case_input_yields_the_same_signature
    upper = SeeItLive::Signing.sign_request(SECRET, "POST", "/sessions", '{"channel":"demo"}', 1800000000)
    lower = SeeItLive::Signing.sign_request(SECRET, "post", "/sessions", '{"channel":"demo"}', 1800000000)

    assert_equal upper, lower
  end
end
