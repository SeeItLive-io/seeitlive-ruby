require "erb"
require_relative "http"

module SeeItLive
  # One entry of Snapshots#list. `url` is the API path the bytes are
  # served from.
  SnapshotSummary = Struct.new(:id, :width, :height, :captured_at, :url, keyword_init: true)

  # Response of Snapshots#get. `data` is the base64-encoded PNG.
  SnapshotImage = Struct.new(:id, :content_type, :width, :height, :captured_at, :data, keyword_init: true)

  # The `snapshots` resource: `list` and `get`. Accessed as
  # `client.snapshots`; not constructed directly. Both calls require the
  # team's plan to include snapshot history.
  class Snapshots
    def initialize(http)
      @http = http
    end

    # GET /sessions/{id}/snapshots. A session's snapshots, newest first.
    def list(session_id)
      raw = @http.request("/sessions/#{encode_path_segment(session_id)}/snapshots")
      raw.map do |item|
        SnapshotSummary.new(
          id: item["id"],
          width: item["width"],
          height: item["height"],
          captured_at: item["capturedAt"],
          url: item["url"],
        )
      end
    end

    # GET /snapshots/{id}?format=base64. The endpoint serves raw PNG bytes
    # by default; the SDK asks for base64 JSON so the response stays JSON --
    # and signs the query along with the path, which is what the server
    # verifies. Decode `data` (Base64.decode64) to get the PNG bytes.
    def get(id)
      raw = @http.request("/snapshots/#{encode_path_segment(id)}?format=base64")
      SnapshotImage.new(
        id: raw["id"],
        content_type: raw["contentType"],
        width: raw["width"],
        height: raw["height"],
        captured_at: raw["capturedAt"],
        data: raw["data"],
      )
    end

    private

    # Minimal percent-encoding matching JavaScript's encodeURIComponent,
    # for a single path segment (ids are opaque server-generated values).
    def encode_path_segment(segment)
      ERB::Util.url_encode(segment.to_s)
    end
  end
end
