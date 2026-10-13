require "net/http"
require "json"
require_relative "errors"
require_relative "signing"

module SeeItLive
  # Default API base URL, shared by Client.new and the standalone
  # SeeItLive.exchange_code (this host proxies to the API's /api/v1).
  DEFAULT_BASE_URL = "https://api.seeitlive.io/v1"

  # Low-level transport shared by the authenticated resources (Sessions,
  # OAuth) and the standalone exchange_code function. `auth_header` is
  # `nil` for unauthenticated calls (the OAuth token exchange authenticates
  # via client_id/client_secret in the POST body instead of a bearer
  # token). `signing_secret` is `nil`/empty to leave requests unsigned
  # (backwards-compatible default); when set, every request sent through
  # this client is HMAC-signed.
  class HTTPClient
    def initialize(base_url, auth_header, signing_secret = nil)
      @base_url = base_url
      @auth_header = auth_header
      @signing_secret = signing_secret && !signing_secret.empty? ? signing_secret : nil
    end

    # `path` is relative to base_url (which already includes `/v1`), e.g.
    # "/sessions", "/sessions/abc/status", "/oauth/verify", "/oauth/token".
    def request(path, method: :get, body: nil)
      uri = URI("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = build_request(method, uri, path, body)
      response = http.request(request)

      handle_response(response)
    end

    private

    def build_request(method, uri, path, body)
      request_class =
        case method
        when :get then Net::HTTP::Get
        when :post then Net::HTTP::Post
        when :put then Net::HTTP::Put
        else raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

      req = request_class.new(uri)
      req["Authorization"] = @auth_header if @auth_header && !@auth_header.empty?

      serialized_body = body ? JSON.generate(body) : nil
      if serialized_body
        req["Content-Type"] = "application/json"
        req.body = serialized_body
      end

      if @signing_secret
        signature_headers = Signing.sign_request(@signing_secret, method.to_s, path, serialized_body, Time.now.to_i)
        signature_headers.each { |key, value| req[key] = value }
      end

      req
    end

    def handle_response(response)
      status = response.code.to_i
      return handle_error(response, status) unless status.between?(200, 299)

      body = response.body
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    end

    def handle_error(response, status)
      parsed =
        begin
          body = response.body
          body && !body.empty? ? JSON.parse(body) : {}
        rescue JSON::ParserError
          {}
        end

      message = parsed["message"] || "HTTP #{status}"
      code = parsed["code"]

      case status
      when 400
        raise ValidationError.new(message, field: parsed["field"], code: code)
      when 401
        raise AuthenticationError.new(message, code: code)
      when 403
        raise PermissionError.new(message, code: code)
      when 404
        raise NotFoundError.new(message, code: code)
      when 429
        raise RateLimitError.new(message, retry_after: parse_retry_after(response), code: code)
      else
        raise Error.new(message, status_code: status, code: code)
      end
    end

    # Preserves a legitimate `Retry-After: 0` (retry now) as 0, distinct
    # from an absent or unparsable header (nil).
    def parse_retry_after(response)
      header = response["Retry-After"]
      return nil if header.nil?

      Integer(header, exception: false)
    end
  end
end
