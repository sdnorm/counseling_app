# Billing: Subscriptions, Seats, Trials, Referrals

**Date:** 2026-09-23
**Status:** Approved
**Part of:** `2026-09-16-pivot-roadmap.md`, project 4
**Depends on:** `2026-09-22-multi-tenancy-design.md`

## Decisions

- Prices from the roadmap: $50/seat/month or $400/seat/year for 1–2 seats;
  $40/seat/month or $320/seat/year at 3+ seats. Client limit stays seats × 30.
- Seats follow active counselors automatically.
- 30-day trial, card required, collected in Stripe Checkout. Dashboard first:
  an owner can set up the practice before starting the trial, but client
  invites are refused until a subscription exists.
- Clients are never affected by billing. Counselors of a canceled or unpaid
  practice see only the billing page.
- `complimentary` practices (Crossroads, the platform's own) skip billing.
- Stripe Tax on. Customer Portal for card changes, plan switches, cancel.
- Referrals: for every two referred practices that pay a first invoice, the
  referrer gets a Stripe customer-balance credit of one month at their
  monthly total, or 10% of their yearly total.

## Stripe objects

One product, two prices, both `billing_scheme: tiered`, `tiers_mode:
volume`, `tax_behavior: exclusive`: monthly tiers `[up_to 2 → 5000,
inf → 4000]`, yearly tiers `[up_to 2 → 40000, inf → 32000]`. A rake task
`stripe:setup` creates them and prints the price IDs. Credentials:
`stripe.secret_key` (a restricted key with Checkout, Customers,
Subscriptions, Billing Portal, Balance Transactions, and Prices read),
`stripe.webhook_secret`, `stripe.monthly_price_id`, `stripe.yearly_price_id`.
API version pinned to `2026-05-27.dahlia`.

## Data

`practices` gains `stripe_customer_id`, `stripe_subscription_id`,
`billing_status` (string, default `"none"`, mirrors Stripe's subscription
status), `billing_interval` (`month`/`year`, nullable), `current_period_end`,
`complimentary` (boolean, default false), `referred_by_practice_id`,
`first_paid_at`, `referral_rewards_granted` (integer, default 0).
`stripe_events`: `event_id` unique, `event_type`, timestamps.

## Model behavior (`PracticeBilling` concern on `Practice`)

- `billing_open?`: complimentary, or status in trialing/active/past_due.
- `billing_locked?`: not complimentary and status in
  canceled/unpaid/incomplete_expired/paused.
- `can_invite_clients?`: `billing_open?`.
- `seat_count`: active counselors. `seat_unit_cents(interval, seats)` per the
  tiers. `next_seat_cost_cents(interval)`: what one more seat adds.
- `ensure_stripe_customer!`: creates the customer once (owner email,
  practice name, metadata practice_id).
- `checkout_session(interval:, success_url:, cancel_url:)`: subscription
  mode, the chosen price, quantity `seat_count`, `automatic_tax` on,
  `billing_address_collection: required`, `customer_update: { address:
  auto, name: auto }`, `payment_method_collection: always`,
  `client_reference_id`, `subscription_data.metadata.practice_id`, and
  `trial_period_days: 30` only when the practice has never had a
  subscription. Never `payment_method_types`.
- `portal_session(return_url:)`.
- `apply_subscription(sub)`: copies id, status, interval, period end, and
  `trial_ends_at` from a Stripe subscription object.
- `sync_seats!`: sets the subscription item quantity to `seat_count`;
  `proration_behavior: create_prorations` on increase, `none` on decrease.
  No-op without a subscription or when equal.
- `record_paid_invoice!`: sets `first_paid_at` if nil; then
  `grant_pending_referral_rewards!` on self and on the referrer.
- `grant_pending_referral_rewards!`: `paid = referred_practices.where.not(
  first_paid_at: nil).count`; `due = paid / 2 - referral_rewards_granted`;
  for each, create a negative customer balance transaction of
  `reward_cents` and increment the counter, inside a lock. Skipped without a
  Stripe customer. `reward_cents` = monthly total, or 10% of yearly total.

## Web

- `POST /stripe/webhooks`: no auth, no CSRF, signature verified. Inserts the
  event ID first (unique index; duplicate → 200 and stop). Handles
  `checkout.session.completed` (practice from `client_reference_id`; fetch
  the subscription; `apply_subscription`), `customer.subscription.updated`
  and `.deleted` (practice from metadata practice_id or subscription id;
  `apply_subscription`), `invoice.paid` (practice from customer id;
  `apply_subscription` if the invoice has one; `record_paid_invoice!`),
  `invoice.payment_failed` (status `past_due`). Unknown events → 200.
- `GET /counselor/billing` (owner): the page described in the design
  message. `POST /counselor/billing/checkout` with `interval` → redirect to
  Checkout. `POST /counselor/billing/portal` → redirect to the portal.
- `Dashboard::BaseController`: `before_action :require_billing_open`, which
  redirects locked practices to the billing page for every action except
  billing and session. Members of a locked practice see the billing page
  with "Ask your practice owner to update billing."
- `Dashboard::InvitesController#create`: refuses when
  `!practice.can_invite_clients?` with "Start your free trial to invite
  clients." (owner) or "Your practice owner needs to start the subscription
  before clients can be invited." (member).
- Seat sync: `StripeSeatSyncJob.perform_later(practice_id)` after a member
  accepts an invite and after a member is removed.
- Members page shows "Adding a counselor adds $X/month" from
  `next_seat_cost_cents`.
- Platform: practices list shows billing status and interval; the practice
  page gets the `complimentary` checkbox; the practice invite form gets
  "Referred by" (a practice select) stored on the created practice at
  acceptance time (the invite carries `referred_by_practice_id`).

## Testing

Stripe is stubbed at the client boundary (`Stripe::Checkout::Session.create`,
`Stripe::Customer.create`, `Stripe::Subscription.retrieve`,
`Stripe::SubscriptionItem.update`, `Stripe::Customer.create_balance_transaction`,
`Stripe::BillingPortal::Session.create`). Webhook tests sign real JSON
payloads with the test signing secret. Coverage: checkout parameters
including the no-trial-on-restart rule and the absence of
`payment_method_types`; every status transition; invite refusal per
status; lockout redirect; seat sync direction and no-op; referral credit
arithmetic, idempotency, and skip-without-customer; complimentary bypass;
webhook signature rejection and duplicate event short-circuit.

## Out of scope

Self-serve public signup, refunds, annual seat true-ups, per-practice
currencies, emailing invoices ourselves.
