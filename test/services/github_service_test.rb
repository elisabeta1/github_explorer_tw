require "test_helper"

# Tests the service's own logic with a fake connector: no HTTP involved.
# (HTTP and error mapping are covered end-to-end in the controller test.)
class GithubServiceTest < ActiveSupport::TestCase
  # Stands in for GithubConnector: returns canned bodies by path and records calls.
  class FakeConnector
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def get(path, params = {})
      @calls << [ path, params ]
      response = @responses.fetch(path) { raise "Unexpected GitHub call: #{path}" }
      response.is_a?(Exception) ? raise(response) : response
    end
  end

  def search_with(**options)
    connector = FakeConnector.new("/search/repositories" => search_json)
    result = GithubService.new(connector:).search_repositories(**options)
    [ result, connector.calls.last.last ]
  end

  # --- search_repositories: query building ---------------------------------

  test "shows popular repositories when nothing is searched" do
    _, params = search_with(query: "  ")
    assert_equal({ q: "stars:>1000", order: "desc", per_page: 20, page: 1 }, params)
  end

  test "combines the query with a language filter" do
    _, params = search_with(query: " rails ", language: "Ruby")
    assert_equal "rails language:Ruby", params[:q]
  end

  test "searches by language alone" do
    _, params = search_with(language: "Go")
    assert_equal "language:Go", params[:q]
  end

  test "ignores languages and sorts it doesn't know" do
    _, params = search_with(query: "x", language: "Cobol stars:>1", sort: "chaos")
    assert_equal "x", params[:q]
    assert_not params.key?(:sort)
  end

  test "sends a known sort, and none for best match" do
    assert_equal "stars", search_with(query: "x", sort: "stars").last[:sort]
    assert_not search_with(query: "x", sort: "").last.key?(:sort)
  end

  test "clamps the page to what GitHub can serve" do
    assert_equal 1, search_with(page: nil).last[:page]
    assert_equal 1, search_with(page: "-5").last[:page]
    assert_equal 50, search_with(page: "999").last[:page]
  end

  # --- search_repositories: result -----------------------------------------

  test "returns Repository objects and paging info" do
    connector = FakeConnector.new("/search/repositories" => search_json(total_count: 45))
    result = GithubService.new(connector:).search_repositories(query: "turbo", page: 2)

    assert_equal 45, result.total_count
    assert_equal 2, result.page
    assert_equal 3, result.total_pages
    repo = result.repositories.first
    assert_kind_of Repository, repo
    assert_equal "hotwired", repo.owner
    assert_equal "turbo", repo.name
    assert_equal 7_123, repo.stars
  end

  test "caps total pages at GitHub's 1,000 result limit" do
    connector = FakeConnector.new("/search/repositories" => search_json(total_count: 2_000_000))
    assert_equal 50, GithubService.new(connector:).search_repositories.total_pages
  end

  # --- repository_details --------------------------------------------------

  # No contributors path here: FakeConnector raises on unexpected calls, so this
  # also proves repository_details doesn't fetch them (they're loaded lazily).
  def details_connector(languages: { "JavaScript" => 700, "Ruby" => 300 })
    FakeConnector.new(
      "/repos/hotwired/turbo" => repo_json,
      "/repos/hotwired/turbo/languages" => languages
    )
  end

  test "groups small and extra languages into Other" do
    languages = { "A" => 400, "B" => 200, "C" => 150, "D" => 100, "E" => 60, "F" => 40,
                  "G" => 30, "Tiny" => 5, "Tinier" => 5 } # total 990; G is 7th, Tiny/Tinier < 1%
    details = GithubService.new(connector: details_connector(languages:)).repository_details("hotwired", "turbo")

    assert_equal %w[A B C D E F Other], details.languages.map(&:name)
    assert_in_delta 4.0, details.languages.last.percent, 0.1
    assert_in_delta 100, details.languages.sum(&:percent), 0.5
  end

  test "leaves out Other when it would round to 0.0%" do
    languages = { "JavaScript" => 434_262, "Dockerfile" => 180 } # Dockerfile is 0.04%
    details = GithubService.new(connector: details_connector(languages:)).repository_details("hotwired", "turbo")

    assert_equal [ [ "JavaScript", 100.0 ] ], details.languages.map { [ _1.name, _1.percent ] }
  end

  test "has no languages for a repo GitHub detected none in" do
    details = GithubService.new(connector: details_connector(languages: {})).repository_details("hotwired", "turbo")
    assert_equal [], details.languages
  end

  # --- contributors --------------------------------------------------------

  def contributors_connector(response)
    FakeConnector.new("/repos/hotwired/turbo/contributors" => response)
  end

  test "returns the top 12 contributors" do
    connector = contributors_connector([ contributor_json ])
    contributors = GithubService.new(connector:).contributors("hotwired", "turbo")

    assert_equal [ "sstephenson" ], contributors.map(&:login)
    assert_equal 1_234, contributors.first.contributions
    assert_equal [ [ "/repos/hotwired/turbo/contributors", { per_page: 12 } ] ], connector.calls
  end

  test "an empty repo (GitHub sends 204, so nil) has no contributors" do
    assert_equal [], GithubService.new(connector: contributors_connector(nil)).contributors("hotwired", "turbo")
  end

  test "contributor errors are raised, for the controller to show in the frame" do
    refused = GithubConnector::Error.new("The history or contributor list is too large")
    assert_raises(GithubConnector::Error) do
      GithubService.new(connector: contributors_connector(refused)).contributors("hotwired", "turbo")
    end
  end

  test "a missing repository raises NotFoundError" do
    connector = FakeConnector.new("/repos/nobody/nothing" => GithubConnector::NotFoundError.new("Not found"))
    assert_raises(GithubConnector::NotFoundError) do
      GithubService.new(connector:).repository_details("nobody", "nothing")
    end
  end

  test "escapes owner and name in the API path" do
    connector = FakeConnector.new("/repos/a%20b/c%2Fd" => GithubConnector::NotFoundError.new("Not found"))
    assert_raises(GithubConnector::NotFoundError) { GithubService.new(connector:).repository_details("a b", "c/d") }
    assert_equal "/repos/a%20b/c%2Fd", connector.calls.first.first
  end
end
