# timeouts, and turning GitHub's failures into the errors below.
class GithubConnector
  class Error < StandardError
    def http_status
      :bad_gateway
    end
  end

  class RateLimitError < Error
    attr_reader :reset_at
    def initialize(reset_at = nil)
      @reset_at = reset_at
      super("GitHub API rate limit exceeded")
    end
    def http_status
      :too_many_requests
    end
  end

  class InvalidQueryError < Error
    def http_status
      :unprocessable_content
    end
  end

  class NotFoundError < Error
    def http_status
      :not_found
    end
  end

  BASE_URL = "https://api.github.com"

  def initialize(token: ENV["GITHUB_TOKEN"])
    @token = token
  end

  # Returns the parsed JSON body, or raises a GithubConnector::Error.
  def get(path, params = {})
    handle(connection.get(path, params))
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed
    raise Error, "Could not reach GitHub"
  end

  private

  def connection
    @connection ||= Faraday.new(BASE_URL) do |f|
      f.headers["Accept"] = "application/vnd.github+json"
      f.headers["Authorization"] = "Bearer #{@token}" if @token.present?
      f.options.open_timeout = 2
      f.options.timeout = 5
      f.response :json
    end
  end

  def handle(response)
    case response.status
    # 204 No Content (e.g. contributors of an empty repo) comes back as nil.
    when 200..299 then response.body.presence
    when 404 then raise NotFoundError, "Not found on GitHub"
    when 422 then raise InvalidQueryError, response.body["message"]
    when 403, 429
      if response.status == 429 || response.headers["x-ratelimit-remaining"] == "0"
        reset = response.headers["x-ratelimit-reset"]
        raise RateLimitError.new(reset && Time.zone.at(reset.to_i))
      end
      raise Error, "GitHub refused the request"
    else
      raise Error, "GitHub returned #{response.status}"
    end
  end
end
