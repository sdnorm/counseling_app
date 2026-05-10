class Api::SyncController < Api::BaseController
  def show
    blob = current_user.encrypted_blob
    if blob
      render json: {
        ciphertext: blob.ciphertext,
        nonce: blob.nonce,
        salt: blob.salt,
        updated_at: blob.updated_at
      }
    else
      render json: {}, status: :not_found
    end
  end

  def update
    blob = current_user.encrypted_blob || current_user.build_encrypted_blob
    if blob.update(blob_params)
      render json: { success: true }
    else
      render json: { errors: blob.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def blob_params
    params.require(:blob).permit(:ciphertext, :nonce, :salt)
  end
end
