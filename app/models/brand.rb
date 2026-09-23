#
# What a page wears. Wraps a practice or nil and applies the generic product
# fallback per field, so views never ask "is there a practice?" themselves.
class Brand
  DEFAULT_PRIMARY = "#32b1c3"
  DEFAULT_ACCENT = "#f06623"
  ICON_SIZES = [ 192, 512, 180 ].freeze

  attr_reader :practice

  def initialize(practice)
    @practice = practice
  end

  def self.generic
    new(nil)
  end

  def generic?
    practice.nil?
  end

  def product_name
    Rails.application.config.x.product_name
  end

  def name
    practice&.name.presence || product_name
  end

  def host
    practice&.host || Rails.application.config.x.product_host
  end

  def title(page = nil)
    [ page, name ].compact.join(" · ")
  end

  def primary_color
    practice&.primary_color.presence || DEFAULT_PRIMARY
  end

  def accent_color
    practice&.accent_color.presence || DEFAULT_ACCENT
  end

  def custom_colors?
    practice.present? && (practice.primary_color.present? || practice.accent_color.present?)
  end

  def logo
    practice.logo if practice&.logo&.attached?
  end

  def icon_variant(size)
    raise ArgumentError, "unsupported icon size #{size}" unless size.in?(ICON_SIZES)
    return unless practice&.icon&.attached?
    practice.icon.variant(resize_to_fill: [ size, size ], format: :png)
  end

  def resources
    return [] unless practice
    practice.resource_links.map { |link| { title: link.title, url: link.url, description: link.description } }
  end

  def schedule
    return {} unless practice
    { booking_url: practice.booking_url, phone: practice.phone, appointment_email: practice.appointment_email }.compact_blank
  end

  def practice_content_json
    { resources: resources, schedule: schedule }.to_json
  end
end
