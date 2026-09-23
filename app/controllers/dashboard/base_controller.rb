# app/controllers/dashboard/base_controller.rb
class Dashboard::BaseController < ApplicationController
  include CounselorAuthentication
  # These pages are for counselors; the client login is irrelevant here.
  allow_unauthenticated_access
  layout "counselor"
  before_action :set_no_cache_headers
  before_action :require_billing_open

  private

  # A counselor's pages always wear their own practice, whatever host they
  # came in on. Before login, the host's practice or the generic brand.
  def brand
    @brand ||= Brand.new(current_counselor&.practice || Current.practice)
  end

  def set_no_cache_headers
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"
  end

  # A canceled or unpaid practice can only reach billing (owners) or the
  # explanation page (members). Clients are never affected by any of this.
  def require_billing_open
    return unless current_counselor&.practice&.billing_locked?
    if current_counselor.owner?
      redirect_to counselor_billing_path, alert: "Your subscription has ended. Restart it to continue."
    else
      render "dashboard/billings/locked", status: :payment_required
    end
  end
end
