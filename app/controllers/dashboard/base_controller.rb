# app/controllers/dashboard/base_controller.rb
class Dashboard::BaseController < ApplicationController
  include CounselorAuthentication
  # These pages are for counselors; the client login is irrelevant here.
  allow_unauthenticated_access
  layout "counselor"
  before_action :set_no_cache_headers

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
end
