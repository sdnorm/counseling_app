class Admin::InvitesController < ApplicationController
  layout "admin"
  allow_unauthenticated_access
  http_basic_authenticate_with name: "admin", password: Rails.application.credentials.dig(:admin, :password) || "changeme"

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

  def invite_params
    params.require(:invite).permit(:email_address)
  end

  def set_no_cache_headers
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"
  end
end
