class EncryptedBlob < ApplicationRecord
  # Base64 of the whole client state. Generous — years of journalling sits well
  # under this — but bounded so one account can't grow storage without limit.
  MAX_CIPHERTEXT_BYTES = 2.megabytes

  # AES-GCM IV (12 bytes) and PBKDF2 salt (16 bytes), base64-encoded.
  MAX_NONCE_BYTES = 64
  MAX_SALT_BYTES = 64

  belongs_to :user
  validates :ciphertext, :nonce, :salt, presence: true
  validates :ciphertext, length: { maximum: MAX_CIPHERTEXT_BYTES }
  validates :nonce, length: { maximum: MAX_NONCE_BYTES }
  validates :salt, length: { maximum: MAX_SALT_BYTES }
end
