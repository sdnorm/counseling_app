class User < ApplicationRecord
  MINIMUM_PASSWORD_LENGTH = 8

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :encrypted_blob, dependent: :destroy
  include PushNotifiable
  belongs_to :invite_code

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  encrypts :email_address, deterministic: true

  # Deterministic encryption keeps this uniqueness check queryable. Without it a
  # duplicate email hits the unique index and 500s instead of re-rendering the form.
  validates :email_address, presence: true,
    uniqueness: { message: "already has an account — sign in or reset your password below" }

  # allow_nil so updates that don't touch the password (reminder settings, the
  # reminder job's timestamp) skip this entirely.
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true

  normalizes :reminder_time, :time_zone, with: ->(value) { value.presence }

  # Zero-padded HH:MM required: SendGratitudeRemindersJob compares these lexicographically.
  validates :reminder_time, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/ }, allow_nil: true
  validate :time_zone_must_be_valid

  private

  def time_zone_must_be_valid
    return if time_zone.nil?
    errors.add(:time_zone, "is not a valid time zone") if ActiveSupport::TimeZone[time_zone].nil?
  end
end
