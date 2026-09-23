# app/controllers/platform/base_controller.rb
class Platform::BaseController < Dashboard::BaseController
  before_action :require_platform_admin

  private

  # 404 rather than 403: non-admins should not learn the pages exist.
  def require_platform_admin
    head :not_found unless current_counselor.platform_admin?
  end
end
