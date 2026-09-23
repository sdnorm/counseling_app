class Session < ApplicationRecord
  # The signed cookie is permanent (20 years), so without this a session would
  # never expire. Absolute age only — an idle timeout would mean touching the
  # row on every request. The data itself is sealed by the client-held data
  # key regardless of session length.
  MAX_AGE = 30.days

  belongs_to :user

  scope :active, -> { where(created_at: MAX_AGE.ago..) }
end
