class InviteCode < ApplicationRecord
  belongs_to :user, optional: true
  validates :code, presence: true, uniqueness: true
  validates :email_address, presence: true
  encrypts :email_address, deterministic: true

  def self.generate(email_address)
    create!(code: SecureRandom.alphanumeric(8).upcase, email_address: email_address)
  end

  # Marks an unused code as used in a single statement so two concurrent signups
  # can't both claim it. Returns the code, or nil if it was already taken.
  def self.claim(code)
    return if code.blank?
    return unless where(code: code, used: false).update_all(used: true) == 1
    find_by(code: code)
  end
end
