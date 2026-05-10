class EncryptedBlob < ApplicationRecord
  belongs_to :user
  validates :ciphertext, :nonce, :salt, presence: true
end
