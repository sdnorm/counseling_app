require "test_helper"

class PracticeBillingTest < ActiveSupport::TestCase
  test "status rules" do
    p = practices(:riverbend)
    assert_not p.billing_open?
    assert_not p.billing_locked?
    assert_not p.can_invite_clients?
    %w[trialing active past_due].each { |s| p.billing_status = s; assert p.billing_open?, s }
    %w[canceled unpaid incomplete_expired paused].each { |s| p.billing_status = s; assert p.billing_locked?, s }
    p.billing_status = "canceled"
    p.complimentary = true
    assert p.billing_open?
    assert_not p.billing_locked?
  end

  test "seat pricing tiers and next seat cost" do
    assert_equal 5000, Practice.seat_unit_cents("month", 1)
    assert_equal 4000, Practice.seat_unit_cents("month", 3)
    assert_equal 32000, Practice.seat_unit_cents("year", 5)
    crossroads = practices(:crossroads) # 2 active counselors
    assert_equal 12000 - 10000, crossroads.next_seat_cost_cents("month"), "third seat drops everyone to $40"
    assert_equal 5000, practices(:riverbend).next_seat_cost_cents("month")
  end

  test "checkout session carries trial, tax, quantity, and never payment_method_types" do
    p = practices(:riverbend)
    captured = nil
    stub_stripe(customer_create: ->(**) { OpenStruct.new(id: "cus_new") },
                checkout_create: ->(params) { captured = params; OpenStruct.new(url: "https://checkout") }) do
      p.checkout_session(interval: "year", success_url: "https://x/s", cancel_url: "https://x/c")
    end
    assert_equal "cus_new", p.reload.stripe_customer_id
    assert_equal "subscription", captured[:mode]
    assert_equal 30, captured[:subscription_data][:trial_period_days]
    assert_equal({ enabled: true }, captured[:automatic_tax])
    assert_equal 1, captured[:line_items].first[:quantity]
    assert_equal Rails.application.config.x.stripe.yearly_price_id, captured[:line_items].first[:price]
    assert_nil captured[:payment_method_types]
    assert_equal p.id.to_s, captured[:client_reference_id]
  end

  test "a practice that has had a subscription gets no second trial" do
    p = practices(:lakeside)
    captured = nil
    stub_stripe(checkout_create: ->(params) { captured = params; OpenStruct.new(url: "u") }) do
      p.checkout_session(interval: "month", success_url: "s", cancel_url: "c")
    end
    assert_nil captured[:subscription_data][:trial_period_days]
  end

  test "apply_subscription mirrors status, interval, period end, and trial end" do
    p = practices(:riverbend)
    p.apply_subscription(fake_subscription(status: "trialing", interval: "year"))
    assert_equal "sub_1", p.stripe_subscription_id
    assert_equal "trialing", p.billing_status
    assert_equal "year", p.billing_interval
    assert_in_delta 30.days.from_now, p.trial_ends_at, 5.seconds
  end

  test "sync_seats! prorates increases, defers decreases, and no-ops when equal" do
    p = practices(:crossroads) # 2 seats
    p.update!(stripe_subscription_id: "sub_x", complimentary: false)
    calls = []
    stub_stripe(subscription_retrieve: ->(_id) { fake_subscription(quantity: 1) },
                item_update: ->(id, **params) { calls << [ id, params ] }) { p.sync_seats! }
    assert_equal [ [ "si_1", { quantity: 2, proration_behavior: "create_prorations" } ] ], calls

    calls = []
    stub_stripe(subscription_retrieve: ->(_id) { fake_subscription(quantity: 3) },
                item_update: ->(id, **params) { calls << [ id, params ] }) { p.sync_seats! }
    assert_equal "none", calls.first.last[:proration_behavior]

    calls = []
    stub_stripe(subscription_retrieve: ->(_id) { fake_subscription(quantity: 2) },
                item_update: ->(*) { calls << :called }) { p.sync_seats! }
    assert_empty calls
  end

  test "referral rewards: one credit per two paid referrals, idempotent, skipped without a customer" do
    referrer = practices(:lakeside)
    a = Practice.create!(name: "A", referrer: referrer, first_paid_at: 1.day.ago)
    b = Practice.create!(name: "B", referrer: referrer)
    credits = []
    stub_stripe(balance_transaction: ->(cus, **params) { credits << [ cus, params[:amount] ] }) do
      referrer.grant_pending_referral_rewards!
      assert_empty credits, "one paid referral is not enough"
      b.update!(stripe_customer_id: "cus_b")
      b.record_paid_invoice!
      assert_equal [ [ "cus_lakeside", -5000 ] ], credits
      referrer.grant_pending_referral_rewards!
      assert_equal 1, credits.size, "re-running must not double credit"
    end
    assert_equal 1, referrer.reload.referral_rewards_granted

    no_customer = practices(:riverbend)
    Practice.create!(name: "C", referrer: no_customer, first_paid_at: 1.day.ago)
    Practice.create!(name: "D", referrer: no_customer, first_paid_at: 1.day.ago)
    stub_stripe(balance_transaction: ->(*) { flunk "must not credit without a customer" }) { no_customer.grant_pending_referral_rewards! }
  end

  test "reward is 10% of the yearly total on a yearly plan" do
    p = practices(:lakeside)
    p.update!(billing_interval: "year")
    assert_equal 4000, p.reward_cents
  end
end
