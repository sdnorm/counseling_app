#
# Everything a practice knows about money. All Stripe calls live here so the
# controllers only ask questions and the tests stub one boundary.
module PracticeBilling
  extend ActiveSupport::Concern

  OPEN_STATUSES = %w[trialing active past_due].freeze
  LOCKED_STATUSES = %w[canceled unpaid incomplete_expired paused].freeze
  TRIAL_DAYS = 30
  GROUP_SEATS = 3
  UNIT_CENTS = {
    "month" => { solo: 5000, group: 4000 },
    "year" => { solo: 40000, group: 32000 }
  }.freeze

  included do
    belongs_to :referrer, class_name: "Practice", foreign_key: :referred_by_practice_id, optional: true
    has_many :referred_practices, class_name: "Practice", foreign_key: :referred_by_practice_id, dependent: :nullify, inverse_of: :referrer
    validates :billing_interval, inclusion: { in: %w[month year] }, allow_nil: true
  end

  class_methods do
    def seat_unit_cents(interval, seats)
      UNIT_CENTS.fetch(interval)[seats >= GROUP_SEATS ? :group : :solo]
    end
  end

  def billing_open?
    complimentary? || billing_status.in?(OPEN_STATUSES)
  end

  def billing_locked?
    !complimentary? && billing_status.in?(LOCKED_STATUSES)
  end

  def can_invite_clients?
    billing_open?
  end

  def trial_available?
    stripe_subscription_id.nil?
  end

  def seat_count
    active_counselors.count
  end

  def price_id(interval)
    interval == "year" ? Rails.application.config.x.stripe.yearly_price_id : Rails.application.config.x.stripe.monthly_price_id
  end

  # What one more counselor adds: the whole practice may drop to the group
  # rate, so it is the difference between totals, not one unit.
  def next_seat_cost_cents(interval)
    seats = seat_count
    total(interval, seats + 1) - total(interval, seats)
  end

  def reward_cents
    interval = billing_interval || "month"
    interval == "year" ? (total("year", seat_count) * 0.10).round : total("month", seat_count)
  end

  def ensure_stripe_customer!
    return stripe_customer_id if stripe_customer_id.present?
    owner = counselors.active.find_by(role: "owner")
    customer = Stripe::Customer.create(email: owner&.email_address, name: name, metadata: { practice_id: id })
    update!(stripe_customer_id: customer.id)
    customer.id
  end

  def checkout_session(interval:, success_url:, cancel_url:)
    params = {
      mode: "subscription",
      customer: ensure_stripe_customer!,
      line_items: [ { price: price_id(interval), quantity: seat_count } ],
      subscription_data: { metadata: { practice_id: id } },
      automatic_tax: { enabled: true },
      billing_address_collection: "required",
      customer_update: { address: "auto", name: "auto" },
      payment_method_collection: "always",
      client_reference_id: id.to_s,
      success_url: success_url,
      cancel_url: cancel_url
    }
    params[:subscription_data][:trial_period_days] = TRIAL_DAYS if trial_available?
    Stripe::Checkout::Session.create(params)
  end

  def portal_session(return_url:)
    Stripe::BillingPortal::Session.create(customer: ensure_stripe_customer!, return_url: return_url)
  end

  # `sub` is a Stripe::Subscription (or anything shaped like one).
  def apply_subscription(sub)
    item = sub.items.data.first
    update!(
      stripe_subscription_id: sub.id,
      billing_status: sub.status,
      billing_interval: item&.price&.recurring&.interval,
      current_period_end: sub.respond_to?(:current_period_end) && sub.current_period_end ? Time.at(sub.current_period_end) : (item&.respond_to?(:current_period_end) && item.current_period_end ? Time.at(item.current_period_end) : current_period_end),
      trial_ends_at: sub.trial_end ? Time.at(sub.trial_end) : trial_ends_at
    )
  end

  # Increases bill now (prorated); decreases wait for renewal.
  def sync_seats!
    return if stripe_subscription_id.blank?
    sub = Stripe::Subscription.retrieve(stripe_subscription_id)
    item = sub.items.data.first
    return if item.quantity == seat_count
    behavior = seat_count > item.quantity ? "create_prorations" : "none"
    Stripe::SubscriptionItem.update(item.id, quantity: seat_count, proration_behavior: behavior)
  end

  def record_paid_invoice!
    update!(first_paid_at: Time.current) if first_paid_at.nil?
    grant_pending_referral_rewards!
    referrer&.grant_pending_referral_rewards!
  end

  # For every two referred practices that have paid, one credit. Counted
  # against what has already been granted so re-running is safe.
  def grant_pending_referral_rewards!
    return if stripe_customer_id.blank?
    with_lock do
      paid = referred_practices.where.not(first_paid_at: nil).count
      due = paid / 2 - referral_rewards_granted
      due.times do
        Stripe::Customer.create_balance_transaction(stripe_customer_id, amount: -reward_cents, currency: "usd", description: "Referral reward")
        increment!(:referral_rewards_granted)
      end
    end
  end

  private

  def total(interval, seats)
    self.class.seat_unit_cents(interval, seats) * seats
  end
end
