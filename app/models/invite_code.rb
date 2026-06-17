class InviteCode < ApplicationRecord
  belongs_to :user, optional: true
  validates :code, presence: true, uniqueness: true
  validates :email_address, presence: true
  encrypts :email_address, deterministic: true

  def self.generate(email_address)
    create!(code: SecureRandom.alphanumeric(8).upcase, email_address: email_address)
  end
end
