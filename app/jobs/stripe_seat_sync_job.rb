class StripeSeatSyncJob < ApplicationJob
  retry_on ::Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 5

  def perform(practice_id)
    Practice.find_by(id: practice_id)&.sync_seats!
  end
end
