require "test_helper"

# End-to-end through the real connector, service and views; WebMock plays GitHub.
class RepositoriesControllerTest < ActionDispatch::IntegrationTest
  API = "https://api.github.com".freeze
  BROWSER_ACCEPT = "text/html,application/xhtml+xml,*/*;q=0.8".freeze

  def stub_github(path, body: {}, status: 200, headers: {}, query: hash_including({}))
    stub_request(:get, "#{API}#{path}").with(query:).to_return(
      status:, body: body.to_json, headers: { "Content-Type" => "application/json" }.merge(headers)
    )
  end

  # Contributors aren't stubbed: the page loads them lazily in a separate request,
  # and WebMock would fail the test if the page tried to fetch them itself.
  def stub_repo_page(owner: "hotwired", name: "turbo")
    stub_github("/repos/#{owner}/#{name}", body: repo_json("name" => name, "full_name" => "#{owner}/#{name}",
                                                           "owner" => { "login" => owner, "avatar_url" => "https://avatars.example.com/x.png" }))
    stub_github("/repos/#{owner}/#{name}/languages", body: { "TypeScript" => 800, "JavaScript" => 200 })
  end

  def rate_limited_headers
    { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => 39.minutes.from_now.to_i.to_s }
  end

  # --- index ---------------------------------------------------------------

  test "home page lists popular repositories" do
    github = stub_github("/search/repositories", body: search_json, query: hash_including(q: "stars:>1000"))

    get root_path

    assert_response :success
    assert_requested github
    assert_select "p", /Popular repositories/
    assert_select "article", 1
    assert_select "article a[href=?]", "/repositories/hotwired/turbo"
  end

  test "searching passes the query, language and sort to GitHub" do
    github = stub_github("/search/repositories", body: search_json(total_count: 45),
                         query: hash_including(q: "turbo language:JavaScript", sort: "stars"))

    get repositories_path(q: "turbo", language: "JavaScript", sort: "stars")

    assert_response :success
    assert_requested github
    assert_select "p", /45 results for “turbo”/
    assert_select "a", text: "Next →"
  end

  test "the form shows the current search when the page is loaded from a link" do
    stub_github("/search/repositories", body: search_json)

    get repositories_path(q: "turbo", language: "Go", sort: "stars")

    assert_select "input[name=q][value=?]", "turbo"
    assert_select "select[name=language] option[selected]", "Go"
    assert_select "select[name=sort] option[selected]", "Most stars"
  end

  test "shows a message when nothing matches" do
    stub_github("/search/repositories", body: search_json(items: []))

    get repositories_path(q: "zzzz")

    assert_select "p", /No repositories match “zzzz”/
  end

  test "index as JSON" do
    stub_github("/search/repositories", body: search_json(total_count: 1))

    get repositories_path(q: "turbo"), as: :json

    assert_response :success
    assert_equal 1, response.parsed_body["total_count"]
    assert_equal "hotwired/turbo", response.parsed_body.dig("items", 0, "full_name")
  end

  # --- index errors ----------------------------------------------------------

  test "an invalid search returns 422 and keeps the search form" do
    stub_github("/search/repositories", status: 422, body: { "message" => "Validation Failed" })

    get repositories_path(q: "is:")

    assert_response :unprocessable_content
    assert_select "[role=alert]", /couldn't process that search/
    assert_select "form input[name=q][value=?]", "is:"
  end

  test "hitting GitHub's rate limit returns 429" do
    stub_github("/search/repositories", status: 403,
                headers: { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => 1.minute.from_now.to_i.to_s })

    get repositories_path(q: "turbo")

    assert_response :too_many_requests
    assert_select "[role=alert]", /rate limit was reached/
  end

  test "GitHub timing out returns 502" do
    stub_request(:get, %r{api.github.com/search}).to_timeout

    get repositories_path(q: "turbo")

    assert_response :bad_gateway
    assert_select "[role=alert]", /couldn't reach GitHub/
  end

  test "errors as JSON" do
    stub_github("/search/repositories", status: 422, body: { "message" => "Validation Failed" })

    get repositories_path(q: "is:"), as: :json

    assert_response :unprocessable_content
    assert_equal({ "error" => "invalid_query_error", "message" => "Validation Failed" }, response.parsed_body)
  end

  # --- show ----------------------------------------------------------------

  test "repository page shows details and languages, and lazy-loads contributors" do
    stub_repo_page

    get repository_path("hotwired", "turbo")

    assert_response :success
    assert_select "h1", /turbo/
    assert_select "a[href=?]", "https://github.com/hotwired/turbo"
    assert_select "li", /TypeScript\s*80.0%/
    assert_select "turbo-frame#contributors[loading=lazy][src=?]", "/repositories/hotwired/turbo/contributors"
  end

  test "repo names with dots work for browsers, not just curl" do
    stub_repo_page(owner: "vercel", name: "next.js")

    get repository_path("vercel", "next.js"), headers: { "Accept" => BROWSER_ACCEPT }

    assert_response :success
    assert_equal "text/html", response.media_type
  end

  test "repository as JSON" do
    stub_repo_page

    get repository_path("hotwired", "turbo"), headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal "hotwired/turbo", response.parsed_body["full_name"]
    assert_equal "TypeScript", response.parsed_body.dig("languages", 0, "name")
  end

  test "an unknown repository shows a 404 page" do
    stub_github("/repos/nobody/nothing", status: 404, body: { "message" => "Not Found" })

    get repository_path("nobody", "nothing")

    assert_response :not_found
    assert_select "h1", "Repository not found"
  end

  test "hitting the rate limit on a repository says so in the title" do
    stub_github("/repos/hotwired/turbo", status: 403, headers: rate_limited_headers)

    get repository_path("hotwired", "turbo")

    assert_response :too_many_requests
    assert_select "h1", "Rate limit reached"
    assert_select "[role=alert] p", /Try again in 39 minutes/
  end

  test "GitHub being down says so in the title" do
    stub_request(:get, %r{api.github.com/repos}).to_timeout

    get repository_path("hotwired", "turbo")

    assert_response :bad_gateway
    assert_select "h1", "GitHub is unavailable"
  end

  test "a rate limit on contributors shows the retry time inside the frame" do
    stub_github("/repos/hotwired/turbo/contributors", status: 403, headers: rate_limited_headers)

    get repository_contributors_path("hotwired", "turbo"), headers: { "Turbo-Frame" => "contributors" }

    assert_response :too_many_requests
    assert_select "turbo-frame#contributors p", /rate limit was reached. Try again in 39 minutes/
  end

  test "back link returns to the search the user came from" do
    stub_repo_page

    get repository_path("hotwired", "turbo"), headers: { "Referer" => "http://www.example.com/repositories?q=turbo&page=2" }

    assert_select "a[href=?]", "/repositories?q=turbo&page=2", text: "← Back to results"
  end
end
