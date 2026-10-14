Contributor = Data.define(:login, :avatar_url, :url, :contributions) do
  def self.from_api(h)
    new(login: h["login"], avatar_url: h["avatar_url"], url: h["html_url"],
        contributions: h["contributions"])
  end
end
