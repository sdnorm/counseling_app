class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  layout "session", only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { too_many_attempts }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      respond_to do |format|
        format.html { redirect_to after_authentication_url }
        # The browser unwraps this with the key it derived from the password;
        # the server can't open it. The recovery-wrapped copy stays out of
        # login: it only ever leaves on the token-gated reset page.
        format.json { render json: { account: user.id, password_wrapped_key: user.password_wrapped_key } }
      end
    else
      respond_to do |format|
        format.html { redirect_to new_session_path, alert: "Try another email address or password." }
        format.json { render json: { errors: [ "Try another email address or password." ] }, status: :unauthorized }
      end
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private

  def too_many_attempts
    respond_to do |format|
      format.html { redirect_to new_session_path, alert: "Try again later." }
      format.json { render json: { errors: [ "Try again later." ] }, status: :too_many_requests }
    end
  end
end
