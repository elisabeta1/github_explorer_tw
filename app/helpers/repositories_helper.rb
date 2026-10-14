module RepositoriesHelper
  # A few of GitHub's linguist colours; anything else falls back to grey.
  LANGUAGE_COLORS = {
    "C" => "#555555", "C#" => "#178600", "C++" => "#f34b7d", "CSS" => "#563d7c",
    "Dart" => "#00b4ab", "Elixir" => "#6e4a7e", "Go" => "#00add8", "HTML" => "#e34c26",
    "Java" => "#b07219", "JavaScript" => "#f1e05a", "Kotlin" => "#a97bff", "PHP" => "#4f5d95",
    "Python" => "#3572a5", "Ruby" => "#701516", "Rust" => "#dea584", "SCSS" => "#c6538c",
    "Shell" => "#89e051", "Swift" => "#f05138", "TypeScript" => "#3178c6", "Vue" => "#41b883"
  }.freeze

  def compact_number(n)
    number_to_human(n, units: { thousand: "k", million: "m" }, format: "%n%u", precision: 2)
  end

  def language_color(language)
    LANGUAGE_COLORS.fetch(language, "#9ca3af")
  end

  # Back to the search the user came from (keeping its filters), else home.
  def back_to_search_path
    referer = URI.parse(request.referer.to_s)
    from_search = referer.host == request.host && referer.path.in?([ root_path, repositories_path ])
    from_search ? referer.request_uri : root_path
  rescue URI::InvalidURIError
    root_path
  end

  # A short heading that says what actually happened.
  def github_error_title(error)
    case error
    when GithubConnector::RateLimitError then "Rate limit reached"
    when GithubConnector::NotFoundError then "Repository not found"
    when GithubConnector::InvalidQueryError then "Search couldn't be run"
    else "GitHub is unavailable"
    end
  end

  def github_error_message(error)
    case error
    when GithubConnector::RateLimitError
      wait = error.reset_at ? "in #{distance_of_time_in_words_to_now(error.reset_at)}" : "shortly"
      "GitHub's rate limit was reached. Try again #{wait}."
    when GithubConnector::InvalidQueryError
      "GitHub couldn't process that search. Try simplifying it."
    when GithubConnector::NotFoundError
      "We couldn't find that repository. It may be private, renamed or deleted."
    else
      "We couldn't reach GitHub right now. Please try again."
    end
  end
end
