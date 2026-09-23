# app/controllers/dashboard/passwords_controller.rb
class Dashboard::PasswordsController < Dashboard::BaseController
  allow_unauthenticated_counselor_access
  before_action :set_counselor_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_counselor_password_path, alert: "Try again later." }

  def new
  end

  def create
    if (counselor = Counselor.active.find_by(email_address: params[:email_address]))
      CounselorPasswordsMailer.reset(counselor).deliver_later
    end
    redirect_to new_counselor_session_path, notice: "Password reset instructions sent (if that email has a counselor account)."
  end

  def edit
  end

  def update
    if params[:password].blank?
      return redirect_to edit_counselor_password_path(params[:token]), alert: "Password can't be blank."
    end

    if @counselor.update(params.permit(:password, :password_confirmation))
      @counselor.sessions.destroy_all
      redirect_to new_counselor_session_path, notice: "Password has been reset."
    else
      redirect_to edit_counselor_password_path(params[:token]), alert: @counselor.errors.full_messages.to_sentence
    end
  end

  private
    def set_counselor_by_token
      @counselor = Counselor.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_counselor_password_path, alert: "Password reset link is invalid or has expired."
    end
end
