class ResourceLink < ApplicationRecord
  belongs_to :practice, inverse_of: :resource_links

  normalizes :title, :url, :description, with: ->(value) { value.presence&.strip }

  validates :title, presence: true
  validates :url, presence: true, format: { with: %r{\Ahttps?://}i, message: "must start with http:// or https://" }
end
