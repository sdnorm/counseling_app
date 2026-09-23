# app/controllers/dashboard/sessions_controller.rb
class Dashboard::SessionsController < Dashboard::BaseController
  allow_unauthenticated_counselor_access only: %i[ new create ]
  skip_before_action :require_billing_open
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_counselor_session_path, alert: "Try again later." }

  def new
    redirect_to counselor_root_path if counselor_signed_in?
  end

  def create
    counselor = Counselor.active.authenticate_by(params.permit(:email_address, :password))
    if counselor
      start_new_counselor_session_for counselor
      redirect_to counselor_root_path
    else
      redirect_to new_counselor_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_counselor_session
    redirect_to new_counselor_session_path, status: :see_other
  end
end
