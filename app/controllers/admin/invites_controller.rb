class Admin::InvitesController < ApplicationController
  layout "admin"
  allow_unauthenticated_access
  before_action :authenticate_admin
  before_action :set_no_cache_headers

  def index
    @codes = InviteCode.order(created_at: :desc)
  end

  def create
    email_address = invite_params[:email_address].to_s.strip.downcase

    if email_address.blank?
      redirect_to admin_invites_path, alert: "Please provide a client email address."
      return
    end

    @code = InviteCode.generate(email_address)
    InvitesMailer.invite(@code).deliver_now

    redirect_to admin_invites_path, notice: "Code #{@code.code} generated and sent to #{@code.email_address}."
  end

  private

  # Fails closed: admin access is impossible until an admin password is
  # configured in the environment's encrypted credentials.
  def authenticate_admin
    expected = Rails.application.credentials.dig(:admin, :password)
    return request_http_basic_authentication if expected.blank?

    authenticate_or_request_with_http_basic do |name, password|
      ActiveSupport::SecurityUtils.secure_compare(name, "admin") &
        ActiveSupport::SecurityUtils.secure_compare(password, expected)
    end
  end

  def invite_params
    params.require(:invite).permit(:email_address)
  end

  def set_no_cache_headers
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"
  end
end
