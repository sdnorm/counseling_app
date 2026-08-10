class Api::SyncController < Api::BaseController
  # Keyed by user rather than IP: clients behind one NAT must not throttle each
  # other. Generous enough for save-on-every-entry usage.
  rate_limit to: 60, within: 1.minute,
    by: -> { current_user&.id || request.remote_ip },
    only: :update,
    with: -> { render json: { errors: [ "Too many requests" ] }, status: :too_many_requests }

  # Reset verifies the account password, so throttle it like login — this
  # endpoint must not let anyone guess passwords faster than /session does.
  rate_limit to: 10, within: 3.minutes,
    by: -> { current_user&.id || request.remote_ip },
    only: :reset,
    with: -> { render json: { errors: [ "Too many attempts" ] }, status: :too_many_requests }

  def show
    blob = current_user.encrypted_blob
    if blob
      render json: {
        account: current_user.id,
        ciphertext: blob.ciphertext,
        nonce: blob.nonce,
        salt: blob.salt,
        updated_at: blob.updated_at
      }
    else
      # Still name the account: the client stamps its local database with this
      # so it can tell whose data the device is holding.
      render json: { account: current_user.id }, status: :not_found
    end
  end

  def update
    save_blob
  end

  # Forgot-passphrase reset, gated by the account password. With a blob the
  # client is re-keying (it re-encrypted its local state under a new
  # passphrase); without one there is nothing local to re-key, so the backup
  # is deleted and the user starts over. Either way the server only ever
  # touches ciphertext.
  def reset
    unless current_user.authenticate(params[:password].to_s)
      return render json: { errors: [ "Incorrect password" ] }, status: :unauthorized
    end

    if params.key?(:blob)
      save_blob
    else
      current_user.encrypted_blob&.destroy!
      render json: { success: true }
    end
  end

  private

  def save_blob
    blob = current_user.encrypted_blob || current_user.build_encrypted_blob
    if blob.update(blob_params)
      render json: { success: true }
    else
      render json: { errors: blob.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def blob_params
    params.require(:blob).permit(:ciphertext, :nonce, :salt)
  end
end
