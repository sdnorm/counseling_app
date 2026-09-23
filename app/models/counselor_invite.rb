class CounselorInvite < ApplicationRecord
  EXPIRY = 7.days

  has_secure_token :token
  belongs_to :practice, optional: true
  belongs_to :invited_by, class_name: "Counselor", optional: true, inverse_of: :sent_invites
  belongs_to :referred_by_practice, class_name: "Practice", optional: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :practice_name, with: ->(v) { v.presence&.strip }
  encrypts :email_address, deterministic: true

  validates :email_address, presence: true
  validates :role, inclusion: { in: Counselor::ROLES }
  validate :targets_exactly_one_practice

  before_create { self.expires_at ||= EXPIRY.from_now }

  scope :pending, -> { where(accepted_at: nil).where(expires_at: Time.current..) }

  def expired?
    expires_at <= Time.current
  end

  def accepted?
    accepted_at.present?
  end

  def usable?
    !expired? && !accepted?
  end

  def practice_display_name
    practice&.name || practice_name
  end

  # Owner invites create the practice; member invites join one. Either way
  # the counselor, the practice, and the acceptance land together or not at
  # all. Raises ActiveRecord::RecordInvalid with the failing record's errors.
  def accept!(name:, password:)
    raise ActiveRecord::RecordInvalid.new(self) unless usable?

    transaction do
      target = practice || Practice.create!(name: practice_name, trial_ends_at: 30.days.from_now, referred_by_practice_id: referred_by_practice_id)
      counselor = target.counselors.create!(email_address: email_address, name: name, password: password, role: role)
      update!(accepted_at: Time.current)
      counselor
    end
  end

  private

  def targets_exactly_one_practice
    if practice.present? == practice_name.present?
      errors.add(:base, "must name either a practice to join or a new practice to create")
    end
  end
end
