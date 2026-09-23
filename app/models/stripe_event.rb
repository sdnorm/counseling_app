# Every webhook event is recorded before it is acted on, so Stripe's retries
# and duplicate deliveries are harmless.
class StripeEvent < ApplicationRecord
  validates :event_id, :event_type, presence: true

  def self.record!(event_id, event_type)
    create!(event_id: event_id, event_type: event_type)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
