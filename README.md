# GitHub Repository Explorer

A small Rails + Hotwire app for browsing GitHub repositories through the GitHub REST API.

## Features
- **Search** repositories by keyword, **filter** by language and **sort** by stars, forks or recently updated
- Pagination (GitHub returns at most 1,000 search results, so pages are capped at 50)
- With no search, shows popular repositories (`stars:>1000`), because GitHub requires a query
- Repository page: stats, topics, license, a language breakdown bar, and top contributors
- Contributors load lazily (Turbo Frame), so they only cost an API call when scrolled into view
- Responsive layout with Tailwind CSS
- JSON responses for every page (`Accept: application/json` or `.json` on the search)

## Running it
Requirements: Ruby 3.3, Bundler.

```bash
bundle install
export GITHUB_TOKEN=your_token   # optional, but strongly recommended
bin/dev                          # Rails server + Tailwind watcher
```
Open http://localhost:3000 (use `PORT=3200 bin/dev` if port 3000 is taken).

**GITHUB_TOKEN:** without a token GitHub allows 60 requests an hour. With one it allows 5,000.
A classic or fine-grained token with **no scopes** is enough, because the app only reads public data.

## Tests
```bash
bin/rails test
```
The tests never call the real GitHub API:
- **Service tests** use a fake connector, so they test the logic alone.
- **Controller tests** use WebMock to fake GitHub's HTTP responses (including errors and rate limits).

## How it's built
```
Controller  → GithubService   → GithubConnector → GitHub API
(HTTP/views)  (app logic)       (HTTP only)
```
- **`GithubConnector`** (`app/connectors`): Faraday client with timeouts. It turns GitHub's HTTP
  errors into Ruby errors (`NotFoundError`, `RateLimitError`, `InvalidQueryError`, `Error`).
- **`GithubService`** (`app/services`):
  - checks the user's input (only known languages and sorts, page limited to 1–50);
  - builds the search query;
  - caches responses for 10 minutes;
  - returns plain value objects (`Repository`, `Contributor`, made with `Data.define`).
- **`RepositoriesController`**: uses `rescue_from` to show each error with the right HTTP status
  (404, 422, 429, 502):
  - search errors appear inside the search page;
  - contributor errors appear inside their own frame;
  - so one failing part doesn't break the whole page.

## Trade-offs and next steps
- The language filter offers 9 common languages. A free-text or "other" option would be the next step.
- Moved/renamed repos (GitHub 301) aren't followed yet.
- Development caches in memory (per process). Production is configured for Solid Cache, which is
  shared across processes, so the cache survives restarts and saves rate limit.
