# Pivot Roadmap: From One Counselor's App to a Product Counselors Subscribe To

**Date:** 2026-09-16
**Status:** Approved direction. Each numbered project below gets its own spec
and plan; this document records the decisions they share.

## What changes

Today the app serves one counselor: HTTP Basic on an invites page, clients
tied to invite codes, one deployment. The product becomes something any
counselor or group practice can sign up for, pay for, and offer to their
clients. The client-facing tools (journal, check-ins, gratitude, coping
skills, agenda, resources) stay as they are.

## What does not change

**Zero-knowledge encryption is the spine of the product.** The server stores
only ciphertext. No counselor, operator, or developer can read a client's
entries. Every project below is designed inside that constraint, and it is
the headline on the landing page.

## Decisions

### Login: one secret, client-derived

Clients get one password. The browser derives both an auth hash (sent to the
server) and a key-wrapping key (never sent) from it. A random data key
encrypts the journal and is stored on the server only in wrapped form. A
recovery code, shown once at signup, wraps a second copy. Details in
`2026-09-16-one-secret-login-design.md`.

Once logged in, a device stays unlocked until logout. Face ID re-lock comes
with the native app.

**No migration of existing accounts.** The launch clears client accounts and
invite codes; the current counselor re-invites clients.

### Engagement visibility without content

Counselors can see that a client is using the app, never what they wrote.
The server records metadata that arrives with each sync: last sync time and
a count of saves per day. Which tools a client opened is recorded only if the
client opts in from settings. The dashboard shows streaks and "checked in 4
of the last 7 days" style summaries per client.

### Pricing

| Plan | Price | Clients |
|---|---|---|
| Solo monthly | $50 / month | 30 active |
| Solo yearly | $400 / year ("save $200") | 30 active |
| Group, per counselor seat | $40 / seat / month, 3 seat minimum; yearly at the same ratio ($320 / seat / year) | 30 active per seat, pooled across the practice |

- 30-day free trial, card required, no free tier.
- "Active client" means an accepted invite the counselor has not archived.
  Usage never counts against the cap.
- Framing for the landing page: less than half of one session fee per month.

### Referrals

Each counselor has a referral code. When two counselors who signed up with
that code each complete a paid month or year (first invoice after trial,
paid), the referrer earns a reward: one free month on a monthly plan, or 10%
off the next yearly renewal. Rewards are applied as a credit balance in
Stripe. Trials that cancel before paying never count.

### Native app: plain Hotwire Native, not Ruby Native

Ruby Native has no biometric support and no way to add native code. Plain
Hotwire Native lets us ship a Face ID bridge component: after login the web
side hands the data key to native, which stores it in the Keychain behind
biometrics and returns it on the next open. iOS first, Android second. Native
push (APNs and FCM) replaces web push in the native shells; the PWA keeps
web push.

The native shell wraps whatever the web app is, so it comes after the web
app has changed shape. Every tool screen becomes a real route so native tabs
can point at URLs.

### Brand and domain

The current domain names one counselor. The product needs its own name and
domain before the landing page ships. Undecided; owned by the user.

## Sequence

1. **One-secret login** (spec written). Fixes the confusion users report now
   and is independent of everything else.
2. **Multi-tenancy.** Counselor accounts with real sign-in, a Practice model
   for groups, per-counselor invites, client archiving, the current
   HTTP Basic admin removed. Existing counselor becomes the first practice.
3. **Counselor dashboard and engagement metadata.** The sync endpoint records
   metadata; the dashboard lists clients with activity summaries and a way
   to invite and archive.
4. **Billing, limits, referrals.** Stripe Checkout and Customer Portal,
   trial, plan caps enforced at invite time, referral codes and credits.
5. **Landing page and brand.** Marketing site on the new domain, counselor
   signup entry point, pricing page.
6. **Hotwire Native.** Route-per-screen refactor, iOS shell, Face ID bridge,
   native push, then Android.

## Open questions

- Product name and domain (before project 5).
- Whether group practices need an owner/member role split or every counselor
  in a practice is equal (decide in project 2).
- HIPAA posture statement for the landing page: the server never holds
  readable client content, but client email addresses and their link to a
  counselor are identifiable. Decide how to word this and whether to offer a
  BAA (before project 5).
