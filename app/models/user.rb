class User < ApplicationRecord
  # The client sends a 32-byte HKDF output, base64url without padding. A raw
  # password can only arrive if the browser's JavaScript never ran.
  AUTH_HASH_FORMAT = /\A[A-Za-z0-9_-]{43}\z/
  WRAPPED_KEY_MAX_BYTES = 256

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :encrypted_blob, dependent: :destroy
  include PushNotifiable
  belongs_to :invite_code
  belongs_to :counselor
  has_one :practice, through: :counselor

  # "Active" for billing means used the app recently, or just joined. The
  # archive flag is deliberately absent: it is a list-tidying tool.
  scope :active_recently, -> {
    since = Practice::ACTIVE_WINDOW.ago
    where(last_synced_at: since..).or(where(created_at: since..))
  }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :unarchived, -> { where(archived_at: nil) }

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  encrypts :email_address, deterministic: true

  # Deterministic encryption keeps this uniqueness check queryable. Without it a
  # duplicate email hits the unique index and 500s instead of re-rendering the form.
  validates :email_address, presence: true,
    uniqueness: { message: "already has an account — sign in or reset your password below" }

  # allow_nil so updates that don't touch the password (reminder settings, the
  # reminder job's timestamp) skip this entirely.
  validates :password, format: { with: AUTH_HASH_FORMAT, message: "requires JavaScript to be enabled" }, allow_nil: true

  validates :password_wrapped_key, :recovery_wrapped_key,
    presence: true, length: { maximum: WRAPPED_KEY_MAX_BYTES }

  normalizes :reminder_time, :time_zone, with: ->(value) { value.presence }

  # Zero-padded HH:MM required: SendGratitudeRemindersJob compares these lexicographically.
  validates :reminder_time, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/ }, allow_nil: true
  validate :time_zone_must_be_valid

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  # Called on every successful sync. One write per ten minutes is plenty for
  # a 30-day window and keeps save-on-every-entry usage cheap.
  def touch_last_synced!
    return if last_synced_at && last_synced_at > 10.minutes.ago
    update_column(:last_synced_at, Time.current)
  end

  private

  def time_zone_must_be_valid
    return if time_zone.nil?
    errors.add(:time_zone, "is not a valid time zone") if ActiveSupport::TimeZone[time_zone].nil?
  end
end
