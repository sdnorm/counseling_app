class ResourceLink < ApplicationRecord
  belongs_to :practice, inverse_of: :resource_links

  normalizes :title, :url, :description, with: ->(value) { value.presence&.strip }

  validates :title, presence: true
  validates :url, presence: true, format: { with: %r{\Ahttps?://\S+\z}i, message: "must be a full http:// or https:// address" }
end
