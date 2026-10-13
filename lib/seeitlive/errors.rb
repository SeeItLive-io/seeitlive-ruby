module SeeItLive
  # Base error for all non-2xx API responses. Network/transport failures
  # (DNS, connection refused, timeouts, ...) are NOT wrapped in this
  # hierarchy -- they surface as Ruby's natural `SystemCallError` /
  # `Net::*` exceptions from the underlying `Net::HTTP` call.
  class Error < StandardError
    attr_reader :status_code, :code

    def initialize(message, status_code:, code: nil)
      super(message)
      @status_code = status_code
      @code = code
    end
  end

  # HTTP 400. Carries `field` when the API response body included one.
  class ValidationError < Error
    attr_reader :field

    def initialize(message, field: nil, code: nil)
      super(message, status_code: 400, code: code)
      @field = field
    end
  end

  # HTTP 401.
  class AuthenticationError < Error
    def initialize(message = "Authentication failed", code: nil)
      super(message, status_code: 401, code: code)
    end
  end

  # HTTP 403.
  class PermissionError < Error
    def initialize(message = "Forbidden", code: nil)
      super(message, status_code: 403, code: code)
    end
  end

  # HTTP 404.
  class NotFoundError < Error
    def initialize(message = "Not found", code: nil)
      super(message, status_code: 404, code: code)
    end
  end

  # HTTP 429. `retry_after` is the integer number of seconds from a
  # `Retry-After` header, `nil` when the header was absent or unparsable.
  # A legitimate `Retry-After: 0` (retry immediately) is preserved as `0`,
  # distinct from `nil` (no header sent at all) -- callers must check
  # explicitly, not treat `nil` as "no need to wait".
  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = "Rate limited", retry_after: nil, code: nil)
      super(message, status_code: 429, code: code)
      @retry_after = retry_after
    end
  end
end
