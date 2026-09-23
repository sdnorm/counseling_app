class Api::AccountKeysController < Api::BaseController
  # Update verifies the current auth hash, so throttle it like login: this
  # endpoint must not let anyone guess credentials faster than /session does.
  rate_limit to: 10, within: 3.minutes,
    by: -> { current_user&.id || request.remote_ip },
    only: :update,
    with: -> { render json: { errors: [ "Too many attempts" ] }, status: :too_many_requests }

  def show
    render json: {
      password_wrapped_key: current_user.password_wrapped_key,
      recovery_wrapped_key: current_user.recovery_wrapped_key
    }
  end

  # Change password (password + password_wrapped_key) or rotate the recovery
  # code (recovery_wrapped_key). The data key itself never changes: the
  # browser unwraps it with the old wrapping key and re-wraps under the new
  # one, so the server only ever swaps ciphertext.
  def update
    unless current_user.authenticate(params[:current_password].to_s)
      return render json: { errors: [ "Incorrect password" ] }, status: :unauthorized
    end

    changes = params.permit(:password, :password_wrapped_key, :recovery_wrapped_key).to_h.compact_blank
    if changes.empty?
      return render json: { errors: [ "Nothing to change" ] }, status: :unprocessable_entity
    end

    User.transaction do
      if current_user.update(changes)
        # A new password invalidates every other device's login, but not the
        # one that just proved it knows the current password.
        current_user.sessions.where.not(id: Current.session.id).destroy_all if changes.key?("password")
        render json: {}
      else
        render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end
    end
  end
end
