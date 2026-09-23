require "test_helper"

class StripeSeatSyncJobTest < ActiveJob::TestCase
  test "syncs the practice's seats" do
    calls = []
    stub_stripe(subscription_retrieve: ->(_id) { fake_subscription(quantity: 5) },
                item_update: ->(id, **params) { calls << params[:quantity] }) do
      StripeSeatSyncJob.perform_now(practices(:lakeside).id)
    end
    assert_equal [ 1 ], calls
  end

  test "a missing practice is a no-op" do
    assert_nothing_raised { StripeSeatSyncJob.perform_now(0) }
  end
end
