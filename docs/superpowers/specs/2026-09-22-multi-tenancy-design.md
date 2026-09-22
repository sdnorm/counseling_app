# Multi-Tenancy: Practices, Counselors, and White-Label Branding

**Date:** 2026-09-22
**Status:** Approved
**Part of:** `2026-09-16-pivot-roadmap.md`, project 2
**Depends on:** `2026-09-16-one-secret-login-design.md` (PR #47)

## Problem

The app serves one counselor. The counselor's identity is an HTTP Basic
password on an invites page, their branding and contact details are
hardcoded in layouts and JavaScript, and clients have no link to a
counselor at all. To sell the app to other counselors, each practice needs
its own account, its own clients, and its own look, and the original
counselor must keep exactly what they have today on their own domain.

## Decisions already made (roadmap)

- White-label per practice with a generic product brand as the fallback.
  Every brand and profile field is optional and set by the counselor.
- Group practices are an owner plus members. Each counselor sees only their
  own clients; the owner additionally manages branding, members, and later
  billing.
- Client invites are a shareable link and code first, email optional.
- Practice creation is invite-only for the pilot, from a platform admin page.
- The billable count is usage-based: clients who synced or were invited in
  the last 30 days. Archiving is cosmetic and never affects the client.
- Crossroads keeps `app.crossroadcounselor.com` and its current branding as
  the first practice.

## Design

### 1. Data model

**practices**

| Column | Notes |
|---|---|
| `name` | required |
| `slug` | required, unique, `[a-z0-9-]`, derived from the name at creation, editable by the owner; hosts the practice at `<slug>.<product host>` |
| `custom_domain` | optional, unique, lowercase host; settable only by a platform admin |
| `trial_ends_at` | set to 30 days after creation; not enforced until billing |
| `primary_color`, `accent_color` | optional `#rrggbb`; map to the `--blue` and `--orange` CSS variables |
| `website_url`, `booking_url`, `phone`, `appointment_email` | optional profile content |
| `client_limit_per_counselor` | integer, default 30; billing replaces this with plan seats later |

Attachments: `logo` (shown in the wordmark) and `icon` (square PNG, at
least 512 px; variants at 192 and 512 for the manifest, 180 for
apple-touch-icon). Active Storage tables are installed by this project.

**Storage on Wasabi.** Production and development use an S3-compatible
`wasabi` service in `config/storage.yml` (`service: S3`, `endpoint:
https://s3.<region>.wasabisys.com`, `region`, `bucket`, keys from
`Rails.application.credentials.wasabi`), which needs the `aws-sdk-s3` gem.
Test keeps the Disk service. The bucket stays private. Because Wasabi
signed URLs expire and a manifest needs stable icon URLs, Active Storage
runs in proxy mode (`config.active_storage.resolve_model_to_route =
:rails_storage_proxy`): icon and logo URLs are same-origin
`/rails/active_storage/...` paths served through the app with long public
cache headers, which also keeps the CSP `img_src :self` rule unchanged.
Adding the Wasabi keys to credentials is the user's step.

**resource_links**: `practice_id`, `title`, `url`, `description`,
`position`. Rendered on the client Resources screen in position order.

**counselors**: `practice_id`, `email_address` (encrypted deterministic,
unique), `password_digest`, `name`, `role` (`owner` or `member`, string),
`platform_admin` (boolean, default false), `removed_at` (nullable).
Password minimum 12 characters, ordinary `has_secure_password`: counselors
hold no encrypted data, so the server may see their password.

**counselor_sessions**: mirrors `sessions` (`counselor_id`, `ip_address`,
`user_agent`), same 30-day absolute age. Cookie name `counselor_session_id`,
signed, httponly, permanent. Separate from the client cookie so a counselor
who is also a client on the same browser never crosses over.

**counselor_invites**: `token` (unique, random), `email_address`, `role`,
`practice_id` (nullable), `practice_name` (nullable), `invited_by_id`
(counselor, nullable for platform invites), `accepted_at`, `expires_at`
(7 days). Exactly one of `practice_id` or `practice_name` is present: a
practice to join as a member, or a practice to create as its owner.

**users** (clients) gain `counselor_id` (required), `archived_at`
(nullable), `last_synced_at` (nullable). **invite_codes** gain
`counselor_id` (required). Existing associations stay.

**Current** gains `practice` (the host's practice, may be nil),
`counselor_session`, and `counselor` delegated from it.

### 2. Tenancy: resolving the practice from the host

`ApplicationController` runs `set_current_practice` before every action:

1. If `request.host` equals a practice's `custom_domain`, that practice.
2. Else if the host is `<slug>.<product host>`, the practice with that slug.
3. Else nil: the generic brand. The bare product host and any unknown host
   resolve here.

Product host and generic name come from `Rails.application.config.x.product_host`
and `config.x.product_name`, read from `PRODUCT_HOST` and `PRODUCT_NAME`
with development defaults (`localhost` and "Counseling App"). In
development, `lvh.me` resolves subdomains without DNS.

Production `config.hosts` becomes: the product host, a regexp for its
subdomains, and one object whose `===` answers true when a practice has
that custom domain, cached for a minute. Nothing else about host
authorization changes.

**Which practice a page wears.** Before login, `Current.practice` (the
host's). After a client logs in, their counselor's practice, via a
`brand_practice` helper that prefers `current_user&.counselor&.practice`.
This is what lets the single native app, which only ever talks to the
product host, show a Crossroads client the Crossroads brand after sign-in.
Client login is not restricted by host. Invite links always use the
practice's own host, so web clients land on the branded domain naturally.

### 3. Brand delivery

A `Brand` table-less model (no service objects) wraps a practice or nil and
answers `name`, `logo`, `icon`, `primary_color`, `accent_color`, `title`,
and `host`, applying the generic fallback per field. Views only ever talk to
`Brand`.

- Layouts (`application`, `session`, and the new `counselor`) render the
  brand's name or logo in the wordmark, the title tag, `<meta
  name="theme-color">` from the primary color, an inline `<style
  nonce>` block overriding `--blue` and `--orange` when set, and an
  `apple-touch-icon` link pointing at the icon variant or the generic file.
- `/manifest.json` moves from `public/` to `ManifestsController#show`,
  which renders name, short name, colors, and icon URLs for the host's
  practice or the generic brand. Cache-Control public, 5 minutes.
- Generic assets: the current files in `public/` are Crossroads' and move
  into the Crossroads seed. New generic icons and a wordmark live under
  `app/assets/images/generic/`; until the product name exists they carry a
  placeholder mark, which is a one-file swap later.
- The client Resources screen renders the practice's resource links, or a
  single generic "About this app" link when there are none. The Schedule
  screen renders the booking, phone, and email buttons only for the fields
  that are set, and when none are set it shows "Ask your counselor how to
  book a session". These two screens read a small JSON blob the layout
  embeds for the client's practice; the Stimulus controllers stop hardcoding
  content.
- `InvitesMailer` and `PasswordsMailer` send from the product domain with
  the practice name as the display name and use the practice host for links.
  The `mailgun.domain` and from-address settings move to the product domain.
- The CSP `connect_src` entry for the Crossroads website is removed; links
  open in new tabs and need no connect permission.

### 4. Counselor authentication and invites

Routes live under `namespace :counselor`. A `CounselorAuthentication`
concern mirrors the client one: `require_counselor`, `resume_counselor_session`,
`start_new_counselor_session_for`, `terminate_counselor_session`,
`allow_unauthenticated_counselor_access`. Rate limits match client login.

- `GET/POST /counselor/session`: email and password form, HTML only.
  Removed counselors (`removed_at` set) cannot log in.
- `/counselor/passwords`: forgot and reset by emailed token, same shape as
  the client flow but plain passwords.
- `GET /counselor/invites/:token` shows the setup form (name, password).
  `POST` accepts it: for a member invite, creates the counselor in that
  practice; for an owner invite, creates the practice from `practice_name`
  with a derived unique slug and `trial_ends_at`, then the owner. Marks the
  invite accepted, starts a counselor session, redirects to the dashboard on
  the practice's host. Expired or accepted tokens render a clear message.
- Owner-only: `resources :members` (index, create sends a member invite,
  destroy sets `removed_at` and destroys that counselor's sessions), and
  `resource :practice` (edit and update brand, profile, resource links, and
  slug).

Slug uniqueness and format are validated; changing the slug changes the
practice's web address, and the edit form says so.

### 5. Counselor dashboard

Server-rendered Turbo pages under `/counselor`, layout `counselor`, styled
with the existing palette and brand variables. Small Stimulus sprinkles
only: copy-to-clipboard on invite links (existing controller) and a live
preview of name, colors, and logo on the practice settings page.

- **Clients** (`/counselor`, the dashboard root): the counselor's own
  clients, active first, with email, joined date, last active ("today",
  "3 days ago", "never"), and archive or reactivate. Archived clients sit in
  a collapsed section. The header shows "N of M active this month" for the
  practice, pooled.
- **Invites** (`/counselor/invites`): list of the counselor's codes with
  status (pending, used, by whom). "New invite" creates a code and shows the
  link `https://<practice host>/users/new?code=XXXX`, the bare code, a copy
  button, and an optional email field with "Send". Creating an invite when
  the practice is at its limit renders the limit message instead of a code.
- **Practice** (owner): name, slug, colors with preview, logo and icon
  upload with size validation (PNG or JPEG, icon square, 512 px minimum,
  2 MB max), website, booking URL, phone, appointment email, and resource
  links as nested fields with add and remove.
- **Members** (owner): list with role and status, invite by email, remove.
- **Account**: change name and password, log out.

Every counselor page sets the same no-store cache headers the old admin page
used.

### 6. Client invites, signup, and the active count

- `InviteCode.generate` takes the counselor; `UsersController#create`
  assigns `user.counselor` from the claimed code. The code claim, user
  creation, and counselor assignment stay in the one existing transaction.
- `Practice#active_client_count`: users joined through counselors of the
  practice where `last_synced_at > 30.days.ago OR created_at > 30.days.ago`.
  `Practice#client_limit`: `client_limit_per_counselor` times counselors
  with no `removed_at`. `Practice#at_client_limit?` compares them.
- `Counselor::InvitesController#create` refuses with a 422 and the message
  "Your practice has N active clients this month, which is your limit. Wait
  for clients to go quiet or add a counselor seat." when at the limit.
- `Api::SyncController#update` touches `last_synced_at` after a successful
  save, skipping the write when it was touched in the last ten minutes.
- Archive and reactivate set or clear `archived_at`. Nothing else reads it
  except the dashboard list.

### 7. Platform admin and the Crossroads cutover

- `namespace :platform`, gated by `current_counselor.platform_admin?`, 404
  otherwise. Pages: practices index (name, host, owner email, counselors,
  active count, trial end), practice show with the custom-domain field, and
  "Invite a practice owner" (email plus practice name) which sends the
  owner invite and shows the link for texting.
- The HTTP Basic admin controller, its layout, its tests, and the
  `admin.password` credential are deleted.
- `db/seeds.rb` creates the Crossroads practice idempotently: name
  "Crossroads Professional Counseling", slug `crossroads`, custom domain
  `app.crossroadcounselor.com`, colors `#32b1c3` and the current orange,
  icon and logo attached from files moved to `db/seeds/crossroads/`, website,
  booking URL, phone `(225) 341-4147`, appointment email, and the two
  resource links currently hardcoded. Seeds also create the platform admin
  counselor from `PLATFORM_ADMIN_EMAIL` with a random password and print a
  reset link, so no password lives in the repo.
- Cutover order in production: add the Wasabi bucket and keys to
  credentials, deploy, run seeds, set `PRODUCT_HOST`, add
  the wildcard DNS and Hatchbox domain entry, log in as platform admin via
  the printed reset link, invite the Crossroads owner, who then re-invites
  clients (the login launch already cleared them).

### 8. Testing

- Models: practice slug derivation and validation, brand fallbacks per
  field, active count and limit arithmetic including pooled members and
  removed members, counselor invite states, icon validation.
- Tenancy integration: a request on a custom domain, on a slug subdomain, on
  the bare product host, and on an unknown subdomain each resolve as
  specified; the manifest reflects the host's practice; a logged-in client on
  the product host wears their own practice's brand.
- Controllers: every counselor route rejects anonymous access, member-only
  pages reject owners' actions and vice versa, removed counselors cannot log
  in, invite acceptance creates practice and owner or member correctly,
  expired tokens are refused, client invite creation refuses at the limit,
  platform pages 404 for non-admins.
- Existing `authentication_lockdown_test.rb` gains the counselor and
  platform namespaces and drops the admin invites route.
- Manual: run seeds locally, view the app on `crossroads.lvh.me`, on
  `lvh.me`, and with a custom domain mapped in `/etc/hosts`; add a client
  invite from the dashboard and complete signup through the link.

## Out of scope

- Engagement summaries beyond last-active (project 3).
- Stripe, plans, seats, trial enforcement, referrals (project 4).
- Public landing page and self-serve counselor signup (project 5); the
  invite flow is built so signup only needs a public entry point.
- Hotwire Native (project 6).
- Moving a client between counselors, deleting a client account, and
  transferring practice ownership.
- Per-practice email sending domains.
