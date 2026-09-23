class InviteCode < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :counselor
  validates :code, presence: true, uniqueness: true
  normalizes :email_address, with: ->(e) { e.presence&.strip&.downcase }
  encrypts :email_address, deterministic: true

  # Email is optional: invites are shared as links first. Keep it when the
  # counselor gives it so the invite email and the list can show it.
  def self.generate(email_address, counselor:)
    create!(code: SecureRandom.alphanumeric(8).upcase, email_address: email_address, counselor: counselor)
  end

  # Marks an unused code as used in a single statement so two concurrent signups
  # can't both claim it. Returns the code, or nil if it was already taken.
  def self.claim(code)
    return if code.blank?
    return unless where(code: code, used: false).update_all(used: true) == 1
    find_by(code: code)
  end
end
