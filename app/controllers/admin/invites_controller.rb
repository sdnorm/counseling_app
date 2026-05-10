class Admin::InvitesController < ApplicationController
  http_basic_authenticate_with name: "admin", password: Rails.application.credentials.dig(:admin, :password) || "changeme"

  def index
    @codes = InviteCode.order(created_at: :desc)
  end

  def create
    @code = InviteCode.generate
    redirect_to admin_invites_path, notice: "Code generated: #{@code.code}"
  end
end
