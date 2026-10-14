ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Tests must never call the real GitHub API.
WebMock.disable_net_connect!(allow_localhost: true)

# Sample GitHub API payloads, shared by the service and controller tests.
module GithubFixtures
  def repo_json(overrides = {})
    {
      "name" => "turbo",
      "full_name" => "hotwired/turbo",
      "owner" => { "login" => "hotwired", "avatar_url" => "https://avatars.example.com/hotwired.png" },
      "description" => "The speed of a single-page web application without the JavaScript",
      "html_url" => "https://github.com/hotwired/turbo",
      "homepage" => "https://turbo.hotwired.dev",
      "language" => "JavaScript",
      "stargazers_count" => 7_123,
      "forks_count" => 450,
      "open_issues_count" => 120,
      "subscribers_count" => 90,
      "topics" => %w[hotwire turbo],
      "license" => { "spdx_id" => "MIT" },
      "default_branch" => "main",
      "archived" => false,
      "created_at" => "2020-12-01T10:00:00Z",
      "updated_at" => "2026-10-01T10:00:00Z",
      "pushed_at" => "2026-10-01T10:00:00Z"
    }.merge(overrides)
  end

  def search_json(items: [ repo_json ], total_count: items.size)
    { "total_count" => total_count, "incomplete_results" => false, "items" => items }
  end

  def contributor_json(login = "sstephenson", contributions = 1_234)
    { "login" => login, "avatar_url" => "https://avatars.example.com/#{login}.png",
      "html_url" => "https://github.com/#{login}", "contributions" => contributions }
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include GithubFixtures
  end
end
