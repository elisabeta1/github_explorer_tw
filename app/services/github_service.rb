# app/services/github_service.rb
#
# App-level repository search: validates the options, builds the GitHub query,
# caches results and returns Repository objects. HTTP lives in GithubConnector.
class GithubService
  PER_PAGE  = 20
  DEFAULT_QUERY = "stars:>1000"
  MAX_PAGE  = 1000 / PER_PAGE # GitHub only returns the first 1,000 search results
  SORTS     = { "Best match" => "", "Most stars" => "stars",
                "Most forks" => "forks", "Recently updated" => "updated" }.freeze
  LANGUAGES = %w[Ruby JavaScript TypeScript Python Go Rust Java PHP Elixir].freeze

  Result = Data.define(:repositories, :total_count, :page) do
    def total_pages
      [ (total_count / PER_PAGE.to_f).ceil, MAX_PAGE ].min
    end
  end

  Details  = Data.define(:repository, :languages)
  Language = Data.define(:name, :percent)
  MAX_LANGUAGES = 6 # the rest are grouped as "Other" so the bar stays readable

  def initialize(connector: GithubConnector.new)
    @connector = connector
  end

  def search_repositories(query: nil, language: nil, sort: nil, page: 1)
    query    = query.to_s.strip
    language = LANGUAGES.include?(language) ? language : nil
    sort     = SORTS.value?(sort) ? sort.presence : nil
    page     = page.to_i.clamp(1, MAX_PAGE)

    q = [ query, ("language:#{language}" if language) ].compact_blank.join(" ")
    # GitHub rejects an empty q with 422, so with no search show popular repos.
    q = DEFAULT_QUERY if q.blank?
    params = { q:, sort:, order: "desc", per_page: PER_PAGE, page: }.compact
    body = fetch("/search/repositories", params)

    Result.new(repositories: body["items"].map { Repository.from_api(_1) },
               total_count: body["total_count"], page:)
  end

  # The repository and its languages (2 API calls). Raises
  # GithubConnector::NotFoundError for unknown repos.
  def repository_details(owner, name)
    path = repo_path(owner, name)

    Details.new(repository: Repository.from_api(fetch(path)),
                languages: language_breakdown(fetch("#{path}/languages")))
  end

  # Top contributors. Loaded separately (lazily) by the repository page, so
  # it only costs an API call when someone scrolls to it.
  def contributors(owner, name)
    # Empty repos get a 204 from GitHub, which the connector returns as nil.
    Array(fetch("#{repo_path(owner, name)}/contributors", per_page: 12)).map { Contributor.from_api(_1) }
  end

  private

  def repo_path(owner, name)
    "/repos/#{ERB::Util.url_encode(owner)}/#{ERB::Util.url_encode(name)}"
  end

  def fetch(path, params = {})
    Rails.cache.fetch([ "github", path, params ], expires_in: 10.minutes) do
      @connector.get(path, params)
    end
  end

  # { "Ruby" => 52000, "HTML" => 3000 } (bytes) -> [Language("Ruby", 94.5), ...]
  def language_breakdown(bytes_by_language)
    bytes_by_language = bytes_by_language.to_h
    total = bytes_by_language.values.sum
    return [] if total.zero?

    sorted = bytes_by_language.sort_by { |_, bytes| -bytes }
    # Keep the biggest few, and fold the rest (and anything under 1%, which
    # would round to "0.0%") into "Other".
    top, rest = sorted.each_with_index.partition { |(_, bytes), i| i < MAX_LANGUAGES && bytes * 100.0 / total >= 1 }
                      .map { |group| group.map(&:first) }
    other_bytes = rest.sum { |_, bytes| bytes }
    # Skip an "Other" so small that it too would show as "0.0%".
    top << [ "Other", other_bytes ] if (other_bytes * 100.0 / total).round(1).positive?

    top.map { |lang, bytes| Language.new(name: lang, percent: (bytes * 100.0 / total).round(1)) }
  end
end
