class InviteCode < ApplicationRecord
  belongs_to :user, optional: true
  validates :code, presence: true, uniqueness: true

  def self.generate
    create!(code: SecureRandom.alphanumeric(8).upcase)
  end
end
