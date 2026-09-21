class PasswordsController < ApplicationController
  allow_unauthenticated_access
  layout "session"
  # JSON bodies here are flat. Without this, a body missing `password` would be
  # wrapped under params[:password] by ParamsWrapper and pass the blank check.
  wrap_parameters false
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  # The view renders @user's recovery-wrapped key, id, and email as data
  # attributes: the browser needs them to unwrap with a recovery code, stamp
  # the device, and salt the new password.
  def edit
  end

  # Three client paths land here, all with a new auth hash and both wrapped
  # keys: recovery code (no blob change), device re-key (`blob` replaces),
  # or start over (`wipe` destroys). The server can't tell which key material
  # is "right"; it only enforces that the pieces arrive together.
  def update
    if params[:password].blank?
      return render json: { errors: [ "Password can't be blank." ] }, status: :unprocessable_entity
    end
    if params[:password_wrapped_key].blank? || params[:recovery_wrapped_key].blank?
      return render json: { errors: [ "Both wrapped keys are required." ] }, status: :unprocessable_entity
    end
    if params[:blob].present? && params[:wipe].present?
      return render json: { errors: [ "Choose either a new blob or a wipe, not both." ] }, status: :unprocessable_entity
    end

    User.transaction do
      @user.update!(params.permit(:password, :password_wrapped_key, :recovery_wrapped_key))
      if params[:blob].present?
        blob = @user.encrypted_blob || @user.build_encrypted_blob
        blob.update!(params.require(:blob).permit(:ciphertext, :nonce))
      elsif params[:wipe].present?
        @user.encrypted_blob&.destroy!
      end
      @user.sessions.destroy_all
    end

    start_new_session_for @user
    render json: { account: @user.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
