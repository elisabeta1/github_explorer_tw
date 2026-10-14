class RepositoriesController < ApplicationController
  before_action :format_from_accept_header, only: %i[show contributors]
  rescue_from GithubConnector::Error, with: :render_github_error

  # Where each action shows a GitHub error, so the rest of the UI keeps working:
  # search errors inside the search page, contributor errors inside their frame,
  # anything else (show) on the error page.
  ERROR_TEMPLATES = { "index" => :index, "contributors" => :contributors }.freeze

  # GET /repositories?q=&language=&sort=&page=
  def index
    # Also used by the view, so the form shows the current search after a
    # refresh or when opened from a shared link.
    @query    = params[:q].to_s.strip
    @language = params[:language]
    @sort     = params[:sort]
    @result = GithubService.new.search_repositories(
      query: @query, language: @language,
      sort: @sort, page: params[:page]
    )

    respond_to do |format|
      format.html
      format.json do
        render json: { total_count: @result.total_count, page: @result.page,
                       total_pages: @result.total_pages,
                       items: @result.repositories.map(&:to_h) }
      end
    end
  end

  # GET /repositories/:owner/:name
  def show
    @details = GithubService.new.repository_details(params[:owner], params[:name])
    @repository = @details.repository

    respond_to do |format|
      format.html
      format.json { render json: @repository.to_h.merge(languages: @details.languages.map(&:to_h)) }
    end
  end

  # GET /repositories/:owner/:name/contributors
  # Loaded into the "contributors" Turbo Frame on the show page when it scrolls into view.
  def contributors
    @contributors = GithubService.new.contributors(params[:owner], params[:name])

    respond_to do |format|
      format.html
      format.json { render json: @contributors.map(&:to_h) }
    end
  end

  private

  def render_github_error(e)
    Rails.logger.warn("[GitHub] #{e.class}: #{e.message}")
    @error = e

    respond_to do |format|
      format.html { render ERROR_TEMPLATES.fetch(action_name, :error), status: e.http_status }
      format.json do
        render json: { error: e.class.name.demodulize.underscore,
                       message: e.message, reset_at: e.try(:reset_at) }.compact,
               status: e.http_status
      end
    end
  end

  # With a browser's Accept header Rails guesses the format from the URL's
  # "extension", so "next.js" would be treated as a JavaScript request (406).
  def format_from_accept_header
    request.format = request.accept.to_s.include?("application/json") ? :json : :html
  end
end
