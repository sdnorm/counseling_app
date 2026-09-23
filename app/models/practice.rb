class Practice < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  COLOR_FORMAT = /\A#[0-9a-fA-F]{6}\z/
  ACTIVE_WINDOW = 30.days
  IMAGE_TYPES = %w[image/png image/jpeg].freeze
  IMAGE_MAX_BYTES = 2.megabytes
  ICON_MIN_PX = 512

  has_many :counselors, dependent: :restrict_with_error
  has_many :clients, through: :counselors
  has_many :resource_links, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :practice
  has_many :counselor_invites, dependent: :destroy
  has_one_attached :logo
  has_one_attached :icon

  # A blank form row still carries position's column default, so :all_blank
  # would keep it and then fail on the empty title and URL.
  accepts_nested_attributes_for :resource_links, allow_destroy: true,
    reject_if: ->(attrs) { attrs["title"].blank? && attrs["url"].blank? }

  normalizes :slug, with: ->(value) { value.to_s.strip.downcase }
  normalizes :custom_domain, with: ->(value) { value.presence&.strip&.downcase }
  normalizes :primary_color, :accent_color, with: ->(value) { value.presence&.strip&.downcase }
  normalizes :website_url, :booking_url, :phone, :appointment_email, with: ->(value) { value.presence&.strip }

  before_validation :derive_slug, on: :create

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT, message: "may only contain lowercase letters, numbers, and dashes" }
  validates :custom_domain, uniqueness: true, allow_nil: true
  validates :primary_color, :accent_color, format: { with: COLOR_FORMAT, message: "must look like #1a2b3c" }, allow_nil: true
  validates :client_limit_per_counselor, numericality: { only_integer: true, greater_than: 0 }
  validate :icon_is_a_square_image
  validate :logo_is_an_image

  # Custom domain first, then <slug>.<product host>. Anything else is nil:
  # the bare product host and unknown hosts wear the generic brand.
  def self.for_host(host)
    host = host.to_s.downcase
    if (practice = find_by(custom_domain: host))
      return practice
    end
    suffix = ".#{Rails.application.config.x.product_host}"
    return nil unless host.end_with?(suffix)
    slug = host.delete_suffix(suffix)
    find_by(slug: slug) unless slug.include?(".")
  end

  def host
    custom_domain || "#{slug}.#{Rails.application.config.x.product_host}"
  end

  def active_counselors
    counselors.active
  end

  def client_limit
    client_limit_per_counselor * active_counselors.count
  end

  # Usage-based on purpose: archiving never changes this, so there is nothing
  # to game. A client who stops syncing drops out of the count by themselves.
  def active_client_count
    clients.active_recently.count
  end

  def at_client_limit?
    active_client_count >= client_limit
  end

  private

  def derive_slug
    return if slug.present? || name.blank?
    base = name.parameterize.presence || "practice"
    candidate = base
    n = 2
    while Practice.exists?(slug: candidate)
      candidate = "#{base}-#{n}"
      n += 1
    end
    self.slug = candidate
  end

  def logo_is_an_image
    validate_image(:logo, square: false)
  end

  def icon_is_a_square_image
    validate_image(:icon, square: true)
  end

  # Only checks a newly assigned file; existing attachments were checked when
  # they were attached. Dimensions come from vips on the upload itself,
  # because Active Storage analysis runs after commit.
  def validate_image(attribute, square:)
    change = attachment_changes[attribute.to_s]
    return unless change.is_a?(ActiveStorage::Attached::Changes::CreateOne)

    blob = change.blob
    unless blob.content_type.in?(IMAGE_TYPES)
      errors.add(attribute, "must be a PNG or JPEG")
      return
    end
    if blob.byte_size > IMAGE_MAX_BYTES
      errors.add(attribute, "must be under #{IMAGE_MAX_BYTES / 1.megabyte} MB")
      return
    end
    return unless square

    width, height = image_dimensions(change.attachable)
    errors.add(attribute, "could not be read") and return if width.nil?
    errors.add(attribute, "must be square") if width != height
    errors.add(attribute, "must be at least #{ICON_MIN_PX} pixels") if width < ICON_MIN_PX
  end

  def image_dimensions(attachable)
    io = attachable.respond_to?(:tempfile) ? attachable.tempfile : attachable[:io]
    io.rewind
    image = Vips::Image.new_from_buffer(io.read, "")
    io.rewind
    [ image.width, image.height ]
  rescue Vips::Error, NoMethodError
    nil
  end
end
