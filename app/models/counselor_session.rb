class CounselorSession < ApplicationRecord
  MAX_AGE = 30.days

  belongs_to :counselor

  scope :active, -> { where(created_at: MAX_AGE.ago..) }
end
