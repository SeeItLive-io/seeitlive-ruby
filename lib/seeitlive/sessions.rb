require "erb"
require_relative "http"

module SeeItLive
  # Response of Sessions#create. Wire format is camelCase; fields are
  # mapped to idiomatic snake_case Ruby accessors.
  Session = Struct.new(:id, :status, :invite_code, :invite_url, :invite_short_url, :agent_view_url, :metadata, :expires_at, :protection, :protection_secret, :protection_otpauth_url, keyword_init: true)

  # Response of Sessions#status. Wire format is camelCase; fields are
  # mapped to idiomatic snake_case Ruby accessors.
  SessionStatus = Struct.new(:id, :status, :started_at, :ended_at, :producer_count, :has_video, keyword_init: true)

  # Response of Sessions#get_protection and #set_protection. For "totp",
  # `code` is the CURRENT code, never the seed -- the seed leaves the server
  # only once, in the create response.
  ProtectionInfo = Struct.new(:type, :password, :code, :seconds_remaining, :locked, :failed_attempts, keyword_init: true)

  # Response of Sessions#reshare. `invite_short_url` is nil when the session
  # has no short link -- it can be extended but not re-sent. `rotated` is
  # true when a new code/link was issued (`mode: "new"`).
  ReshareResult = Struct.new(:expires_at, :invite_short_url, :resend, :rotated, keyword_init: true)

  # A session's invitation as the agent side sees it -- never the token
  # hash and never the guest secret.
  SessionInvitation = Struct.new(:code, :channel, :recipient, :expires_at, :opened_at, keyword_init: true)

  # Response of Sessions#get: a stored session read back by id, unlike
  # `Session` which is the one-time create response.
  SessionDetail = Struct.new(:id, :team_id, :env, :status, :created_by_client_id, :created_by_api_key_id, :note, :metadata, :started_at, :ended_at, :created_at, :invitation, keyword_init: true)

  # Response of Sessions#create_agent_token. Tokens expire after 120
  # minutes; mint another to re-open a viewer.
  AgentToken = Struct.new(:code, :token, :agent_view_url, keyword_init: true)

  # The `sessions` resource: `create` and `status`. Accessed as
  # `client.sessions`; not constructed directly.
  class Sessions
    # snake_case keyword -> camelCase wire key, for the params accepted by
    # #create. Any keyword not listed here is camelCased generically (see
    # #camelize) so forward-compatible with future API fields.
    WIRE_KEYS = {
      recipient_phone: "recipientPhone",
      recipient_email: "recipientEmail",
      ttl_minutes: "ttlMinutes",
    }.freeze

    def initialize(http)
      @http = http
    end

    # POST /sessions. `params` accepts `channel:` (required: "sms" |
    # "email" | "link"), `recipient_phone:`, `recipient_email:`, `note:`,
    # `ttl_minutes:`, `sms_consent:`, `metadata:`, `short_link:`,
    # `protection:`, `protection_secret:` (all optional; nil values are
    # omitted from the request body). `metadata:` is a flat hash of string
    # keys to string values. For the "sms" channel the API requires
    # `sms_consent: true` -- the recipient must have agreed to receive a
    # text (carrier fees may apply). `short_link: true` requests that the
    # API also mint a `sitl.cc/s/<code>` short link for the session invite.
    # `protection:` requires the guest to answer a challenge before sharing
    # camera -- "password" (a static secret) or "totp" (a rotating 6-digit
    # code the agent reads aloud) -- and `protection_secret:` is the
    # password or base32 TOTP seed; leave it out and the API generates one,
    # returned once on the created Session. The SDK does NOT send a team id
    # -- the team is implicit from the API key / OAuth token used to
    # construct the client.
    def create(**params)
      body = params.each_with_object({}) do |(key, value), acc|
        next if value.nil?

        acc[WIRE_KEYS.fetch(key, camelize(key))] = value
      end
      raw = @http.request("/sessions", method: :post, body: body)
      session_from(raw)
    end

    # GET /sessions/{id}. Reads a stored session, including how its
    # invitation was delivered (channel/recipient), so an agent re-opening
    # a session sees how the customer was reached. `invitation` is nil for
    # a session whose invitation is gone.
    def get(id)
      raw = @http.request("/sessions/#{encode_path_segment(id)}")
      session_detail_from(raw)
    end

    # GET /sessions/{id}/status
    def status(id)
      raw = @http.request("/sessions/#{encode_path_segment(id)}/status")
      session_status_from(raw)
    end

    # GET /sessions/{id}/protection. The secret to read to the customer: the
    # password, or the rotating code of the moment.
    def get_protection(id)
      raw = @http.request("/sessions/#{encode_path_segment(id)}/protection")
      protection_info_from(raw)
    end

    # PUT /sessions/{id}/protection. Changes a session's guest challenge
    # after creation -- including adding one to a session created without
    # any, which is otherwise impossible. `protection:` is "none",
    # "password" or "totp"; leave `protection_secret:` out and the API
    # generates one. `protection: "none"` clears the challenge and any
    # lockout the customer triggered along with it.
    def set_protection(id, protection:, protection_secret: nil)
      body = { "protection" => protection }
      # Only send the key when given one: absence is what tells the API to
      # generate a secret, so a nil must not become an explicit null.
      body["protectionSecret"] = protection_secret unless protection_secret.nil?
      raw = @http.request("/sessions/#{encode_path_segment(id)}/protection", method: :put, body: body)
      protection_info_from(raw)
    end

    # POST /sessions/{id}/protection/reset. Clears a guest lockout.
    # Rotation is opt-in (`rotate: true`): the usual cause of a lockout is
    # the customer mistyping, and a new secret would just make the agent
    # read it out again for no security gain.
    def reset_protection(id, rotate: nil)
      body = {}
      body["rotate"] = rotate unless rotate.nil?
      raw = @http.request("/sessions/#{encode_path_segment(id)}/protection/reset", method: :post, body: body)
      protection_info_from(raw)
    end

    # POST /sessions/{id}/agent-token. Mints a fresh agent-view token so an
    # embedded viewer can watch the session. `label:` names the viewer in
    # the dashboard's list (e.g. "Odoo - crm.lead 42"); leave it out and
    # the API applies its own default, branched by principal.
    def create_agent_token(id, label: nil)
      body = {}
      body["label"] = label unless label.nil?
      raw = @http.request("/sessions/#{encode_path_segment(id)}/agent-token", method: :post, body: body)
      AgentToken.new(code: raw["code"], token: raw["token"], agent_view_url: raw["agentViewUrl"])
    end

    # POST /sessions/{id}/reshare. Revives an expired invitation. `mode:
    # "revive"` (the default) extends the SAME link and code in place, so a
    # message the customer already has starts working again; `mode: "new"`
    # issues a fresh link and kills the old one. All keywords are optional;
    # an omitted one is left out of the request body entirely and means
    # "reuse what the invitation already recorded". `sms_consent:` is
    # required and must be true when `channel:` is "sms".
    #
    # A session created without a short link can be extended but not
    # re-sent -- the plaintext token survives only in the short link's
    # encrypted fragment. `resend` on the result reports which happened.
    def reshare(id, mode: nil, channel: nil, recipient: nil, sms_consent: nil)
      body = {}
      body["mode"] = mode unless mode.nil?
      body["channel"] = channel unless channel.nil?
      body["recipient"] = recipient unless recipient.nil?
      body["smsConsent"] = sms_consent unless sms_consent.nil?
      raw = @http.request("/sessions/#{encode_path_segment(id)}/reshare", method: :post, body: body)
      reshare_result_from(raw)
    end

    private

    def session_detail_from(raw)
      invitation = raw["invitation"]
      SessionDetail.new(
        id: raw["id"],
        team_id: raw["teamId"],
        env: raw["env"],
        status: raw["status"],
        created_by_client_id: raw["createdByClientId"],
        created_by_api_key_id: raw["createdByApiKeyId"],
        note: raw["note"],
        metadata: raw["metadata"],
        started_at: raw["startedAt"],
        ended_at: raw["endedAt"],
        created_at: raw["createdAt"],
        invitation: invitation && SessionInvitation.new(
          code: invitation["code"],
          channel: invitation["channel"],
          recipient: invitation["recipient"],
          expires_at: invitation["expiresAt"],
          opened_at: invitation["openedAt"],
        ),
      )
    end

    def protection_info_from(raw)
      ProtectionInfo.new(
        type: raw["type"],
        password: raw["password"],
        code: raw["code"],
        seconds_remaining: raw["secondsRemaining"],
        locked: raw["locked"],
        failed_attempts: raw["failedAttempts"],
      )
    end

    def reshare_result_from(raw)
      ReshareResult.new(
        expires_at: raw["expiresAt"],
        invite_short_url: raw["inviteShortUrl"],
        resend: raw["resend"],
        rotated: raw["rotated"],
      )
    end

    def session_from(raw)
      Session.new(
        id: raw["id"],
        status: raw["status"],
        invite_code: raw["inviteCode"],
        invite_url: raw["inviteUrl"],
        invite_short_url: raw["inviteShortUrl"],
        agent_view_url: raw["agentViewUrl"],
        metadata: raw["metadata"],
        expires_at: raw["expiresAt"],
        protection: raw["protection"],
        protection_secret: raw["protectionSecret"],
        protection_otpauth_url: raw["protectionOtpauthUrl"],
      )
    end

    def session_status_from(raw)
      SessionStatus.new(
        id: raw["id"],
        status: raw["status"],
        started_at: raw["startedAt"],
        ended_at: raw["endedAt"],
        producer_count: raw["producerCount"],
        has_video: raw["hasVideo"],
      )
    end

    def camelize(key)
      key.to_s.gsub(/_([a-z0-9])/) { Regexp.last_match(1).upcase }
    end

    # Minimal percent-encoding matching JavaScript's encodeURIComponent,
    # for a single path segment (session ids are opaque server-generated
    # identifiers).
    def encode_path_segment(segment)
      ERB::Util.url_encode(segment.to_s)
    end
  end
end
