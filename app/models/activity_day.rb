#
# "This client used the app on this day." Nothing else is recorded: no
# counts, no screens, no content. One row per client per local day.
class ActivityDay < ApplicationRecord
  belongs_to :user
  validates :day, presence: true, uniqueness: { scope: :user_id }
end
