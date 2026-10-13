require "openssl"

module SeeItLive
  # Computes the HMAC request-signature headers per the SeeItLive wire
  # contract:
  #
  #   signature = HMAC_SHA256(secret, "#{timestamp}.#{METHOD}.#{path}.#{sha256hex(rawBody)}")
  #
  # - `timestamp` is unix seconds.
  # - `method` is upper-cased (so `"post"` and `"POST"` sign identically).
  # - `path` is exactly the request path (no base URL, no `/v1` prefix).
  # - `body` must be the exact serialized bytes sent as the request body
  #   (e.g. the `JSON.generate(...)` result); pass `nil` when the request
  #   has no body, which hashes as the empty string.
  module Signing
    def self.sign_request(secret, method, path, body, timestamp)
      body_hash = OpenSSL::Digest::SHA256.hexdigest(body || "")
      message = "#{timestamp}.#{method.upcase}.#{path}.#{body_hash}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, message)
      {
        "X-SeeItLive-Signature" => "sha256=#{signature}",
        "X-SeeItLive-Timestamp" => timestamp.to_s,
      }
    end
  end
end
