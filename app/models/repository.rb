Repository = Data.define(:owner, :name, :full_name, :description, :url, :homepage,
                         :language, :stars, :forks, :open_issues, :watchers, :topics,
                         :license, :default_branch, :archived, :owner_avatar,
                         :created_at, :updated_at, :pushed_at) do
  def self.from_api(h)
    new(owner: h.dig("owner", "login"), name: h["name"], full_name: h["full_name"],
        description: h["description"], url: h["html_url"], homepage: h["homepage"].presence,
        language: h["language"], stars: h["stargazers_count"], forks: h["forks_count"],
        open_issues: h["open_issues_count"],
        # Only the single-repo endpoint returns subscribers_count (real watchers).
        watchers: h["subscribers_count"],
        topics: Array(h["topics"]), license: h.dig("license", "spdx_id"),
        default_branch: h["default_branch"], archived: h["archived"] == true,
        owner_avatar: h.dig("owner", "avatar_url"),
        created_at: parse_time(h["created_at"]), updated_at: parse_time(h["updated_at"]),
        pushed_at: parse_time(h["pushed_at"]))
  end

  def self.parse_time(value)
    value && Time.zone.parse(value)
  end
end
