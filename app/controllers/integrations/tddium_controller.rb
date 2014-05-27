require 'octokit'

class Integrations::TddiumController < Integrations::BaseController
  protected

  def deploy?
    params[:status] == 'passed' &&
      params[:event] == 'stop' &&
      !skip?
  end

  def skip?
    # Tddium doesn't send commit message, so we have to get creative
    repo_name = "#{params[:repository][:org_name]}/#{params[:repository][:name]}"
    data = GITHUB.commit(repo_name, params[:commit_id])

    ["[deploy skip]", "[skip deploy]"].any? do |token|
      data.commit.message.include?(token)
    end

  rescue Octokit::Error => e
    Rails.logger.info("Error trying to grab commit: #{e.message}")
    # We'll assume that if we don't hear back, don't skip
    false
  end

  def branch
    params[:branch]
  end

  def commit
    params[:commit_id]
  end

  def user
    name = "Tddium"
    email = "deploy+tddium@zendesk.com"

    User.create_with(name: name).find_or_create_by(email: email)
  end
end
