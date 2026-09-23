class Counselor < ApplicationRecord
  MINIMUM_PASSWORD_LENGTH = 12
  ROLES = %w[owner member].freeze

  belongs_to :practice
  has_many :sessions, class_name: "CounselorSession", dependent: :destroy
  has_many :clients, class_name: "User", dependent: :restrict_with_error
  has_many :invite_codes, dependent: :destroy
  has_many :sent_invites, class_name: "CounselorInvite", foreign_key: :invited_by_id, dependent: :nullify, inverse_of: :invited_by

  # Counselors hold no encrypted data, so an ordinary password is fine here.
  has_secure_password

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  encrypts :email_address, deterministic: true

  validates :email_address, presence: true, uniqueness: true
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true

  scope :active, -> { where(removed_at: nil) }

  def owner?
    role == "owner"
  end

  def removed?
    removed_at.present?
  end

  # Keeps the record (clients still point at it) but ends every session and
  # blocks login.
  def remove!
    transaction do
      update!(removed_at: Time.current)
      sessions.destroy_all
    end
  end
end
