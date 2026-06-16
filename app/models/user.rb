class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :encrypted_blob, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  belongs_to :invite_code

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  encrypts :email_address, deterministic: true
end
