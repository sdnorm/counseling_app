class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :encrypted_blob, dependent: :destroy
  include PushNotifiable
  belongs_to :invite_code

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  encrypts :email_address, deterministic: true

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
