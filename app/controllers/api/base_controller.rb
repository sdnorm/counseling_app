class Api::BaseController < ApplicationController
  # Every /api response names an account or carries its blob. no-store keeps
  # any cache — browser heuristics included — from replaying one account's
  # response into another account's unlock or reset.
  after_action :forbid_caching

  private

  def forbid_caching
    response.headers["Cache-Control"] = "no-store"
  end
end
