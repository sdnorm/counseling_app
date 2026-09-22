# Multi-Tenancy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the single-counselor app into practices with their own counselors, clients, and white-label branding, with Crossroads preserved on its own domain and a platform admin page replacing HTTP Basic.

**Architecture:** A `Practice` owns counselors, brand fields, and profile content. Counselors have their own password login and sessions, separate from clients. The practice is resolved from the request host; a table-less `Brand` applies generic fallbacks per field and every view reads from it. The counselor dashboard and platform pages are server-rendered Turbo pages. The active-client count is usage-based and enforced only when creating a client invite.

**Tech Stack:** Rails 8.1, SQLite, Active Storage on Wasabi (S3 API, proxy mode), `image_processing` + `ruby-vips`, Turbo, Stimulus, Minitest.

**Spec:** `docs/superpowers/specs/2026-09-22-multi-tenancy-design.md`

---

## How this plan is executed

Same shape as the login plan: every agent works in this checkout on the
`product-ready` branch (Herdr workspace `wM`). Lanes never edit the same
file. Each agent stages and commits only its own files, one commit per
task, with `git add <files> && git commit -m "..."` in a single command;
on `index.lock`, wait a few seconds and retry. Never `git stash`, never
`git add -A`, never push. If parallel `bin/rails test` runs hit SQLite
locks, run yours against a private database:
`DATABASE_URL=sqlite3:/private/tmp/<lane>-test.sqlite3 bin/rails test`.

The driver (Claude, tab 1) does the Foundation first, then prompts the
three lanes, then integrates.

| Lane | Agent | Owns |
|---|---|---|
| Foundation | driver | Gemfile, `config/**`, migrations, `db/schema.rb`, `app/models/**` (all new and changed models, including `brand.rb`), `app/controllers/application_controller.rb`, `app/controllers/users_controller.rb`, deletion of `app/controllers/admin/**`, `app/views/admin/**`, `app/views/layouts/admin.html.erb`, `test/controllers/admin/**`, `test/models/**`, `test/fixtures/**`, `test/test_helper.rb` |
| T — tenancy and client brand | pi | `app/controllers/manifests_controller.rb`, `app/views/manifests/**`, `app/views/layouts/application.html.erb`, `app/views/layouts/session.html.erb`, `app/views/shared/_brand_head.html.erb`, `app/views/shared/_practice_content.html.erb`, `app/javascript/controllers/resources_controller.js`, `app/javascript/controllers/navigation_controller.js`, `app/mailers/application_mailer.rb`, `app/mailers/invites_mailer.rb`, `app/mailers/passwords_mailer.rb`, `app/views/invites_mailer/**`, `app/views/passwords_mailer/**`, `app/controllers/api/sync_controller.rb`, `config/initializers/content_security_policy.rb`, `test/controllers/manifests_controller_test.rb`, `test/controllers/api/sync_controller_test.rb`, `test/integration/tenancy_test.rb`, `test/integration/client_practice_content_test.rb`, `test/integration/unauthenticated_layout_test.rb`, `test/integration/content_security_policy_test.rb`, `test/mailers/invites_mailer_test.rb`, `test/mailers/passwords_mailer_test.rb` |
| C — counselor auth and dashboard | codex | `app/controllers/concerns/counselor_authentication.rb`, `app/controllers/dashboard/**`, `app/views/dashboard/**`, `app/views/layouts/counselor.html.erb`, `app/mailers/counselor_passwords_mailer.rb`, `app/mailers/counselor_invites_mailer.rb`, `app/views/counselor_passwords_mailer/**`, `app/views/counselor_invites_mailer/**`, `app/javascript/controllers/brand_preview_controller.js`, `app/assets/stylesheets/counselor.css`, `test/controllers/dashboard/**`, `test/mailers/counselor_invites_mailer_test.rb` |
| P — platform admin, seeds, lockdown | grok | `app/controllers/platform/**`, `app/views/platform/**`, `db/seeds.rb`, `db/seeds/crossroads/**`, `app/assets/images/generic/**`, deletion of the Crossroads files in `public/` (icons and `manifest.json`), `README.md`, `test/controllers/platform/**`, `test/integration/authentication_lockdown_test.rb`, `test/integration/seeds_test.rb` |

Lanes T, C, and P run in parallel after the Foundation commit. P's
platform controllers inherit from C's `Dashboard::BaseController` and call
C's `CounselorInvitesMailer`; T's layouts reference P's generic asset
files. Each lane codes against the contract below; in the shared checkout
the files appear as they land, and the driver runs the full suite at
integration.

## Contract between lanes

### Routes (Foundation writes `config/routes.rb` in full)

```ruby
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :users, only: [ :new, :create ]
  get "/manifest.json", to: "manifests#show", as: :manifest

  namespace :api do
    resource :account_keys, only: [ :show, :update ], path: "account/keys"
    resource :sync, only: [ :show, :update ], controller: "sync"
    resource :push, only: [ :create, :destroy ], controller: "push"
    get "push/vapid_public_key", to: "push#vapid_public_key"
    patch "push/preferences", to: "push#update_preferences"
  end

  namespace :counselor, module: "dashboard" do
    root "clients#index"
    resource :session, only: [ :new, :create, :destroy ]
    resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]
    get  "setup/:token", to: "setups#show",   as: :setup
    post "setup/:token", to: "setups#create"
    resources :clients, only: [ :index ] do
      member do
        patch :archive
        patch :unarchive
      end
    end
    resources :invites, only: [ :index, :create ]
    resource :practice, only: [ :edit, :update ]
    resources :members, only: [ :index, :create, :destroy ]
    resource :account, only: [ :edit, :update ]
  end

  namespace :platform do
    root "practices#index"
    resources :practices, only: [ :index, :show, :update ]
    resources :practice_invites, only: [ :new, :create ]
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "/screens/:id", to: "screens#show", as: :screen

  root "home#index"
end
```

### Models (Foundation writes; everyone reads)

```ruby
Practice#host                 # custom_domain || "#{slug}.#{product_host}"
Practice#active_counselors    # counselors.active
Practice#client_limit         # client_limit_per_counselor * active_counselors.count
Practice#active_client_count  # clients synced or created in the last 30 days
Practice#at_client_limit?
Practice.for_host(host)       # Practice or nil
practice.resource_links       # ordered; accepts_nested_attributes_for, allow_destroy
practice.logo / practice.icon # has_one_attached

Counselor#owner? / #removed? / #remove!
Counselor.active              # removed_at IS NULL
Counselor#sessions            # CounselorSession
Counselor#clients             # User
Counselor#invite_codes

CounselorInvite.pending
CounselorInvite#usable? / #expired? / #accepted?
CounselorInvite#accept!(name:, password:)  # -> Counselor; raises ActiveRecord::RecordInvalid
CounselorInvite#practice_display_name      # practice&.name || practice_name

User#counselor, User#practice, User.active_recently, User.archived, User.unarchived
User#archive! / #unarchive! / #touch_last_synced!
InviteCode.generate(email_address, counselor:)   # email_address may be nil

Brand.new(practice_or_nil), Brand.generic
brand.generic?, brand.name, brand.product_name, brand.host, brand.title(page = nil)
brand.primary_color, brand.accent_color, brand.custom_colors?
brand.logo                   # attachment or nil
brand.icon_variant(size)     # variant or nil; sizes 192, 512, 180
brand.resources              # [{ title:, url:, description: }]
brand.schedule               # { booking_url:, phone:, appointment_email: } with blanks removed
brand.practice_content_json  # JSON string of { resources:, schedule: }

Current.practice, Current.counselor_session, Current.counselor
```

### Controller helpers

- `ApplicationController#brand` (helper method, Foundation): the
  logged-in client's practice brand, else the host's practice brand, else
  generic.
- `Dashboard::BaseController` (Lane C; URL namespace `/counselor`, Ruby module `Dashboard` so nothing collides with the `Counselor` model): `include CounselorAuthentication`,
  `layout "counselor"`, no-store headers, and `brand` overridden to
  `Brand.new(current_counselor.practice)`. Platform controllers (Lane P)
  inherit from it.
- `CounselorAuthentication` (Lane C): `current_counselor`,
  `require_counselor`, `allow_unauthenticated_counselor_access`,
  `start_new_counselor_session_for(counselor)`,
  `terminate_counselor_session`, `require_owner`.
- `CounselorInvitesMailer.invite(counselor_invite)` (Lane C): sends the
  setup link `counselor_setup_url(token, host: practice_host_or_product)`.
  Lane P calls `.deliver_later`.

### Generic assets (Lane P writes; Lane T references)

`app/assets/images/generic/icon-192.png`, `generic/icon-512.png`,
`generic/apple-touch-icon.png` (180 px), `generic/wordmark.svg`. Until the
product has a name these carry a plain placeholder mark.

### Practice content for client screens (Lane T)

The application layout embeds
`<script type="application/json" id="practice-content"><%= raw brand.practice_content_json %></script>`
and the Resources and Schedule JavaScript read it.

---

## Foundation (driver, on `product-ready`)

### Task F1: Storage, product config, Active Storage install

**Files:**
- Modify: `Gemfile`
- Modify: `config/storage.yml`
- Modify: `config/application.rb`
- Modify: `config/environments/production.rb`
- Create: `config/initializers/product.rb`
- Create: Active Storage migration (generated)

- [ ] **Step 1: Add the S3 SDK**

Append to `Gemfile` after the `image_processing` lines:

```ruby
# Active Storage on Wasabi (S3-compatible)
gem "aws-sdk-s3", require: false
```

Run: `bundle install`

- [ ] **Step 2: Add the Wasabi service**

Append to `config/storage.yml`:

```yaml
wasabi:
  service: S3
  endpoint: <%= ENV.fetch("WASABI_ENDPOINT", "https://s3.us-east-1.wasabisys.com") %>
  region: <%= ENV.fetch("WASABI_REGION", "us-east-1") %>
  bucket: <%= Rails.application.credentials.dig(:wasabi, :bucket) || ENV["WASABI_BUCKET"] %>
  access_key_id: <%= Rails.application.credentials.dig(:wasabi, :access_key_id) %>
  secret_access_key: <%= Rails.application.credentials.dig(:wasabi, :secret_access_key) %>
```

In `config/environments/production.rb` change `config.active_storage.service = :local` to `config.active_storage.service = :wasabi`. Development stays `:local` (this worktree has no credentials key); the spec's "development uses Wasabi" is relaxed to "when configured".

- [ ] **Step 3: Proxy mode and product config**

In `config/application.rb`, inside the `Application` class, add:

```ruby
    # Brand icons are served through the app so manifest URLs are stable and
    # same-origin; Wasabi's signed URLs would expire.
    config.active_storage.resolve_model_to_route = :rails_storage_proxy
```

Create `config/initializers/product.rb`:

```ruby
# The product's own host and name. Practices live at <slug>.<product_host>
# unless they have a custom domain; the bare product host wears the generic
# brand. Test uses example.com so integration tests can hit
# crossroads.example.com; development uses lvh.me, which resolves every
# subdomain to 127.0.0.1 without DNS setup.
Rails.application.configure do
  config.x.product_host = ENV.fetch("PRODUCT_HOST") { Rails.env.test? ? "example.com" : "lvh.me" }
  config.x.product_name = ENV.fetch("PRODUCT_NAME", "Counseling App")
end
```

- [ ] **Step 4: Host authorization in production**

Replace the `config.hosts = [...]` block in `config/environments/production.rb` with:

```ruby
  # Enable DNS rebinding protection and other `Host` header attacks.
  product_host = ENV.fetch("PRODUCT_HOST", "app.crossroadcounselor.com")
  custom_domain_host = Object.new
  def custom_domain_host.===(host)
    Rails.cache.fetch("custom_domain_host/#{host}", expires_in: 1.minute) do
      Practice.exists?(custom_domain: host.to_s.downcase)
    end
  end
  config.hosts = [
    product_host,
    /\A[a-z0-9-]+\.#{Regexp.escape(product_host)}\z/,
    custom_domain_host
  ]
```

- [ ] **Step 5: Install Active Storage and migrate**

Run: `bin/rails active_storage:install && bin/rails db:migrate && grep -c active_storage db/schema.rb`
Expected: a migration under `db/migrate/` creating `active_storage_blobs`, `active_storage_attachments`, `active_storage_variant_records`; grep prints 3 or more.

- [ ] **Step 6: Suite still green, commit**

Run: `bin/rails test 2>&1 | tail -3`
Expected: `0 failures, 0 errors`.

```bash
git add Gemfile Gemfile.lock config db/migrate db/schema.rb
git commit -m "Configure Wasabi storage, proxy mode, product host, and install Active Storage"
```

### Task F2: Tenancy tables, models, fixtures

**Files:**
- Create: `db/migrate/20260922000001_create_practices.rb`
- Create: `db/migrate/20260922000002_create_resource_links.rb`
- Create: `db/migrate/20260922000003_create_counselors.rb`
- Create: `db/migrate/20260922000004_create_counselor_sessions.rb`
- Create: `db/migrate/20260922000005_create_counselor_invites.rb`
- Create: `db/migrate/20260922000006_add_tenancy_to_users_and_invite_codes.rb`
- Create: `app/models/practice.rb`, `app/models/resource_link.rb`, `app/models/counselor.rb`, `app/models/counselor_session.rb`, `app/models/counselor_invite.rb`, `app/models/brand.rb`
- Modify: `app/models/user.rb`, `app/models/invite_code.rb`, `app/models/current.rb`
- Create: `test/fixtures/practices.yml`, `test/fixtures/counselors.yml`
- Modify: `test/fixtures/users.yml`, `test/fixtures/invite_codes.yml`, `test/test_helper.rb`
- Create: `test/models/practice_test.rb`, `test/models/counselor_test.rb`, `test/models/counselor_invite_test.rb`, `test/models/brand_test.rb`
- Modify: `test/models/user_test.rb`, `test/models/invite_code_test.rb`

- [ ] **Step 1: Migrations**

```ruby
# db/migrate/20260922000001_create_practices.rb
class CreatePractices < ActiveRecord::Migration[8.1]
  def change
    create_table :practices do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :custom_domain
      t.datetime :trial_ends_at
      t.string :primary_color
      t.string :accent_color
      t.string :website_url
      t.string :booking_url
      t.string :phone
      t.string :appointment_email
      t.integer :client_limit_per_counselor, null: false, default: 30
      t.timestamps
    end
    add_index :practices, :slug, unique: true
    add_index :practices, :custom_domain, unique: true
  end
end
```

```ruby
# db/migrate/20260922000002_create_resource_links.rb
class CreateResourceLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_links do |t|
      t.references :practice, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      t.string :description
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
```

```ruby
# db/migrate/20260922000003_create_counselors.rb
class CreateCounselors < ActiveRecord::Migration[8.1]
  def change
    create_table :counselors do |t|
      t.references :practice, null: false, foreign_key: true
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.string :role, null: false, default: "member"
      t.boolean :platform_admin, null: false, default: false
      t.datetime :removed_at
      t.timestamps
    end
    add_index :counselors, :email_address, unique: true
  end
end
```

```ruby
# db/migrate/20260922000004_create_counselor_sessions.rb
class CreateCounselorSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :counselor_sessions do |t|
      t.references :counselor, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
  end
end
```

```ruby
# db/migrate/20260922000005_create_counselor_invites.rb
class CreateCounselorInvites < ActiveRecord::Migration[8.1]
  def change
    create_table :counselor_invites do |t|
      t.string :token, null: false
      t.string :email_address, null: false
      t.string :role, null: false, default: "member"
      t.references :practice, foreign_key: true
      t.string :practice_name
      t.references :invited_by, foreign_key: { to_table: :counselors }
      t.datetime :accepted_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :counselor_invites, :token, unique: true
  end
end
```

```ruby
# db/migrate/20260922000006_add_tenancy_to_users_and_invite_codes.rb
class AddTenancyToUsersAndInviteCodes < ActiveRecord::Migration[8.1]
  # Both tables are empty after the one-secret login launch migration, so
  # NOT NULL columns without defaults are safe here.
  def change
    add_reference :users, :counselor, null: false, foreign_key: true
    add_column :users, :archived_at, :datetime
    add_column :users, :last_synced_at, :datetime
    add_reference :invite_codes, :counselor, null: false, foreign_key: true
  end
end
```

Run: `bin/rails db:migrate`
Expected: all six migrate; `db/schema.rb` gains the tables.

- [ ] **Step 2: Practice, ResourceLink, Counselor, CounselorSession, CounselorInvite**

```ruby
# app/models/practice.rb
class Practice < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  COLOR_FORMAT = /\A#[0-9a-fA-F]{6}\z/
  ACTIVE_WINDOW = 30.days
  IMAGE_TYPES = %w[image/png image/jpeg].freeze
  IMAGE_MAX_BYTES = 2.megabytes
  ICON_MIN_PX = 512

  has_many :counselors, dependent: :restrict_with_error
  has_many :clients, through: :counselors
  has_many :resource_links, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :practice
  has_many :counselor_invites, dependent: :destroy
  has_one_attached :logo
  has_one_attached :icon

  accepts_nested_attributes_for :resource_links, allow_destroy: true, reject_if: :all_blank

  normalizes :slug, with: ->(value) { value.to_s.strip.downcase }
  normalizes :custom_domain, with: ->(value) { value.presence&.strip&.downcase }
  normalizes :primary_color, :accent_color, with: ->(value) { value.presence&.strip&.downcase }
  normalizes :website_url, :booking_url, :phone, :appointment_email, with: ->(value) { value.presence&.strip }

  before_validation :derive_slug, on: :create

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT, message: "may only contain lowercase letters, numbers, and dashes" }
  validates :custom_domain, uniqueness: true, allow_nil: true
  validates :primary_color, :accent_color, format: { with: COLOR_FORMAT, message: "must look like #1a2b3c" }, allow_nil: true
  validates :client_limit_per_counselor, numericality: { only_integer: true, greater_than: 0 }
  validate :icon_is_a_square_image
  validate :logo_is_an_image

  # Custom domain first, then <slug>.<product host>. Anything else is nil:
  # the bare product host and unknown hosts wear the generic brand.
  def self.for_host(host)
    host = host.to_s.downcase
    if (practice = find_by(custom_domain: host))
      return practice
    end
    suffix = ".#{Rails.application.config.x.product_host}"
    return nil unless host.end_with?(suffix)
    slug = host.delete_suffix(suffix)
    find_by(slug: slug) unless slug.include?(".")
  end

  def host
    custom_domain || "#{slug}.#{Rails.application.config.x.product_host}"
  end

  def active_counselors
    counselors.active
  end

  def client_limit
    client_limit_per_counselor * active_counselors.count
  end

  # Usage-based on purpose: archiving never changes this, so there is nothing
  # to game. A client who stops syncing drops out of the count by themselves.
  def active_client_count
    clients.active_recently.count
  end

  def at_client_limit?
    active_client_count >= client_limit
  end

  private

  def derive_slug
    return if slug.present? || name.blank?
    base = name.parameterize.presence || "practice"
    candidate = base
    n = 2
    while Practice.exists?(slug: candidate)
      candidate = "#{base}-#{n}"
      n += 1
    end
    self.slug = candidate
  end

  def logo_is_an_image
    validate_image(:logo, square: false)
  end

  def icon_is_a_square_image
    validate_image(:icon, square: true)
  end

  # Only checks a newly assigned file; existing attachments were checked when
  # they were attached. Dimensions come from vips on the upload itself,
  # because Active Storage analysis runs after commit.
  def validate_image(attribute, square:)
    change = attachment_changes[attribute.to_s]
    return unless change.is_a?(ActiveStorage::Attached::Changes::CreateOne)

    blob = change.blob
    unless blob.content_type.in?(IMAGE_TYPES)
      errors.add(attribute, "must be a PNG or JPEG")
      return
    end
    if blob.byte_size > IMAGE_MAX_BYTES
      errors.add(attribute, "must be under #{IMAGE_MAX_BYTES / 1.megabyte} MB")
      return
    end
    return unless square

    width, height = image_dimensions(change.attachable)
    errors.add(attribute, "could not be read") and return if width.nil?
    errors.add(attribute, "must be square") if width != height
    errors.add(attribute, "must be at least #{ICON_MIN_PX} pixels") if width < ICON_MIN_PX
  end

  def image_dimensions(attachable)
    io = attachable.respond_to?(:tempfile) ? attachable.tempfile : attachable[:io]
    io.rewind
    image = Vips::Image.new_from_buffer(io.read, "")
    io.rewind
    [ image.width, image.height ]
  rescue Vips::Error, NoMethodError
    nil
  end
end
```

```ruby
# app/models/resource_link.rb
class ResourceLink < ApplicationRecord
  belongs_to :practice, inverse_of: :resource_links

  normalizes :title, :url, :description, with: ->(value) { value.presence&.strip }

  validates :title, presence: true
  validates :url, presence: true, format: { with: %r{\Ahttps?://}i, message: "must start with http:// or https://" }
end
```

```ruby
# app/models/counselor.rb
class Counselor < ApplicationRecord
  MINIMUM_PASSWORD_LENGTH = 12
  ROLES = %w[owner member].freeze

  belongs_to :practice
  has_many :sessions, class_name: "CounselorSession", dependent: :destroy
  has_many :clients, class_name: "User", dependent: :restrict_with_error
  has_many :invite_codes, dependent: :destroy
  has_many :sent_invites, class_name: "CounselorInvite", foreign_key: :invited_by_id, dependent: :nullify, inverse_of: :invited_by

  # Counselors hold no encrypted data, so an ordinary password is fine here.
  has_secure_password

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  encrypts :email_address, deterministic: true

  validates :email_address, presence: true, uniqueness: true
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true

  scope :active, -> { where(removed_at: nil) }

  def owner?
    role == "owner"
  end

  def removed?
    removed_at.present?
  end

  # Keeps the record (clients still point at it) but ends every session and
  # blocks login.
  def remove!
    transaction do
      update!(removed_at: Time.current)
      sessions.destroy_all
    end
  end
end
```

```ruby
# app/models/counselor_session.rb
class CounselorSession < ApplicationRecord
  MAX_AGE = 30.days

  belongs_to :counselor

  scope :active, -> { where(created_at: MAX_AGE.ago..) }
end
```

```ruby
# app/models/counselor_invite.rb
class CounselorInvite < ApplicationRecord
  EXPIRY = 7.days

  has_secure_token :token
  belongs_to :practice, optional: true
  belongs_to :invited_by, class_name: "Counselor", optional: true, inverse_of: :sent_invites

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :practice_name, with: ->(v) { v.presence&.strip }
  encrypts :email_address, deterministic: true

  validates :email_address, presence: true
  validates :role, inclusion: { in: Counselor::ROLES }
  validate :targets_exactly_one_practice

  before_create { self.expires_at ||= EXPIRY.from_now }

  scope :pending, -> { where(accepted_at: nil).where(expires_at: Time.current..) }

  def expired?
    expires_at <= Time.current
  end

  def accepted?
    accepted_at.present?
  end

  def usable?
    !expired? && !accepted?
  end

  def practice_display_name
    practice&.name || practice_name
  end

  # Owner invites create the practice; member invites join one. Either way
  # the counselor, the practice, and the acceptance land together or not at
  # all. Raises ActiveRecord::RecordInvalid with the failing record's errors.
  def accept!(name:, password:)
    raise ActiveRecord::RecordInvalid.new(self) unless usable?

    transaction do
      target = practice || Practice.create!(name: practice_name, trial_ends_at: 30.days.from_now)
      counselor = target.counselors.create!(email_address: email_address, name: name, password: password, role: role)
      update!(accepted_at: Time.current)
      counselor
    end
  end

  private

  def targets_exactly_one_practice
    if practice.present? == practice_name.present?
      errors.add(:base, "must name either a practice to join or a new practice to create")
    end
  end
end
```

- [ ] **Step 3: User, InviteCode, Current, Brand**

`app/models/user.rb`: add after `belongs_to :invite_code`:

```ruby
  belongs_to :counselor
  has_one :practice, through: :counselor

  # "Active" for billing means used the app recently, or just joined. The
  # archive flag is deliberately absent: it is a list-tidying tool.
  scope :active_recently, -> {
    since = Practice::ACTIVE_WINDOW.ago
    where(last_synced_at: since..).or(where(created_at: since..))
  }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :unarchived, -> { where(archived_at: nil) }
```

and these public methods before `private`:

```ruby
  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  # Called on every successful sync. One write per ten minutes is plenty for
  # a 30-day window and keeps save-on-every-entry usage cheap.
  def touch_last_synced!
    return if last_synced_at && last_synced_at > 10.minutes.ago
    update_column(:last_synced_at, Time.current)
  end
```

`app/models/invite_code.rb`:

```ruby
class InviteCode < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :counselor
  validates :code, presence: true, uniqueness: true
  normalizes :email_address, with: ->(e) { e.presence&.strip&.downcase }
  encrypts :email_address, deterministic: true

  # Email is optional: invites are shared as links first. Keep it when the
  # counselor gives it so the invite email and the list can show it.
  def self.generate(email_address, counselor:)
    create!(code: SecureRandom.alphanumeric(8).upcase, email_address: email_address, counselor: counselor)
  end

  # Marks an unused code as used in a single statement so two concurrent signups
  # can't both claim it. Returns the code, or nil if it was already taken.
  def self.claim(code)
    return if code.blank?
    return unless where(code: code, used: false).update_all(used: true) == 1
    find_by(code: code)
  end
end
```

`app/models/current.rb`:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :counselor_session
  attribute :practice
  delegate :user, to: :session, allow_nil: true
  delegate :counselor, to: :counselor_session, allow_nil: true
end
```

```ruby
# app/models/brand.rb
#
# What a page wears. Wraps a practice or nil and applies the generic product
# fallback per field, so views never ask "is there a practice?" themselves.
class Brand
  DEFAULT_PRIMARY = "#32b1c3"
  DEFAULT_ACCENT = "#f06623"
  ICON_SIZES = [ 192, 512, 180 ].freeze

  attr_reader :practice

  def initialize(practice)
    @practice = practice
  end

  def self.generic
    new(nil)
  end

  def generic?
    practice.nil?
  end

  def product_name
    Rails.application.config.x.product_name
  end

  def name
    practice&.name.presence || product_name
  end

  def host
    practice&.host || Rails.application.config.x.product_host
  end

  def title(page = nil)
    [ page, name ].compact.join(" · ")
  end

  def primary_color
    practice&.primary_color.presence || DEFAULT_PRIMARY
  end

  def accent_color
    practice&.accent_color.presence || DEFAULT_ACCENT
  end

  def custom_colors?
    practice.present? && (practice.primary_color.present? || practice.accent_color.present?)
  end

  def logo
    practice.logo if practice&.logo&.attached?
  end

  def icon_variant(size)
    raise ArgumentError, "unsupported icon size #{size}" unless size.in?(ICON_SIZES)
    return unless practice&.icon&.attached?
    practice.icon.variant(resize_to_fill: [ size, size ], format: :png)
  end

  def resources
    return [] unless practice
    practice.resource_links.map { |link| { title: link.title, url: link.url, description: link.description } }
  end

  def schedule
    return {} unless practice
    { booking_url: practice.booking_url, phone: practice.phone, appointment_email: practice.appointment_email }.compact_blank
  end

  def practice_content_json
    { resources: resources, schedule: schedule }.to_json
  end
end
```

- [ ] **Step 4: Fixtures and test helper**

```yaml
# test/fixtures/practices.yml
crossroads:
  name: Crossroads Professional Counseling
  slug: crossroads
  custom_domain: app.crossroadcounselor.com
  trial_ends_at: <%= 1.year.from_now %>
  primary_color: "#32b1c3"
  accent_color: "#f06623"
  website_url: https://crossroadcounselor.com/
  booking_url: https://www.therapyportal.com/p/crossroadspc/
  phone: "(225) 341-4147"
  appointment_email: logan@crossroadcounselor.com

riverbend:
  name: Riverbend Therapy
  slug: riverbend
  trial_ends_at: <%= 20.days.from_now %>
```

```yaml
# test/fixtures/counselors.yml
logan:
  practice: crossroads
  email_address: logan@crossroadcounselor.com
  password_digest: <%= BCrypt::Password.create("counselor-secret-123") %>
  name: Logan
  role: owner
  platform_admin: true

jo:
  practice: crossroads
  email_address: jo@crossroadcounselor.com
  password_digest: <%= BCrypt::Password.create("counselor-secret-123") %>
  name: Jo
  role: member

sam:
  practice: riverbend
  email_address: sam@riverbend.example
  password_digest: <%= BCrypt::Password.create("counselor-secret-123") %>
  name: Sam
  role: owner
```

`test/fixtures/users.yml`: add `counselor: logan` to `danny` and `counselor: jo` to `maria`.
`test/fixtures/invite_codes.yml`: add `counselor: logan` to `danny_invite` and `counselor: jo` to `maria_invite`.

`test/test_helper.rb`: after the `WRAPPED_KEY` constant add:

```ruby
COUNSELOR_PASSWORD = "counselor-secret-123"

# A real PNG for logo and icon uploads, made on the fly so no binary fixture
# is committed. Available in model and integration tests alike.
module ImageFixtures
  def png_upload(width, height = width, name: "icon.png")
    data = Vips::Image.black(width, height, bands: 3).write_to_buffer(".png")
    Rack::Test::UploadedFile.new(StringIO.new(data), "image/png", original_filename: name)
  end
end
```

Inside `class TestCase` (under `module ActiveSupport`) add `include ImageFixtures` next to `include WebPushTestHelpers`. Inside `class ActionDispatch::IntegrationTest` add:

```ruby
  def sign_in_counselor_as(counselor, password: COUNSELOR_PASSWORD)
    post counselor_session_path, params: { email_address: counselor.email_address, password: password }
  end
```

- [ ] **Step 5: Model tests**

```ruby
# test/models/practice_test.rb
require "test_helper"

class PracticeTest < ActiveSupport::TestCase
  test "slug derives from the name and stays unique" do
    a = Practice.create!(name: "Calm Waters Counseling")
    b = Practice.create!(name: "Calm Waters Counseling")
    assert_equal "calm-waters-counseling", a.slug
    assert_equal "calm-waters-counseling-2", b.slug
  end

  test "slug format is enforced" do
    practice = practices(:riverbend)
    practice.slug = "Not Valid!"
    assert_not practice.valid?
  end

  test "host prefers the custom domain" do
    assert_equal "app.crossroadcounselor.com", practices(:crossroads).host
    assert_equal "riverbend.example.com", practices(:riverbend).host
  end

  test "for_host resolves custom domains, slugs, and nothing else" do
    assert_equal practices(:crossroads), Practice.for_host("app.crossroadcounselor.com")
    assert_equal practices(:crossroads), Practice.for_host("APP.CROSSROADCOUNSELOR.COM")
    assert_equal practices(:riverbend), Practice.for_host("riverbend.example.com")
    assert_nil Practice.for_host("example.com")
    assert_nil Practice.for_host("nobody.example.com")
    assert_nil Practice.for_host("deep.riverbend.example.com")
  end

  test "colors must be hex" do
    practice = practices(:riverbend)
    practice.primary_color = "blue"
    assert_not practice.valid?
    practice.primary_color = "#ABCDEF"
    assert practice.valid?
    assert_equal "#abcdef", practice.primary_color
  end

  test "active client count is usage based and pooled across counselors" do
    practice = practices(:crossroads)
    users(:danny).update_columns(last_synced_at: 2.days.ago, created_at: 90.days.ago)
    users(:maria).update_columns(last_synced_at: nil, created_at: 90.days.ago)
    assert_equal 1, practice.active_client_count

    users(:maria).update_columns(created_at: 3.days.ago)
    assert_equal 2, practice.active_client_count, "a newly invited client counts before their first sync"

    users(:danny).archive!
    assert_equal 2, practice.active_client_count, "archiving must not change the count"
  end

  test "client limit multiplies by active counselors" do
    practice = practices(:crossroads)
    assert_equal 60, practice.client_limit
    counselors(:jo).remove!
    assert_equal 30, practice.client_limit
    assert_not practice.at_client_limit?
    practice.update!(client_limit_per_counselor: 1)
    users(:danny).update_columns(last_synced_at: 1.hour.ago)
    assert practice.at_client_limit?
  end

  test "icon must be a square PNG of at least 512 pixels" do
    practice = practices(:riverbend)
    practice.icon = png_upload(300, 200)
    assert_not practice.valid?
    assert_includes practice.errors[:icon], "must be square"

    practice.icon = png_upload(256)
    assert_not practice.valid?
    assert_includes practice.errors[:icon], "must be at least 512 pixels"

    practice.icon = png_upload(512)
    assert practice.valid?, practice.errors.full_messages.to_sentence
  end

  test "resource links are ordered and removable through nested attributes" do
    practice = practices(:riverbend)
    practice.update!(resource_links_attributes: [
      { title: "Second", url: "https://b.example", position: 2 },
      { title: "First", url: "https://a.example", position: 1 }
    ])
    assert_equal %w[First Second], practice.resource_links.map(&:title)
    first = practice.resource_links.first
    practice.update!(resource_links_attributes: [ { id: first.id, _destroy: "1" } ])
    assert_equal %w[Second], practice.reload.resource_links.map(&:title)
  end
end
```

```ruby
# test/models/counselor_test.rb
require "test_helper"

class CounselorTest < ActiveSupport::TestCase
  test "requires a 12 character password" do
    counselor = Counselor.new(practice: practices(:riverbend), email_address: "new@riverbend.example", name: "New", role: "member", password: "short")
    assert_not counselor.valid?
    counselor.password = "long enough password"
    assert counselor.valid?, counselor.errors.full_messages.to_sentence
  end

  test "role is owner or member" do
    counselor = counselors(:jo)
    counselor.role = "admin"
    assert_not counselor.valid?
  end

  test "remove! ends sessions and leaves the active scope" do
    counselor = counselors(:jo)
    counselor.sessions.create!(ip_address: "127.0.0.1", user_agent: "test")
    counselor.remove!
    assert counselor.removed?
    assert_equal 0, counselor.sessions.count
    assert_not_includes Counselor.active, counselor
  end

  test "email is unique regardless of case" do
    dup = Counselor.new(practice: practices(:riverbend), email_address: "LOGAN@crossroadcounselor.com", name: "Dup", role: "member", password: "long enough password")
    assert_not dup.valid?
  end
end
```

```ruby
# test/models/counselor_invite_test.rb
require "test_helper"

class CounselorInviteTest < ActiveSupport::TestCase
  test "must target exactly one practice" do
    assert_not CounselorInvite.new(email_address: "a@example.com", role: "member").valid?
    assert_not CounselorInvite.new(email_address: "a@example.com", role: "owner", practice: practices(:riverbend), practice_name: "X").valid?
    assert CounselorInvite.new(email_address: "a@example.com", role: "member", practice: practices(:riverbend)).valid?
    assert CounselorInvite.new(email_address: "a@example.com", role: "owner", practice_name: "New Practice").valid?
  end

  test "gets a token and a seven day expiry" do
    invite = CounselorInvite.create!(email_address: "a@example.com", role: "owner", practice_name: "New Practice")
    assert invite.token.present?
    assert_in_delta 7.days.from_now, invite.expires_at, 5.seconds
    assert invite.usable?
  end

  test "accepting an owner invite creates the practice and the owner" do
    invite = CounselorInvite.create!(email_address: "owner@example.com", role: "owner", practice_name: "Calm Waters")

    counselor = invite.accept!(name: "Pat", password: "long enough password")

    assert counselor.owner?
    assert_equal "Calm Waters", counselor.practice.name
    assert_equal "calm-waters", counselor.practice.slug
    assert_in_delta 30.days.from_now, counselor.practice.trial_ends_at, 5.seconds
    assert invite.reload.accepted?
  end

  test "accepting a member invite joins the practice" do
    invite = CounselorInvite.create!(email_address: "member@example.com", role: "member", practice: practices(:riverbend), invited_by: counselors(:sam))

    counselor = invite.accept!(name: "Kim", password: "long enough password")

    assert_equal practices(:riverbend), counselor.practice
    assert_not counselor.owner?
  end

  test "an expired or accepted invite cannot be accepted, and a failed acceptance creates nothing" do
    invite = CounselorInvite.create!(email_address: "x@example.com", role: "owner", practice_name: "Expired")
    invite.update_column(:expires_at, 1.hour.ago)
    assert_raises(ActiveRecord::RecordInvalid) { invite.accept!(name: "X", password: "long enough password") }

    dup = CounselorInvite.create!(email_address: counselors(:logan).email_address, role: "owner", practice_name: "Dup Practice")
    assert_no_difference -> { Practice.count } do
      assert_raises(ActiveRecord::RecordInvalid) { dup.accept!(name: "X", password: "long enough password") }
    end
  end
end
```

```ruby
# test/models/brand_test.rb
require "test_helper"

class BrandTest < ActiveSupport::TestCase
  test "generic brand uses product config" do
    brand = Brand.generic
    assert brand.generic?
    assert_equal "Counseling App", brand.name
    assert_equal "example.com", brand.host
    assert_equal Brand::DEFAULT_PRIMARY, brand.primary_color
    assert_nil brand.logo
    assert_nil brand.icon_variant(192)
    assert_equal [], brand.resources
    assert_equal({}, brand.schedule)
  end

  test "practice brand falls back per field" do
    practice = practices(:riverbend)
    practice.update!(accent_color: "#112233", booking_url: "https://book.example")
    brand = Brand.new(practice)
    assert_equal "Riverbend Therapy", brand.name
    assert_equal Brand::DEFAULT_PRIMARY, brand.primary_color
    assert_equal "#112233", brand.accent_color
    assert brand.custom_colors?
    assert_equal({ booking_url: "https://book.example" }, brand.schedule)
    assert_equal "Journal · Riverbend Therapy", brand.title("Journal")
  end

  test "icon variants exist only with an attached icon" do
    practice = practices(:riverbend)
    practice.icon.attach(png_upload(512))
    practice.save!
    assert Brand.new(practice).icon_variant(512)
    assert_raises(ArgumentError) { Brand.new(practice).icon_variant(64) }
  end

  test "practice content json carries resources and schedule" do
    practice = practices(:crossroads)
    practice.resource_links.create!(title: "Site", url: "https://crossroadcounselor.com/", description: "About")
    json = JSON.parse(Brand.new(practice).practice_content_json)
    assert_equal "Site", json["resources"].first["title"]
    assert_equal "(225) 341-4147", json["schedule"]["phone"]
  end
end
```

Update `test/models/user_test.rb`: every `User.new(...)` gains `counselor: counselors(:logan)`. Add:

```ruby
  test "touch_last_synced! writes at most every ten minutes" do
    user = users(:danny)
    user.touch_last_synced!
    first = user.reload.last_synced_at
    assert first
    user.touch_last_synced!
    assert_equal first, user.reload.last_synced_at
    user.update_column(:last_synced_at, 11.minutes.ago)
    user.touch_last_synced!
    assert_operator user.reload.last_synced_at, :>, first
  end
```

Update `test/models/invite_code_test.rb`: every `InviteCode.generate("...")` becomes `InviteCode.generate("...", counselor: counselors(:logan))`; add `test "email is optional" do assert InviteCode.generate(nil, counselor: counselors(:logan)).persisted? end`.

- [ ] **Step 6: Run model tests, then the whole suite**

Run: `bin/rails test test/models`
Expected: PASS. Then `bin/rails test 2>&1 | tail -3` will show failures in `users_controller_test`, `admin/invites_controller_test`, `sync_controller_test` (fixtures fine, but `InviteCode.generate` callers). Those are fixed in F3.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models test/models test/fixtures test/test_helper.rb
git commit -m "Add practices, counselors, counselor sessions and invites, brand, and tenancy columns"
```

### Task F3: Routes, tenant resolution, signup attaches the counselor, admin removed

**Files:**
- Modify: `config/routes.rb` (replace with the contract version above)
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/users_controller.rb`
- Modify: `test/controllers/users_controller_test.rb`
- Delete: `app/controllers/admin/invites_controller.rb`, `app/views/admin/`, `app/views/layouts/admin.html.erb`, `test/controllers/admin/invites_controller_test.rb`

- [ ] **Step 1: Routes**

Replace `config/routes.rb` with the file in the Contract section.

- [ ] **Step 2: ApplicationController**

```ruby
class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current_practice
  helper_method :brand

  private

  # The host decides which practice a page wears before anyone is logged in.
  def set_current_practice
    Current.practice = Practice.for_host(request.host)
  end

  # After a client logs in, their own counselor's practice wins over the
  # host's: the native app only ever talks to the product host, and a
  # Crossroads client there must still see Crossroads.
  def brand
    @brand ||= Brand.new(current_user&.counselor&.practice || Current.practice)
  end
end
```

- [ ] **Step 3: Signup attaches the counselor**

In `app/controllers/users_controller.rb`, inside `claim_code_and_save`, change `@user.invite_code = invite_code` to:

```ruby
      @user.invite_code = invite_code
      @user.counselor = invite_code.counselor
```

In `test/controllers/users_controller_test.rb`, change every `InviteCode.generate("...")` to `InviteCode.generate("...", counselor: counselors(:logan))` and add:

```ruby
  test "signup attaches the client to the inviting counselor" do
    code = InviteCode.generate("attach@example.com", counselor: counselors(:jo))
    post users_path, params: { user: {
      email_address: "attach@example.com", password: NEW_AUTH_HASH, invite_code: code.code,
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY
    } }, as: :json
    assert_response :created
    assert_equal counselors(:jo), User.find_by(email_address: "attach@example.com").counselor
  end
```

- [ ] **Step 4: Delete the HTTP Basic admin**

```bash
git rm -r app/controllers/admin app/views/admin app/views/layouts/admin.html.erb test/controllers/admin
```

In `test/integration/authentication_lockdown_test.rb` delete the `"admin invites require http basic auth"` test (Lane P rewrites this file; this keeps the suite loading).

- [ ] **Step 5: Whole suite green, commit**

Run: `bin/rails test && bin/rubocop`
Expected: `0 failures, 0 errors`.

```bash
git add config/routes.rb app/controllers/application_controller.rb app/controllers/users_controller.rb test/controllers/users_controller_test.rb test/integration/authentication_lockdown_test.rb
git commit -m "Resolve the practice from the host, attach clients to counselors, remove HTTP Basic admin"
```

---

## Lane T — tenancy and client brand (pi)

Only touch the files Lane T owns. Views must read everything from `brand`
(the `ApplicationController` helper); never call `Current.practice` from a
view. Run `bin/rails test` before each commit.

### Task T1: Dynamic manifest

**Files:**
- Create: `app/controllers/manifests_controller.rb`
- Create: `app/views/manifests/show.json.jbuilder`
- Create: `test/controllers/manifests_controller_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/manifests_controller_test.rb
require "test_helper"

class ManifestsControllerTest < ActionDispatch::IntegrationTest
  test "generic manifest on the product host" do
    host! "example.com"
    get manifest_path

    assert_response :success
    assert_equal "application/manifest+json", response.media_type
    body = JSON.parse(response.body)
    assert_equal "Counseling App", body["name"]
    assert_equal "#32b1c3", body["theme_color"]
    assert_match %r{/assets/generic/icon-192}, body["icons"].first["src"]
    assert_match(/public/, response.headers["Cache-Control"])
  end

  test "practice manifest on a custom domain uses its name, colors, and icon" do
    practice = practices(:crossroads)
    practice.icon.attach(png_upload(512))
    practice.save!
    host! "app.crossroadcounselor.com"

    get manifest_path

    body = JSON.parse(response.body)
    assert_equal "Crossroads Professional Counseling", body["name"]
    assert_equal "Crossroads Professional Counseling", body["short_name"]
    assert_match %r{/rails/active_storage/representations/proxy/}, body["icons"].first["src"]
    assert_equal [ "192x192", "512x512" ], body["icons"].map { |i| i["sizes"] }
  end

  test "practice without an icon falls back to the generic icons" do
    host! "riverbend.example.com"
    get manifest_path
    body = JSON.parse(response.body)
    assert_equal "Riverbend Therapy", body["name"]
    assert_match %r{/assets/generic/icon-512}, body["icons"].last["src"]
  end

  test "manifest is public" do
    get manifest_path
    assert_response :success
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/controllers/manifests_controller_test.rb`
Expected: FAIL, `uninitialized constant ManifestsController`.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/manifests_controller.rb
class ManifestsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  # "Add to Home Screen" reads this once per install, so it must describe the
  # host's practice: its name and icon end up on the client's phone.
  def show
    expires_in 5.minutes, public: true
    render formats: :json, content_type: "application/manifest+json"
  end
end
```

```ruby
# app/views/manifests/show.json.jbuilder
json.name brand.name
json.short_name brand.name.truncate(30, omission: "")
json.start_url "/"
json.display "standalone"
json.background_color "#f3f8f9"
json.theme_color brand.primary_color
json.icons [ 192, 512 ] do |size|
  variant = brand.icon_variant(size)
  json.src variant ? url_for(variant) : image_path("generic/icon-#{size}.png")
  json.sizes "#{size}x#{size}"
  json.type "image/png"
end
```

Delete `public/manifest.json` is Lane P's job (it owns `public/`); until then the route above shadows the static file because `config.public_file_server` serves only when no route matches. Confirm: `curl -s localhost:3000/manifest.json` shows the dynamic body during manual checks.

- [ ] **Step 4: Run the tests, commit**

Run: `bin/rails test test/controllers/manifests_controller_test.rb`
Expected: PASS. (If `png_upload` is missing, Foundation F2 Step 4 has not landed yet: wait for it.)

```bash
git add app/controllers/manifests_controller.rb app/views/manifests test/controllers/manifests_controller_test.rb
git commit -m "Serve the web app manifest per practice"
```

### Task T2: Brand in the client layouts

**Files:**
- Create: `app/views/shared/_brand_head.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/views/layouts/session.html.erb`
- Create: `test/integration/tenancy_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/integration/tenancy_test.rb
require "test_helper"

class TenancyTest < ActionDispatch::IntegrationTest
  test "the login page on a custom domain wears that practice" do
    host! "app.crossroadcounselor.com"
    get new_session_path
    assert_select "title", "Sign in · Crossroads Professional Counseling"
    assert_select ".auth-brand .mark", text: /Crossroads/i
    assert_select "meta[name=theme-color][content='#32b1c3']"
  end

  test "the login page on a slug subdomain wears that practice, with generic colors when unset" do
    host! "riverbend.example.com"
    get new_session_path
    assert_select "title", "Sign in · Riverbend Therapy"
    assert_select "style", false, "no color override when the practice has no colors"
  end

  test "custom colors override the palette" do
    practices(:riverbend).update!(primary_color: "#112233", accent_color: "#445566")
    host! "riverbend.example.com"
    get new_session_path
    assert_select "style", /--blue:\s*#112233/
    assert_select "style", /--orange:\s*#445566/
  end

  test "the bare product host and unknown subdomains wear the generic brand" do
    [ "example.com", "nobody.example.com" ].each do |host|
      host! host
      get new_session_path
      assert_select "title", "Sign in · Counseling App"
      assert_select "link[rel=apple-touch-icon][href*='generic/apple-touch-icon']"
    end
  end

  test "a logged in client wears their own practice even on the product host" do
    host! "example.com"
    sign_in_as users(:danny)
    get root_path
    assert_select "title", "Crossroads Professional Counseling"
    assert_select "#topbar-title", text: /Crossroads/i
  end

  test "a practice logo replaces the wordmark text" do
    practice = practices(:riverbend)
    practice.logo.attach(png_upload(400, 100, name: "logo.png"))
    practice.save!
    host! "riverbend.example.com"
    get new_session_path
    assert_select ".auth-brand img[alt='Riverbend Therapy']"
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/integration/tenancy_test.rb`
Expected: FAIL on titles and brand markup.

- [ ] **Step 3: Shared head partial**

```erb
<%# app/views/shared/_brand_head.html.erb
    Everything in <head> that depends on whose brand the page wears.
    `page` is the page-specific title prefix, or nil. %>
<link rel="manifest" href="<%= manifest_path %>">
<% touch = brand.icon_variant(180) %>
<link rel="apple-touch-icon" href="<%= touch ? url_for(touch) : image_path("generic/apple-touch-icon.png") %>">
<meta name="theme-color" content="<%= brand.primary_color %>">
<title><%= brand.title(page) %></title>
<% if brand.custom_colors? %>
  <style nonce="<%= content_security_policy_nonce %>">:root{--blue:<%= brand.primary_color %>;--orange:<%= brand.accent_color %>;}</style>
<% end %>
```

Note: the CSP allows `style_src :unsafe_inline`, so the nonce is harmless and future-proof.

- [ ] **Step 4: Application layout**

In `app/views/layouts/application.html.erb` replace the four lines

```erb
    <link rel="manifest" href="/manifest.json">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    <meta name="theme-color" content="#32b1c3">
    <title>Crossroads Professional Counseling</title>
```

with `<%= render "shared/brand_head", page: nil %>`, and replace

```erb
        <span class="topbar-title" id="topbar-title">CROSSROADS</span>
```

with

```erb
        <span class="topbar-title" id="topbar-title"><%= brand.name.upcase %></span>
```

- [ ] **Step 5: Session layout**

Replace the same four head lines with `<%= render "shared/brand_head", page: "Sign in" %>` and replace the `.auth-brand` block with:

```erb
        <div class="auth-brand">
          <% if brand.logo %>
            <%= image_tag url_for(brand.logo.variant(resize_to_limit: [ 240, 80 ])), alt: brand.name, style: "max-width:240px;max-height:80px;" %>
          <% else %>
            <span class="mark"><%= brand.name.upcase %></span>
            <% unless brand.generic? %><span class="sub"><%= brand.product_name.upcase %></span><% end %>
          <% end %>
        </div>
```

- [ ] **Step 6: Run the tests, commit**

Run: `bin/rails test test/integration/tenancy_test.rb test/integration`
Expected: PASS. `unauthenticated_layout_test.rb` may assert old Crossroads text; if so update its expectations to the generic name, since the default test host is `www.example.com`.

```bash
git add app/views/shared/_brand_head.html.erb app/views/layouts/application.html.erb app/views/layouts/session.html.erb test/integration/tenancy_test.rb test/integration/unauthenticated_layout_test.rb
git commit -m "Client layouts wear the practice brand"
```

### Task T3: Practice content on the Resources and Schedule screens

**Files:**
- Create: `app/views/shared/_practice_content.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/javascript/controllers/resources_controller.js`
- Modify: `app/javascript/controllers/navigation_controller.js`
- Create: `test/integration/client_practice_content_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/client_practice_content_test.rb
require "test_helper"

# The client screens render the counselor's links from a JSON blob the
# layout embeds. There is no JS harness, so pin both halves statically.
class ClientPracticeContentTest < ActionDispatch::IntegrationTest
  RESOURCES_JS = Rails.root.join("app/javascript/controllers/resources_controller.js")
  NAVIGATION_JS = Rails.root.join("app/javascript/controllers/navigation_controller.js")

  test "the layout embeds the client's practice content" do
    practices(:crossroads).resource_links.create!(title: "Crossroads Site", url: "https://crossroadcounselor.com/", description: "About")
    sign_in_as users(:danny)
    get root_path

    assert_select "script#practice-content[type='application/json']", 1
    json = JSON.parse(css_select("script#practice-content").first.text)
    assert_equal "Crossroads Site", json["resources"].first["title"]
    assert_equal "(225) 341-4147", json["schedule"]["phone"]
  end

  test "no counselor content is hardcoded in the client JavaScript" do
    [ RESOURCES_JS, NAVIGATION_JS ].each do |path|
      assert_no_match(/crossroad|therapyportal|225\) 341|logan@/i, path.read, "#{path.basename} still hardcodes Crossroads content")
    end
    assert_match(/practice-content/, RESOURCES_JS.read)
    assert_match(/practice-content/, NAVIGATION_JS.read)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/integration/client_practice_content_test.rb`
Expected: FAIL.

- [ ] **Step 3: Embed the content**

```erb
<%# app/views/shared/_practice_content.html.erb
    The client's counselor's links and booking details, read by the Resources
    and Schedule screens. Content only, never anything about other clients. %>
<script type="application/json" id="practice-content"><%= raw brand.practice_content_json.gsub("</", "<\\/") %></script>
```

In `app/views/layouts/application.html.erb`, add `<%= render "shared/practice_content" %>` right after `<div id="flash-container"></div>`.

- [ ] **Step 4: Resources screen reads it**

Replace the top of `app/javascript/controllers/resources_controller.js` (the `RESOURCES` constant) and `loadFeed` with:

```js
import { Controller } from "@hotwired/stimulus";
import { escapeHtml } from "lib/html";

const GENERIC_RESOURCES = [
  {
    title: "Nothing here yet",
    url: "/",
    description: "Your counselor hasn't added any links. Ask them what they'd like you to have here."
  }
];

function practiceContent() {
  try {
    return JSON.parse(document.getElementById("practice-content")?.textContent || "{}");
  } catch {
    return {};
  }
}

export default class extends Controller {
  static targets = ["feed"];

  connect() {
    this.loadFeed();
  }

  loadFeed() {
    const resources = practiceContent().resources || [];
    const list = resources.length ? resources : GENERIC_RESOURCES;
    this.feedTarget.innerHTML = list.map(resource => `
      <div class="card">
        <h3><a href="${escapeHtml(resource.url)}" target="_blank" rel="noopener">${escapeHtml(resource.title)}</a></h3>
        ${resource.description ? `<p style="font-size:13px;margin-top:8px;">${escapeHtml(resource.description)}</p>` : ""}
      </div>
    `).join("");
  }
}
```

Keep the rest of the file (any helper methods below `loadFeed`) unchanged.

- [ ] **Step 5: Schedule screen reads it**

In `app/javascript/controllers/navigation_controller.js`, replace `appointmentMailto()` and `renderSchedule()` with:

```js
  practiceContent() {
    try {
      return JSON.parse(document.getElementById("practice-content")?.textContent || "{}");
    } catch {
      return {};
    }
  }

  appointmentMailto(email) {
    const subject = "Appointment request";
    const body = [
      "Hi,",
      "",
      "I would like to request an appointment.",
      "",
      "My name is: ",
      "My availability is: ",
      "",
    ].join("\r\n");
    return `mailto:${email}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  }

  renderSchedule() {
    const schedule = this.practiceContent().schedule || {};
    const buttons = [];
    if (schedule.booking_url) {
      buttons.push(`<a href="${escapeHtml(schedule.booking_url)}" target="_blank" rel="noopener" class="link-btn" style="background:var(--blue)">
          🗓️ Book Online
          <small>Use the online scheduling portal</small>
        </a>`);
    }
    if (schedule.phone) {
      const tel = schedule.phone.replace(/[^\d+]/g, "");
      buttons.push(`<a href="tel:${escapeHtml(tel)}" class="link-btn" style="background:var(--orange)">
          📞 Call the Office
          <small>${escapeHtml(schedule.phone)}</small>
        </a>`);
    }
    if (schedule.appointment_email) {
      buttons.push(`<a href="${this.appointmentMailto(schedule.appointment_email)}" class="link-btn" style="background:var(--brown)">
          ✉️ Email
          <small>${escapeHtml(schedule.appointment_email)}</small>
        </a>`);
    }
    const body = buttons.length
      ? `<div class="card">${buttons.join("")}</div>`
      : `<div class="card"><p class="subtitle">Ask your counselor how to book a session.</p></div>`;
    return `
      <h2>Schedule a Session</h2>
      <p class="subtitle">Choose how you'd like to book your next appointment.</p>
      ${body}
      <div class="tip" style="margin-top:16px;">${this.legalDisclaimer()}</div>
    `;
  }
```

Add `import { escapeHtml } from "lib/html";` at the top of the file if it is not already imported. Remove the old "delivers directly to our administrative assistant" sentence: it was Crossroads-specific.

- [ ] **Step 6: Run the tests, commit**

Run: `node --check app/javascript/controllers/resources_controller.js && node --check app/javascript/controllers/navigation_controller.js && bin/rails test test/integration`
Expected: PASS.

```bash
git add app/views/shared/_practice_content.html.erb app/views/layouts/application.html.erb app/javascript/controllers/resources_controller.js app/javascript/controllers/navigation_controller.js test/integration/client_practice_content_test.rb
git commit -m "Resources and Schedule screens render the counselor's own content"
```

### Task T4: Mailers on the product domain, CSP cleanup, last-synced touch

**Files:**
- Modify: `app/mailers/application_mailer.rb`, `app/mailers/invites_mailer.rb`, `app/mailers/passwords_mailer.rb`
- Modify: `app/views/invites_mailer/invite.text.erb`, `app/views/invites_mailer/invite.html.erb`, `app/views/passwords_mailer/reset.text.erb`, `app/views/passwords_mailer/reset.html.erb`
- Modify: `config/initializers/content_security_policy.rb`
- Modify: `app/controllers/api/sync_controller.rb`
- Modify: `test/controllers/api/sync_controller_test.rb`
- Create: `test/mailers/invites_mailer_test.rb`, `test/mailers/passwords_mailer_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/mailers/invites_mailer_test.rb
require "test_helper"

class InvitesMailerTest < ActionMailer::TestCase
  test "invite comes from the product domain with the practice as sender name and links to the practice host" do
    code = InviteCode.generate("client@example.com", counselor: counselors(:logan))
    mail = InvitesMailer.invite(code)

    assert_equal [ "client@example.com" ], mail.to
    assert_equal [ "no-reply@example.com" ], mail.from
    assert_match(/Crossroads Professional Counseling/, mail[:from].display_names.first)
    assert_match(/Crossroads Professional Counseling/, mail.subject)
    assert_match %r{https://app\.crossroadcounselor\.com/users/new\?code=#{code.code}}, mail.text_part.body.to_s
  end
end
```

```ruby
# test/mailers/passwords_mailer_test.rb
require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset link uses the client's practice host" do
    mail = PasswordsMailer.reset(users(:danny))
    assert_match %r{https://app\.crossroadcounselor\.com/passwords/}, mail.text_part.body.to_s
    assert_equal [ "no-reply@example.com" ], mail.from
  end
end
```

Add to `test/controllers/api/sync_controller_test.rb`:

```ruby
  test "a successful save records that the client synced" do
    user = users(:danny)
    sign_in_as user
    put api_sync_path, params: { blob: { ciphertext: "cipher", nonce: "nonce" } }, as: :json
    assert_response :success
    assert_in_delta Time.current, user.reload.last_synced_at, 5.seconds
  end

  test "a rejected save does not record a sync" do
    user = users(:danny)
    sign_in_as user
    put api_sync_path, params: { blob: { ciphertext: "", nonce: "nonce" } }, as: :json
    assert_response :unprocessable_entity
    assert_nil user.reload.last_synced_at
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/mailers test/controllers/api/sync_controller_test.rb`
Expected: FAIL (from-address, subject, host, missing touch).

- [ ] **Step 3: Mailers**

```ruby
# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  private

  # Mail is sent from the product domain (one Mailgun domain for everyone);
  # the practice shows up as the display name and in links.
  def from_for(brand)
    email_address_with_name("no-reply@#{Rails.application.config.x.product_host}", brand.name)
  end
end
```

```ruby
# app/mailers/invites_mailer.rb
class InvitesMailer < ApplicationMailer
  def invite(code)
    @code = code
    @brand = Brand.new(code.counselor.practice)
    @signup_url = new_user_url(code: code.code, host: @brand.host, protocol: "https")
    mail to: code.email_address, from: from_for(@brand), subject: "Your invite to #{@brand.name}"
  end
end
```

```ruby
# app/mailers/passwords_mailer.rb
class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @brand = Brand.new(user.counselor.practice)
    @reset_url = edit_password_url(user.password_reset_token, host: @brand.host, protocol: "https")
    mail to: user.email_address, from: from_for(@brand), subject: "Reset your #{@brand.name} password"
  end
end
```

`app/views/invites_mailer/invite.text.erb`:

```erb
Here is your invite code for <%= @brand.name %>:

<%= @code.code %>

Use it to create your account:
<%= @signup_url %>

This code can only be used once. If you did not request it, you can safely ignore this email.
```

Mirror the same wording in `invite.html.erb` with the link as an anchor. In both `reset` templates replace `edit_password_url(@user.password_reset_token)` with `@reset_url`.

- [ ] **Step 4: CSP and sync touch**

In `config/initializers/content_security_policy.rb` change `policy.connect_src :self, "https://crossroadcounselor.com"` to `policy.connect_src :self`.

In `app/controllers/api/sync_controller.rb`, in `save_blob`, change the success branch to:

```ruby
    if blob.update(blob_params)
      current_user.touch_last_synced!
      render json: { success: true }
```

- [ ] **Step 5: Run the tests, commit**

Run: `bin/rails test test/mailers test/controllers/api test/integration/content_security_policy_test.rb`
Expected: PASS. If the CSP test pins the Crossroads connect entry, update it to expect `connect-src 'self'` only.

```bash
git add app/mailers app/views/invites_mailer app/views/passwords_mailer config/initializers/content_security_policy.rb app/controllers/api/sync_controller.rb test/mailers test/controllers/api/sync_controller_test.rb test/integration/content_security_policy_test.rb
git commit -m "Mail from the product domain with practice links, drop Crossroads CSP entry, record syncs"
```

### Task T5: Report done

Run `bin/rails test && bin/rubocop`, then tell the driver Lane T is complete with the list of commits and anything you deviated on.

---

## Lane C — counselor auth and dashboard (codex)

URL paths live under `/counselor/...` but the Ruby module is `Dashboard`
(routes use `namespace :counselor, module: "dashboard"`) so controllers
never collide with the `Counselor` model constant. Route helpers are
`counselor_*`. Only touch the files Lane C owns. Every page reads branding
from `brand`. Run `bin/rails test` before each commit.

### Task C1: Counselor authentication, base controller, login, layout

**Files:**
- Create: `app/controllers/concerns/counselor_authentication.rb`
- Create: `app/controllers/dashboard/base_controller.rb`
- Create: `app/controllers/dashboard/sessions_controller.rb`
- Create: `app/views/dashboard/sessions/new.html.erb`
- Create: `app/views/layouts/counselor.html.erb`
- Create: `app/assets/stylesheets/counselor.css`
- Create: `test/controllers/dashboard/sessions_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/dashboard/sessions_controller_test.rb
require "test_helper"

class Dashboard::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "login page renders on any host with that host's brand" do
    host! "app.crossroadcounselor.com"
    get new_counselor_session_path
    assert_response :success
    assert_select "title", /Crossroads/
  end

  test "valid login starts a counselor session and lands on the dashboard" do
    sign_in_counselor_as counselors(:logan)
    assert_redirected_to counselor_root_path
    get counselor_root_path
    assert_response :success
    assert cookies[:counselor_session_id].present?
    assert_nil cookies[:session_id], "counselor login must not create a client session"
  end

  test "wrong password is rejected" do
    sign_in_counselor_as counselors(:logan), password: "nope nope nope"
    assert_redirected_to new_counselor_session_path
    get counselor_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "a removed counselor cannot log in and an existing session dies" do
    sign_in_counselor_as counselors(:jo)
    counselors(:jo).remove!
    get counselor_root_path
    assert_redirected_to new_counselor_session_path

    sign_in_counselor_as counselors(:jo)
    assert_redirected_to new_counselor_session_path
  end

  test "logout ends the session" do
    sign_in_counselor_as counselors(:logan)
    delete counselor_session_path
    assert_response :see_other
    get counselor_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "dashboard pages are never cached" do
    sign_in_counselor_as counselors(:logan)
    get counselor_root_path
    assert_match(/no-store/, response.headers["Cache-Control"])
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/dashboard/sessions_controller_test.rb`
Expected: FAIL, `uninitialized constant Dashboard::SessionsController`.

- [ ] **Step 3: The concern**

```ruby
# app/controllers/concerns/counselor_authentication.rb
#
# Counselor login, kept apart from the client Authentication concern: a
# separate cookie and session table so one browser can hold both a client
# and a counselor login without either leaking into the other.
module CounselorAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_counselor
    helper_method :current_counselor, :counselor_signed_in?
  end

  class_methods do
    def allow_unauthenticated_counselor_access(**options)
      skip_before_action :require_counselor, **options
    end
  end

  private
    def counselor_signed_in?
      resume_counselor_session.present?
    end

    def current_counselor
      Current.counselor
    end

    def require_counselor
      resume_counselor_session || redirect_to(new_counselor_session_path)
    end

    def require_owner
      return if current_counselor.owner?
      redirect_to counselor_root_path, alert: "Only the practice owner can do that."
    end

    def resume_counselor_session
      Current.counselor_session ||= find_counselor_session_by_cookie
    end

    # A removed counselor's sessions are destroyed by remove!, but check
    # anyway so a race can't keep them logged in.
    def find_counselor_session_by_cookie
      id = cookies.signed[:counselor_session_id]
      return unless id
      session = CounselorSession.active.find_by(id: id)
      session if session && !session.counselor.removed?
    end

    def start_new_counselor_session_for(counselor)
      counselor.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.counselor_session = session
        cookies.signed.permanent[:counselor_session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_counselor_session
      Current.counselor_session&.destroy
      cookies.delete(:counselor_session_id)
    end
end
```

- [ ] **Step 4: Base controller and sessions**

```ruby
# app/controllers/dashboard/base_controller.rb
class Dashboard::BaseController < ApplicationController
  include CounselorAuthentication
  # These pages are for counselors; the client login is irrelevant here.
  allow_unauthenticated_access
  layout "counselor"
  before_action :set_no_cache_headers

  private

  # A counselor's pages always wear their own practice, whatever host they
  # came in on. Before login, the host's practice or the generic brand.
  def brand
    @brand ||= Brand.new(current_counselor&.practice || Current.practice)
  end

  def set_no_cache_headers
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"
  end
end
```

```ruby
# app/controllers/dashboard/sessions_controller.rb
class Dashboard::SessionsController < Dashboard::BaseController
  allow_unauthenticated_counselor_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_counselor_session_path, alert: "Try again later." }

  def new
    redirect_to counselor_root_path if counselor_signed_in?
  end

  def create
    counselor = Counselor.active.authenticate_by(params.permit(:email_address, :password))
    if counselor
      start_new_counselor_session_for counselor
      redirect_to counselor_root_path
    else
      redirect_to new_counselor_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_counselor_session
    redirect_to new_counselor_session_path, status: :see_other
  end
end
```

- [ ] **Step 5: Layout, stylesheet, login view**

```erb
<%# app/views/layouts/counselor.html.erb %>
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= render "shared/brand_head", page: content_for(:title) || "Counselor" %>
    <link href="https://fonts.googleapis.com/css2?family=Lora:ital,wght@0,400;0,600;0,700;1,400&family=Open+Sans:wght@400;600;700&display=swap" rel="stylesheet">
    <%= stylesheet_link_tag "application", "counselor" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="counselor">
    <header class="c-header">
      <div class="c-brand">
        <% if brand.logo %>
          <%= image_tag url_for(brand.logo.variant(resize_to_limit: [ 160, 48 ])), alt: brand.name, class: "c-logo" %>
        <% else %>
          <span class="c-mark"><%= brand.name %></span>
        <% end %>
        <span class="c-sub">Counselor</span>
      </div>
      <% if counselor_signed_in? %>
        <nav class="c-nav">
          <%= link_to "Clients", counselor_root_path %>
          <%= link_to "Invites", counselor_invites_path %>
          <% if current_counselor.owner? %>
            <%= link_to "Practice", edit_counselor_practice_path %>
            <%= link_to "Members", counselor_members_path %>
          <% end %>
          <% if current_counselor.platform_admin? %>
            <%= link_to "Platform", platform_root_path %>
          <% end %>
          <%= link_to "Account", edit_counselor_account_path %>
          <%= button_to "Log out", counselor_session_path, method: :delete, class: "c-linkbtn" %>
        </nav>
      <% end %>
    </header>
    <main class="c-main">
      <%= tag.div(flash[:alert], class: "form-error") if flash[:alert] %>
      <%= tag.div(flash[:notice], class: "form-notice") if flash[:notice] %>
      <%= yield %>
    </main>
  </body>
</html>
```

Note: `shared/_brand_head` is Lane T's file. If it hasn't landed yet, the layout errors until it does; that is expected in the shared checkout and resolves when T2 commits.

```css
/* app/assets/stylesheets/counselor.css */
body.counselor{background:var(--bg);color:var(--brown);max-width:none}
.c-header{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:12px 20px;background:var(--white);border-bottom:1px solid var(--light-blue);flex-wrap:wrap}
.c-brand{display:flex;align-items:baseline;gap:10px}
.c-mark{font-family:'Lora',serif;font-size:18px;letter-spacing:1px;color:var(--brown)}
.c-logo{max-height:48px}
.c-sub{font-size:11px;letter-spacing:1.5px;color:var(--lt-brown);text-transform:uppercase}
.c-nav{display:flex;gap:14px;align-items:center;flex-wrap:wrap;font-size:14px}
.c-nav a{color:var(--deep);font-weight:600;text-decoration:none}
.c-nav a:hover{text-decoration:underline}
.c-linkbtn{background:none;border:none;color:var(--lt-brown);font:inherit;font-weight:600;cursor:pointer;padding:0}
.c-main{max-width:900px;margin:0 auto;padding:20px}
.c-main h2{font-family:'Lora',serif;margin-bottom:6px}
.c-table{width:100%;border-collapse:collapse;background:var(--white);border-radius:8px;overflow:hidden;font-size:14px}
.c-table th,.c-table td{text-align:left;padding:10px 12px;border-bottom:1px solid var(--light-blue);vertical-align:middle}
.c-table th{font-size:12px;color:var(--lt-brown);text-transform:uppercase;letter-spacing:.5px}
.c-muted{color:var(--lt-brown);font-size:12px}
.c-row{display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap}
.c-row .field{flex:1;min-width:200px}
.c-inline{display:inline}
.c-code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:18px;letter-spacing:2px}
.c-swatch{display:inline-block;width:18px;height:18px;border-radius:4px;vertical-align:middle;border:1px solid rgba(0,0,0,.1)}
.c-preview{border:1px solid var(--light-blue);border-radius:8px;padding:14px;background:var(--white);margin-top:12px}
.c-preview .topbar{border-radius:6px}
.c-count{font-size:13px;color:var(--deep);margin-bottom:12px}
.c-links-row{display:grid;grid-template-columns:1fr 1fr 1fr auto auto;gap:8px;align-items:center;margin-bottom:8px}
details.c-archived summary{cursor:pointer;color:var(--lt-brown);margin:16px 0 8px}
```

```erb
<%# app/views/dashboard/sessions/new.html.erb %>
<% content_for :title, "Counselor sign in" %>
<div class="auth-screen" style="max-width:360px;margin:40px auto;">
  <h2>Counselor sign in</h2>
  <p class="subtitle">Manage your clients, invites, and practice.</p>

  <%= form_with url: counselor_session_path do |form| %>
    <div class="field">
      <%= form.label :email_address, "Email" %>
      <%= form.email_field :email_address, required: true, autofocus: true, autocomplete: "username", placeholder: "you@practice.com" %>
    </div>
    <div class="field">
      <%= form.label :password, "Password" %>
      <%= form.password_field :password, required: true, autocomplete: "current-password", placeholder: "Your password" %>
    </div>
    <div class="actions">
      <%= form.submit "Sign in", class: "btn" %>
    </div>
  <% end %>

  <p class="auth-alt"><%= link_to "Forgot your password?", new_counselor_password_path %></p>
</div>
```

- [ ] **Step 6: Run the tests, commit**

Run: `bin/rails test test/controllers/dashboard/sessions_controller_test.rb`
Expected: PASS (the `counselor_root_path` GET needs `Dashboard::ClientsController` from C4; until then that one assertion errors. Mark the two tests that GET the root with `skip "needs C4"` and remove the skips in C4.)

```bash
git add app/controllers/concerns/counselor_authentication.rb app/controllers/dashboard/base_controller.rb app/controllers/dashboard/sessions_controller.rb app/views/dashboard/sessions app/views/layouts/counselor.html.erb app/assets/stylesheets/counselor.css test/controllers/dashboard/sessions_controller_test.rb
git commit -m "Counselor login with its own session and layout"
```

### Task C2: Counselor password reset

**Files:**
- Create: `app/controllers/dashboard/passwords_controller.rb`
- Create: `app/views/dashboard/passwords/new.html.erb`, `app/views/dashboard/passwords/edit.html.erb`
- Create: `app/mailers/counselor_passwords_mailer.rb`
- Create: `app/views/counselor_passwords_mailer/reset.text.erb`, `app/views/counselor_passwords_mailer/reset.html.erb`
- Create: `test/controllers/dashboard/passwords_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/dashboard/passwords_controller_test.rb
require "test_helper"

class Dashboard::PasswordsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "requesting a reset emails a link on the practice host" do
    assert_enqueued_emails 1 do
      post counselor_passwords_path, params: { email_address: counselors(:logan).email_address }
    end
    assert_redirected_to new_counselor_session_path
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_match %r{https://app\.crossroadcounselor\.com/counselor/passwords/.+/edit}, mail.text_part.body.to_s
  end

  test "unknown emails get the same response and no mail" do
    assert_no_enqueued_emails do
      post counselor_passwords_path, params: { email_address: "nobody@example.com" }
    end
    assert_redirected_to new_counselor_session_path
  end

  test "resetting sets the password, revokes sessions, and redirects to login" do
    counselor = counselors(:logan)
    sign_in_counselor_as counselor
    token = counselor.password_reset_token

    patch counselor_password_path(token), params: { password: "brand new password 1", password_confirmation: "brand new password 1" }

    assert_redirected_to new_counselor_session_path
    assert_equal 0, counselor.sessions.count
    assert Counselor.authenticate_by(email_address: counselor.email_address, password: "brand new password 1")
  end

  test "short or mismatched passwords are rejected" do
    counselor = counselors(:logan)
    token = counselor.password_reset_token
    digest = counselor.password_digest

    patch counselor_password_path(token), params: { password: "short", password_confirmation: "short" }
    assert_redirected_to edit_counselor_password_path(token)
    patch counselor_password_path(token), params: { password: "long enough password", password_confirmation: "different password!" }
    assert_redirected_to edit_counselor_password_path(token)
    assert_equal digest, counselor.reload.password_digest
  end

  test "a bad token is refused" do
    get edit_counselor_password_path("bogus")
    assert_redirected_to new_counselor_password_path
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/dashboard/passwords_controller_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/dashboard/passwords_controller.rb
class Dashboard::PasswordsController < Dashboard::BaseController
  allow_unauthenticated_counselor_access
  before_action :set_counselor_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_counselor_password_path, alert: "Try again later." }

  def new
  end

  def create
    if (counselor = Counselor.active.find_by(email_address: params[:email_address]))
      CounselorPasswordsMailer.reset(counselor).deliver_later
    end
    redirect_to new_counselor_session_path, notice: "Password reset instructions sent (if that email has a counselor account)."
  end

  def edit
  end

  def update
    if params[:password].blank?
      return redirect_to edit_counselor_password_path(params[:token]), alert: "Password can't be blank."
    end

    if @counselor.update(params.permit(:password, :password_confirmation))
      @counselor.sessions.destroy_all
      redirect_to new_counselor_session_path, notice: "Password has been reset."
    else
      redirect_to edit_counselor_password_path(params[:token]), alert: @counselor.errors.full_messages.to_sentence
    end
  end

  private
    def set_counselor_by_token
      @counselor = Counselor.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_counselor_password_path, alert: "Password reset link is invalid or has expired."
    end
end
```

```ruby
# app/mailers/counselor_passwords_mailer.rb
class CounselorPasswordsMailer < ApplicationMailer
  def reset(counselor)
    @counselor = counselor
    @brand = Brand.new(counselor.practice)
    @reset_url = edit_counselor_password_url(counselor.password_reset_token, host: @brand.host, protocol: "https")
    mail to: counselor.email_address, from: from_for(@brand), subject: "Reset your counselor password"
  end
end
```

`app/views/counselor_passwords_mailer/reset.text.erb`:

```erb
You can reset your counselor password on
<%= @reset_url %>

This link will expire in <%= distance_of_time_in_words(0, @counselor.password_reset_token_expires_in) %>.
```

`reset.html.erb`: the same two sentences with the URL as a link.

`app/views/dashboard/passwords/new.html.erb`:

```erb
<% content_for :title, "Forgot password" %>
<div class="auth-screen" style="max-width:360px;margin:40px auto;">
  <h2>Forgot your password?</h2>
  <p class="subtitle">We'll email you a link to set a new one.</p>
  <%= form_with url: counselor_passwords_path do |form| %>
    <div class="field">
      <%= form.label :email_address, "Email" %>
      <%= form.email_field :email_address, required: true, autofocus: true, autocomplete: "username" %>
    </div>
    <div class="actions"><%= form.submit "Email reset instructions", class: "btn" %></div>
  <% end %>
  <p class="auth-alt"><%= link_to "Back to sign in", new_counselor_session_path %></p>
</div>
```

`app/views/dashboard/passwords/edit.html.erb`:

```erb
<% content_for :title, "Set a new password" %>
<div class="auth-screen" style="max-width:360px;margin:40px auto;">
  <h2>Set a new password</h2>
  <p class="subtitle">At least <%= Counselor::MINIMUM_PASSWORD_LENGTH %> characters.</p>
  <%= form_with url: counselor_password_path(params[:token]), method: :patch do |form| %>
    <div class="field">
      <%= form.label :password, "New password" %>
      <%= form.password_field :password, required: true, autocomplete: "new-password", minlength: Counselor::MINIMUM_PASSWORD_LENGTH %>
    </div>
    <div class="field">
      <%= form.label :password_confirmation, "Confirm password" %>
      <%= form.password_field :password_confirmation, required: true, autocomplete: "new-password" %>
    </div>
    <div class="actions"><%= form.submit "Save password", class: "btn" %></div>
  <% end %>
</div>
```

- [ ] **Step 4: Run the tests, commit**

Run: `bin/rails test test/controllers/dashboard/passwords_controller_test.rb`
Expected: PASS.

```bash
git add app/controllers/dashboard/passwords_controller.rb app/views/dashboard/passwords app/mailers/counselor_passwords_mailer.rb app/views/counselor_passwords_mailer test/controllers/dashboard/passwords_controller_test.rb
git commit -m "Counselor password reset"
```

### Task C3: Accepting a counselor invite (setup) and the invite mailer

**Files:**
- Create: `app/controllers/dashboard/setups_controller.rb`
- Create: `app/views/dashboard/setups/show.html.erb`, `app/views/dashboard/setups/invalid.html.erb`
- Create: `app/mailers/counselor_invites_mailer.rb`
- Create: `app/views/counselor_invites_mailer/invite.text.erb`, `app/views/counselor_invites_mailer/invite.html.erb`
- Create: `test/controllers/dashboard/setups_controller_test.rb`, `test/mailers/counselor_invites_mailer_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/dashboard/setups_controller_test.rb
require "test_helper"

class Dashboard::SetupsControllerTest < ActionDispatch::IntegrationTest
  test "an owner invite shows the setup form with the new practice name" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")
    get counselor_setup_path(invite.token)
    assert_response :success
    assert_select "h2", /Calm Waters/
    assert_select "input[name=name]"
    assert_select "input[name=password]"
  end

  test "accepting an owner invite creates the practice and lands on its dashboard host" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")

    assert_difference [ -> { Practice.count }, -> { Counselor.count } ], 1 do
      post counselor_setup_path(invite.token), params: { name: "Pat", password: "long enough password" }
    end

    assert_redirected_to counselor_root_url(host: "calm-waters.example.com", protocol: "https")
    assert invite.reload.accepted?
    assert cookies[:counselor_session_id].present?
  end

  test "accepting a member invite joins the practice" do
    invite = CounselorInvite.create!(email_address: "kim@example.com", role: "member", practice: practices(:riverbend), invited_by: counselors(:sam))
    post counselor_setup_path(invite.token), params: { name: "Kim", password: "long enough password" }
    assert_redirected_to counselor_root_url(host: "riverbend.example.com", protocol: "https")
    assert_equal practices(:riverbend), Counselor.find_by(email_address: "kim@example.com").practice
  end

  test "validation errors re-render the form and create nothing" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")
    assert_no_difference -> { Practice.count } do
      post counselor_setup_path(invite.token), params: { name: "", password: "short" }
    end
    assert_response :unprocessable_entity
    assert_match(/Password is too short/, response.body)
  end

  test "expired, accepted, and unknown tokens show a clear message" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")
    invite.update_column(:expires_at, 1.hour.ago)
    get counselor_setup_path(invite.token)
    assert_response :not_found
    assert_match(/expired/i, response.body)

    get counselor_setup_path("bogus")
    assert_response :not_found
  end
end
```

```ruby
# test/mailers/counselor_invites_mailer_test.rb
require "test_helper"

class CounselorInvitesMailerTest < ActionMailer::TestCase
  test "member invite links to the practice host" do
    invite = CounselorInvite.create!(email_address: "kim@example.com", role: "member", practice: practices(:crossroads), invited_by: counselors(:logan))
    mail = CounselorInvitesMailer.invite(invite)
    assert_equal [ "kim@example.com" ], mail.to
    assert_match %r{https://app\.crossroadcounselor\.com/counselor/setup/#{invite.token}}, mail.text_part.body.to_s
    assert_match(/Crossroads Professional Counseling/, mail.subject)
  end

  test "owner invite for a new practice links to the product host" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")
    mail = CounselorInvitesMailer.invite(invite)
    assert_match %r{https://example\.com/counselor/setup/#{invite.token}}, mail.text_part.body.to_s
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/dashboard/setups_controller_test.rb test/mailers/counselor_invites_mailer_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/dashboard/setups_controller.rb
#
# Where a counselor invite becomes a counselor: the setup link from a
# platform (owner) or member invite lands here.
class Dashboard::SetupsController < Dashboard::BaseController
  allow_unauthenticated_counselor_access
  before_action :set_invite

  def show
  end

  def create
    counselor = @invite.accept!(name: params[:name].to_s, password: params[:password].to_s)
    start_new_counselor_session_for counselor
    redirect_to counselor_root_url(host: counselor.practice.host, protocol: "https"), allow_other_host: true
  rescue ActiveRecord::RecordInvalid => e
    @errors = e.record.errors.full_messages
    render :show, status: :unprocessable_entity
  end

  private

  def set_invite
    @invite = CounselorInvite.find_by(token: params[:token])
    return if @invite&.usable?

    @reason = if @invite.nil? then "This invite link isn't valid."
              elsif @invite.accepted? then "This invite has already been used."
              else "This invite has expired. Ask for a new one."
              end
    render :invalid, status: :not_found
  end

  def brand
    @brand ||= Brand.new(@invite&.practice || Current.practice)
  end
end
```

```ruby
# app/mailers/counselor_invites_mailer.rb
class CounselorInvitesMailer < ApplicationMailer
  def invite(invite)
    @invite = invite
    @brand = Brand.new(invite.practice)
    @setup_url = counselor_setup_url(invite.token, host: @brand.host, protocol: "https")
    subject = invite.practice ? "You're invited to join #{@brand.name}" : "Set up #{invite.practice_name} on #{@brand.product_name}"
    mail to: invite.email_address, from: from_for(@brand), subject: subject
  end
end
```

`app/views/counselor_invites_mailer/invite.text.erb`:

```erb
<% if @invite.practice %>You've been invited to join <%= @brand.name %> as a counselor.<% else %>You've been invited to set up <%= @invite.practice_name %> on <%= @brand.product_name %>.<% end %>

Finish setting up your account here:
<%= @setup_url %>

This link expires in 7 days.
```

`invite.html.erb`: the same with the URL as a link.

`app/views/dashboard/setups/show.html.erb`:

```erb
<% content_for :title, "Set up your account" %>
<div class="auth-screen" style="max-width:420px;margin:40px auto;">
  <h2><%= @invite.practice ? "Join #{@invite.practice_display_name}" : "Set up #{@invite.practice_display_name}" %></h2>
  <p class="subtitle">You're joining as <%= @invite.role %>. Your email is <%= @invite.email_address %>.</p>
  <% if @errors %><div class="form-error"><%= @errors.to_sentence %></div><% end %>

  <%= form_with url: counselor_setup_path(@invite.token), method: :post do |form| %>
    <div class="field">
      <%= form.label :name, "Your name" %>
      <%= form.text_field :name, required: true, autofocus: true, value: params[:name] %>
    </div>
    <div class="field">
      <%= form.label :password, "Password (at least #{Counselor::MINIMUM_PASSWORD_LENGTH} characters)" %>
      <%= form.password_field :password, required: true, autocomplete: "new-password", minlength: Counselor::MINIMUM_PASSWORD_LENGTH %>
    </div>
    <div class="actions"><%= form.submit "Create my account", class: "btn" %></div>
  <% end %>
</div>
```

`app/views/dashboard/setups/invalid.html.erb`:

```erb
<% content_for :title, "Invite not valid" %>
<div class="auth-screen" style="max-width:420px;margin:40px auto;">
  <h2>Invite not valid</h2>
  <p class="subtitle"><%= @reason %></p>
</div>
```

- [ ] **Step 4: Run the tests, commit**

Run: `bin/rails test test/controllers/dashboard/setups_controller_test.rb test/mailers/counselor_invites_mailer_test.rb`
Expected: PASS.

```bash
git add app/controllers/dashboard/setups_controller.rb app/views/dashboard/setups app/mailers/counselor_invites_mailer.rb app/views/counselor_invites_mailer test/controllers/dashboard/setups_controller_test.rb test/mailers/counselor_invites_mailer_test.rb
git commit -m "Accept counselor invites: create the practice or join it"
```

### Task C4: Clients list with archive and reactivate

**Files:**
- Create: `app/controllers/dashboard/clients_controller.rb`
- Create: `app/views/dashboard/clients/index.html.erb`
- Create: `test/controllers/dashboard/clients_controller_test.rb`
- Modify: `test/controllers/dashboard/sessions_controller_test.rb` (remove the C1 skips)

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/dashboard/clients_controller_test.rb
require "test_helper"

class Dashboard::ClientsControllerTest < ActionDispatch::IntegrationTest
  test "requires a counselor login" do
    get counselor_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "lists only the counselor's own clients with last-active and the practice count" do
    users(:danny).update_columns(last_synced_at: 2.days.ago)
    sign_in_counselor_as counselors(:logan)
    get counselor_root_path

    assert_response :success
    assert_select "td", text: "danny@example.com"
    assert_select "td", text: "maria@example.com", count: 0
    assert_select "td", text: "2 days ago"
    assert_select ".c-count", /2 of 60 active this month/
  end

  test "archive hides the client from the active list and reactivate restores them" do
    sign_in_counselor_as counselors(:logan)
    patch archive_counselor_client_path(users(:danny))
    assert_redirected_to counselor_root_path
    assert users(:danny).reload.archived?

    get counselor_root_path
    assert_select "details.c-archived td", text: "danny@example.com"

    patch unarchive_counselor_client_path(users(:danny))
    assert_not users(:danny).reload.archived?
  end

  test "a counselor cannot archive another counselor's client" do
    sign_in_counselor_as counselors(:logan)
    patch archive_counselor_client_path(users(:maria))
    assert_response :not_found
    assert_not users(:maria).reload.archived?
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/dashboard/clients_controller_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/dashboard/clients_controller.rb
class Dashboard::ClientsController < Dashboard::BaseController
  before_action :set_client, only: %i[ archive unarchive ]

  # Only this counselor's clients, ever. The practice-wide number is a count,
  # never a list: the owner sees how many, not who.
  def index
    clients = current_counselor.clients.order(created_at: :desc)
    @active = clients.unarchived
    @archived = clients.archived
    @practice = current_counselor.practice
  end

  def archive
    @client.archive!
    redirect_to counselor_root_path, notice: "Archived. They keep full access to the app."
  end

  def unarchive
    @client.unarchive!
    redirect_to counselor_root_path, notice: "Reactivated."
  end

  private

  def set_client
    @client = current_counselor.clients.find(params[:id])
  end
end
```

```erb
<%# app/views/dashboard/clients/index.html.erb %>
<% content_for :title, "Clients" %>
<h2>Clients</h2>
<p class="c-count"><%= @practice.active_client_count %> of <%= @practice.client_limit %> active this month across the practice.</p>

<% if @active.empty? %>
  <p class="subtitle">No clients yet. <%= link_to "Create an invite", counselor_invites_path %> to get started.</p>
<% else %>
  <table class="c-table">
    <thead><tr><th>Email</th><th>Joined</th><th>Last active</th><th></th></tr></thead>
    <tbody>
      <% @active.each do |client| %>
        <tr>
          <td><%= client.email_address %></td>
          <td><%= client.created_at.to_date %></td>
          <td><%= client.last_synced_at ? "#{time_ago_in_words(client.last_synced_at)} ago" : "never" %></td>
          <td><%= button_to "Archive", archive_counselor_client_path(client), method: :patch, class: "c-linkbtn", form_class: "c-inline" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>

<% if @archived.any? %>
  <details class="c-archived">
    <summary><%= @archived.size %> archived</summary>
    <table class="c-table">
      <tbody>
        <% @archived.each do |client| %>
          <tr>
            <td><%= client.email_address %></td>
            <td class="c-muted">archived <%= client.archived_at.to_date %></td>
            <td><%= button_to "Reactivate", unarchive_counselor_client_path(client), method: :patch, class: "c-linkbtn", form_class: "c-inline" %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </details>
<% end %>
```

Note: `time_ago_in_words(2.days.ago)` renders "2 days"; the test expects "2 days ago", which the view produces. Remove the `skip "needs C4"` lines from the sessions test.

- [ ] **Step 4: Run the tests, commit**

Run: `bin/rails test test/controllers/dashboard`
Expected: PASS.

```bash
git add app/controllers/dashboard/clients_controller.rb app/views/dashboard/clients test/controllers/dashboard/clients_controller_test.rb test/controllers/dashboard/sessions_controller_test.rb
git commit -m "Counselor client list with archive and reactivate"
```

### Task C5: Client invites with the active-client limit

**Files:**
- Create: `app/controllers/dashboard/invites_controller.rb`
- Create: `app/views/dashboard/invites/index.html.erb`
- Create: `test/controllers/dashboard/invites_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/dashboard/invites_controller_test.rb
require "test_helper"

class Dashboard::InvitesControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { sign_in_counselor_as counselors(:logan) }

  test "creating an invite without an email shows the link and code, sends nothing" do
    assert_no_enqueued_emails do
      assert_difference -> { counselors(:logan).invite_codes.count }, 1 do
        post counselor_invites_path, params: { invite: { email_address: "" } }
      end
    end
    code = counselors(:logan).invite_codes.order(:created_at).last
    assert_redirected_to counselor_invites_path(highlight: code.id)
    follow_redirect!
    assert_select ".c-code", text: code.code
    assert_select "input[value=?]", "https://app.crossroadcounselor.com/users/new?code=#{code.code}"
  end

  test "creating an invite with an email also sends it" do
    assert_enqueued_emails 1 do
      post counselor_invites_path, params: { invite: { email_address: "new@example.com" } }
    end
  end

  test "at the limit no code is made and the message explains" do
    practices(:crossroads).update!(client_limit_per_counselor: 1)
    users(:danny).update_columns(last_synced_at: 1.hour.ago)
    users(:maria).update_columns(last_synced_at: 1.hour.ago)

    assert_no_difference -> { InviteCode.count } do
      post counselor_invites_path, params: { invite: { email_address: "" } }
    end
    assert_response :unprocessable_entity
    assert_match(/2 active clients this month, which is your limit/, response.body)
  end

  test "the list shows status and only this counselor's codes" do
    used = InviteCode.generate("gone@example.com", counselor: counselors(:logan))
    InviteCode.claim(used.code)
    used.update!(user: users(:danny))
    InviteCode.generate(nil, counselor: counselors(:jo))

    get counselor_invites_path
    assert_select "td", text: used.code
    assert_select "td", text: /used by danny@example.com/
    assert_select "tbody tr", count: 1 + counselors(:logan).invite_codes.where(used: false).count
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/dashboard/invites_controller_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/dashboard/invites_controller.rb
class Dashboard::InvitesController < Dashboard::BaseController
  def index
    load_index
  end

  # The one place the client limit is enforced. Nothing else ever blocks a
  # client; a practice over its limit simply cannot add more until people go
  # quiet or a seat is added.
  def create
    practice = current_counselor.practice
    if practice.at_client_limit?
      load_index
      flash.now[:alert] = "Your practice has #{practice.active_client_count} active clients this month, which is your limit. " \
                          "Wait for clients to go quiet or add a counselor seat."
      return render :index, status: :unprocessable_entity
    end

    code = InviteCode.generate(invite_params[:email_address].presence, counselor: current_counselor)
    InvitesMailer.invite(code).deliver_later if code.email_address.present?
    redirect_to counselor_invites_path(highlight: code.id), notice: "Invite created. Share the link or code with your client."
  end

  private

  def load_index
    @codes = current_counselor.invite_codes.includes(:user).order(created_at: :desc)
    @highlight = @codes.find_by(id: params[:highlight])
    @practice = current_counselor.practice
  end

  def invite_params
    params.fetch(:invite, {}).permit(:email_address)
  end

  helper_method def signup_link(code)
    new_user_url(code: code.code, host: current_counselor.practice.host, protocol: "https")
  end
end
```

```erb
<%# app/views/dashboard/invites/index.html.erb %>
<% content_for :title, "Invites" %>
<h2>Invites</h2>
<p class="c-count"><%= @practice.active_client_count %> of <%= @practice.client_limit %> active this month.</p>

<% if @highlight %>
  <div class="card" data-controller="clipboard">
    <p class="subtitle">Send this link to your client. Text works best.</p>
    <input type="text" readonly value="<%= signup_link(@highlight) %>" data-clipboard-target="source">
    <button type="button" class="btn btn-o" style="margin-top:8px;" data-clipboard-target="button" data-action="click->clipboard#copy">Copy link</button>
    <p class="subtitle" style="margin-top:12px;">Or give them the code: <span class="c-code"><%= @highlight.code %></span></p>
  </div>
<% end %>

<div class="card">
  <%= form_with url: counselor_invites_path, scope: :invite, class: "c-row" do |form| %>
    <div class="field">
      <%= form.label :email_address, "Client email (optional, to send the invite by email)" %>
      <%= form.email_field :email_address, placeholder: "client@example.com" %>
    </div>
    <div><%= form.submit "New invite", class: "btn" %></div>
  <% end %>
</div>

<table class="c-table">
  <thead><tr><th>Code</th><th>Email</th><th>Status</th><th>Created</th></tr></thead>
  <tbody>
    <% @codes.each do |code| %>
      <tr>
        <td><%= code.code %></td>
        <td><%= code.email_address.presence || "—" %></td>
        <td><%= code.used? ? "used by #{code.user&.email_address || 'a client'}" : "pending" %></td>
        <td class="c-muted"><%= code.created_at.to_date %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

- [ ] **Step 4: Run the tests, commit**

Run: `bin/rails test test/controllers/dashboard/invites_controller_test.rb`
Expected: PASS.

```bash
git add app/controllers/dashboard/invites_controller.rb app/views/dashboard/invites test/controllers/dashboard/invites_controller_test.rb
git commit -m "Client invites with a shareable link and the active-client limit"
```

### Task C6: Practice settings (owner): brand, profile, resource links, live preview

**Files:**
- Create: `app/controllers/dashboard/practices_controller.rb`
- Create: `app/views/dashboard/practices/edit.html.erb`
- Create: `app/javascript/controllers/brand_preview_controller.js`
- Create: `test/controllers/dashboard/practices_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/dashboard/practices_controller_test.rb
require "test_helper"

class Dashboard::PracticesControllerTest < ActionDispatch::IntegrationTest
  test "members cannot open practice settings" do
    sign_in_counselor_as counselors(:jo)
    get edit_counselor_practice_path
    assert_redirected_to counselor_root_path
  end

  test "owner updates brand, profile, and resource links" do
    sign_in_counselor_as counselors(:sam)
    patch counselor_practice_path, params: { practice: {
      name: "Riverbend Therapy", slug: "riverbend", primary_color: "#112233", accent_color: "#445566",
      website_url: "https://riverbend.example", booking_url: "https://book.example", phone: "555-0100", appointment_email: "hi@riverbend.example",
      resource_links_attributes: { "0" => { title: "Site", url: "https://riverbend.example", description: "About us", position: 1 } }
    } }
    assert_redirected_to edit_counselor_practice_path
    practice = practices(:riverbend).reload
    assert_equal "#112233", practice.primary_color
    assert_equal "Site", practice.resource_links.first.title
  end

  test "icon upload is validated and stored" do
    sign_in_counselor_as counselors(:sam)
    patch counselor_practice_path, params: { practice: { icon: png_upload(300, 200) } }
    assert_response :unprocessable_entity
    assert_match(/must be square/, response.body)

    patch counselor_practice_path, params: { practice: { icon: png_upload(512) } }
    assert_redirected_to edit_counselor_practice_path
    assert practices(:riverbend).reload.icon.attached?
  end

  test "changing the slug is refused when taken" do
    sign_in_counselor_as counselors(:sam)
    patch counselor_practice_path, params: { practice: { slug: "crossroads" } }
    assert_response :unprocessable_entity
  end

  test "the edit page shows the practice's web address" do
    sign_in_counselor_as counselors(:sam)
    get edit_counselor_practice_path
    assert_select "code", "riverbend.example.com"
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/dashboard/practices_controller_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/dashboard/practices_controller.rb
class Dashboard::PracticesController < Dashboard::BaseController
  before_action :require_owner
  before_action :set_practice

  def edit
  end

  def update
    if @practice.update(practice_params)
      redirect_to edit_counselor_practice_path, notice: "Practice saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_practice
    @practice = current_counselor.practice
  end

  # custom_domain is deliberately absent: only a platform admin sets it, since
  # each one needs DNS and a Hatchbox entry.
  def practice_params
    params.require(:practice).permit(
      :name, :slug, :primary_color, :accent_color, :logo, :icon,
      :website_url, :booking_url, :phone, :appointment_email,
      resource_links_attributes: [ :id, :title, :url, :description, :position, :_destroy ]
    )
  end
end
```

```erb
<%# app/views/dashboard/practices/edit.html.erb %>
<% content_for :title, "Practice" %>
<h2>Practice</h2>
<p class="subtitle">Anything you leave blank falls back to the <%= brand.product_name %> default.</p>
<% if @practice.errors.any? %><div class="form-error"><%= @practice.errors.full_messages.to_sentence %></div><% end %>

<%= form_with model: @practice, url: counselor_practice_path, method: :patch, data: { controller: "brand-preview" } do |f| %>
  <div class="card">
    <h3>Brand</h3>
    <div class="field">
      <%= f.label :name %>
      <%= f.text_field :name, required: true, data: { brand_preview_target: "name", action: "input->brand-preview#update" } %>
    </div>
    <div class="field">
      <%= f.label :slug, "Web address" %>
      <%= f.text_field :slug, required: true, pattern: "[a-z0-9]+(-[a-z0-9]+)*" %>
      <p class="field-hint">Your clients use <code><%= @practice.host %></code>. Changing this changes the address for everyone.</p>
    </div>
    <div class="c-row">
      <div class="field">
        <%= f.label :primary_color, "Primary color" %>
        <%= f.text_field :primary_color, placeholder: Brand::DEFAULT_PRIMARY, data: { brand_preview_target: "primary", action: "input->brand-preview#update" } %>
      </div>
      <div class="field">
        <%= f.label :accent_color, "Accent color" %>
        <%= f.text_field :accent_color, placeholder: Brand::DEFAULT_ACCENT, data: { brand_preview_target: "accent", action: "input->brand-preview#update" } %>
      </div>
    </div>
    <div class="c-row">
      <div class="field">
        <%= f.label :logo, "Logo (PNG or JPEG, optional)" %>
        <%= f.file_field :logo, accept: "image/png,image/jpeg", data: { brand_preview_target: "logo", action: "change->brand-preview#update" } %>
        <% if @practice.logo.attached? %><p class="field-hint">Current: <%= image_tag url_for(@practice.logo.variant(resize_to_limit: [ 120, 40 ])), alt: "logo" %></p><% end %>
      </div>
      <div class="field">
        <%= f.label :icon, "App icon (square PNG, at least 512 px)" %>
        <%= f.file_field :icon, accept: "image/png,image/jpeg" %>
        <% if @practice.icon.attached? %><p class="field-hint">Current: <%= image_tag url_for(@practice.icon.variant(resize_to_fill: [ 48, 48 ])), alt: "icon" %></p><% end %>
      </div>
    </div>
    <div class="c-preview">
      <p class="c-muted">Preview</p>
      <div class="topbar" data-brand-preview-target="bar" style="background:<%= brand.primary_color %>;padding:10px;color:#fff;">
        <img data-brand-preview-target="logoPreview" alt="" style="max-height:32px;<%= 'display:none;' unless @practice.logo.attached? %>" src="<%= @practice.logo.attached? ? url_for(@practice.logo.variant(resize_to_limit: [ 160, 32 ])) : '' %>">
        <span data-brand-preview-target="namePreview" style="<%= 'display:none;' if @practice.logo.attached? %>"><%= @practice.name.upcase %></span>
      </div>
      <button type="button" class="btn" data-brand-preview-target="button" style="margin-top:10px;background:<%= brand.accent_color %>;">Sample button</button>
    </div>
  </div>

  <div class="card">
    <h3>How clients reach you</h3>
    <div class="field"><%= f.label :website_url, "Website" %><%= f.url_field :website_url, placeholder: "https://" %></div>
    <div class="field"><%= f.label :booking_url, "Online booking link" %><%= f.url_field :booking_url, placeholder: "https://" %></div>
    <div class="field"><%= f.label :phone, "Office phone" %><%= f.telephone_field :phone %></div>
    <div class="field"><%= f.label :appointment_email, "Appointment request email" %><%= f.email_field :appointment_email %></div>
  </div>

  <div class="card">
    <h3>Resource links</h3>
    <p class="subtitle">Shown on your clients' Resources screen, in order.</p>
    <% links = @practice.resource_links.to_a + [ @practice.resource_links.build, @practice.resource_links.build ] %>
    <%= f.fields_for :resource_links, links do |lf| %>
      <div class="c-links-row">
        <%= lf.text_field :title, placeholder: "Title" %>
        <%= lf.url_field :url, placeholder: "https://" %>
        <%= lf.text_field :description, placeholder: "One line description" %>
        <%= lf.number_field :position, placeholder: "#", style: "width:60px;" %>
        <% if lf.object.persisted? %><label class="c-muted"><%= lf.check_box :_destroy %> remove</label><% else %><span></span><% end %>
      </div>
    <% end %>
    <p class="field-hint">Blank rows are ignored.</p>
  </div>

  <div class="actions"><%= f.submit "Save practice", class: "btn" %></div>
<% end %>
```

```js
// app/javascript/controllers/brand_preview_controller.js
import { Controller } from "@hotwired/stimulus";

const HEX = /^#[0-9a-f]{6}$/i;

export default class extends Controller {
  static targets = ["name", "primary", "accent", "logo", "bar", "button", "namePreview", "logoPreview"];

  update() {
    if (this.hasNameTarget) this.namePreviewTarget.textContent = this.nameTarget.value.toUpperCase();
    if (HEX.test(this.primaryTarget.value)) this.barTarget.style.background = this.primaryTarget.value;
    if (HEX.test(this.accentTarget.value)) this.buttonTarget.style.background = this.accentTarget.value;
    const file = this.hasLogoTarget && this.logoTarget.files[0];
    if (file) {
      this.logoPreviewTarget.src = URL.createObjectURL(file);
      this.logoPreviewTarget.style.display = "";
      this.namePreviewTarget.style.display = "none";
    }
  }
}
```

- [ ] **Step 4: Run the tests, commit**

Run: `node --check app/javascript/controllers/brand_preview_controller.js && bin/rails test test/controllers/dashboard/practices_controller_test.rb`
Expected: PASS.

```bash
git add app/controllers/dashboard/practices_controller.rb app/views/dashboard/practices app/javascript/controllers/brand_preview_controller.js test/controllers/dashboard/practices_controller_test.rb
git commit -m "Practice settings: brand, profile, resource links, live preview"
```

### Task C7: Members (owner) and Account

**Files:**
- Create: `app/controllers/dashboard/members_controller.rb`, `app/controllers/dashboard/accounts_controller.rb`
- Create: `app/views/dashboard/members/index.html.erb`, `app/views/dashboard/accounts/edit.html.erb`
- Create: `test/controllers/dashboard/members_controller_test.rb`, `test/controllers/dashboard/accounts_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/dashboard/members_controller_test.rb
require "test_helper"

class Dashboard::MembersControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "members cannot manage members" do
    sign_in_counselor_as counselors(:jo)
    get counselor_members_path
    assert_redirected_to counselor_root_path
  end

  test "owner sees members and pending invites" do
    CounselorInvite.create!(email_address: "pending@example.com", role: "member", practice: practices(:crossroads), invited_by: counselors(:logan))
    sign_in_counselor_as counselors(:logan)
    get counselor_members_path
    assert_select "td", text: "Jo"
    assert_select "td", text: "pending@example.com"
  end

  test "owner invites a member by email" do
    sign_in_counselor_as counselors(:logan)
    assert_enqueued_emails 1 do
      assert_difference -> { CounselorInvite.count }, 1 do
        post counselor_members_path, params: { member: { email_address: "new@example.com" } }
      end
    end
    invite = CounselorInvite.last
    assert_equal practices(:crossroads), invite.practice
    assert_equal "member", invite.role
    assert_equal counselors(:logan), invite.invited_by
  end

  test "owner removes a member but not themselves" do
    sign_in_counselor_as counselors(:logan)
    delete counselor_member_path(counselors(:jo))
    assert counselors(:jo).reload.removed?

    delete counselor_member_path(counselors(:logan))
    assert_not counselors(:logan).reload.removed?
    assert_redirected_to counselor_members_path
  end

  test "owner cannot remove someone from another practice" do
    sign_in_counselor_as counselors(:logan)
    delete counselor_member_path(counselors(:sam))
    assert_response :not_found
  end
end
```

```ruby
# test/controllers/dashboard/accounts_controller_test.rb
require "test_helper"

class Dashboard::AccountsControllerTest < ActionDispatch::IntegrationTest
  test "changes name and password with the current password" do
    sign_in_counselor_as counselors(:jo)
    patch counselor_account_path, params: { account: { name: "Jo B.", current_password: COUNSELOR_PASSWORD, password: "a whole new password", password_confirmation: "a whole new password" } }
    assert_redirected_to edit_counselor_account_path
    counselor = counselors(:jo).reload
    assert_equal "Jo B.", counselor.name
    assert counselor.authenticate("a whole new password")
  end

  test "wrong current password changes nothing" do
    sign_in_counselor_as counselors(:jo)
    patch counselor_account_path, params: { account: { name: "Jo B.", current_password: "wrong", password: "a whole new password", password_confirmation: "a whole new password" } }
    assert_response :unprocessable_entity
    assert_equal "Jo", counselors(:jo).reload.name
  end

  test "name alone can change without a password" do
    sign_in_counselor_as counselors(:jo)
    patch counselor_account_path, params: { account: { name: "Jo B." } }
    assert_redirected_to edit_counselor_account_path
    assert_equal "Jo B.", counselors(:jo).reload.name
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/dashboard/members_controller_test.rb test/controllers/dashboard/accounts_controller_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/dashboard/members_controller.rb
class Dashboard::MembersController < Dashboard::BaseController
  before_action :require_owner

  def index
    load_index
  end

  def create
    invite = current_counselor.practice.counselor_invites.new(
      email_address: params.dig(:member, :email_address), role: "member", invited_by: current_counselor
    )
    if invite.save
      CounselorInvitesMailer.invite(invite).deliver_later
      redirect_to counselor_members_path, notice: "Invite sent to #{invite.email_address}."
    else
      load_index
      flash.now[:alert] = invite.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    member = current_counselor.practice.counselors.find(params[:id])
    if member == current_counselor
      return redirect_to counselor_members_path, alert: "You can't remove yourself."
    end
    member.remove!
    redirect_to counselor_members_path, notice: "#{member.name} removed."
  end

  private

  def load_index
    @members = current_counselor.practice.counselors.order(:name)
    @pending = current_counselor.practice.counselor_invites.pending.order(:created_at)
  end
end
```

```ruby
# app/controllers/dashboard/accounts_controller.rb
class Dashboard::AccountsController < Dashboard::BaseController
  def edit
  end

  def update
    attrs = params.require(:account).permit(:name, :password, :password_confirmation)
    if attrs[:password].present? && !current_counselor.authenticate(params.dig(:account, :current_password).to_s)
      flash.now[:alert] = "Current password is incorrect."
      return render :edit, status: :unprocessable_entity
    end
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?

    if current_counselor.update(attrs)
      redirect_to edit_counselor_account_path, notice: "Account updated."
    else
      flash.now[:alert] = current_counselor.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
end
```

```erb
<%# app/views/dashboard/members/index.html.erb %>
<% content_for :title, "Members" %>
<h2>Members</h2>
<table class="c-table">
  <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Status</th><th></th></tr></thead>
  <tbody>
    <% @members.each do |m| %>
      <tr>
        <td><%= m.name %></td>
        <td><%= m.email_address %></td>
        <td><%= m.role %></td>
        <td><%= m.removed? ? "removed" : "active" %></td>
        <td><% if m != current_counselor && !m.removed? %><%= button_to "Remove", counselor_member_path(m), method: :delete, class: "c-linkbtn", form_class: "c-inline" %><% end %></td>
      </tr>
    <% end %>
    <% @pending.each do |i| %>
      <tr class="c-muted"><td>—</td><td><%= i.email_address %></td><td>member</td><td>invited, expires <%= i.expires_at.to_date %></td><td></td></tr>
    <% end %>
  </tbody>
</table>

<div class="card" style="margin-top:16px;">
  <h3>Invite a counselor</h3>
  <%= form_with url: counselor_members_path, scope: :member, class: "c-row" do |form| %>
    <div class="field">
      <%= form.label :email_address, "Email" %>
      <%= form.email_field :email_address, required: true %>
    </div>
    <div><%= form.submit "Send invite", class: "btn" %></div>
  <% end %>
</div>
```

```erb
<%# app/views/dashboard/accounts/edit.html.erb %>
<% content_for :title, "Account" %>
<h2>Account</h2>
<%= form_with url: counselor_account_path, scope: :account, method: :patch do |form| %>
  <div class="card">
    <div class="field"><%= form.label :name %><%= form.text_field :name, value: current_counselor.name, required: true %></div>
    <p class="c-muted">Signed in as <%= current_counselor.email_address %>, <%= current_counselor.role %> of <%= current_counselor.practice.name %>.</p>
  </div>
  <div class="card">
    <h3>Change password</h3>
    <div class="field"><%= form.label :current_password %><%= form.password_field :current_password, autocomplete: "current-password" %></div>
    <div class="field"><%= form.label :password, "New password" %><%= form.password_field :password, autocomplete: "new-password", minlength: Counselor::MINIMUM_PASSWORD_LENGTH %></div>
    <div class="field"><%= form.label :password_confirmation, "Confirm new password" %><%= form.password_field :password_confirmation, autocomplete: "new-password" %></div>
  </div>
  <div class="actions"><%= form.submit "Save", class: "btn" %></div>
<% end %>
```

- [ ] **Step 4: Run the tests, commit**

Run: `bin/rails test test/controllers/dashboard`
Expected: PASS.

```bash
git add app/controllers/dashboard/members_controller.rb app/controllers/dashboard/accounts_controller.rb app/views/dashboard/members app/views/dashboard/accounts test/controllers/dashboard/members_controller_test.rb test/controllers/dashboard/accounts_controller_test.rb
git commit -m "Members management for owners and counselor account settings"
```

### Task C8: Report done

Run `bin/rails test && bin/rubocop`, then tell the driver Lane C is complete with the list of commits and any deviations.

---

## Lane P — platform admin, seeds, generic assets, lockdown (grok)

Platform controllers inherit from Lane C's `Dashboard::BaseController`
and call Lane C's `CounselorInvitesMailer`. If those files are not in the
tree yet, write your code against the contract and keep going; run your
tests once they land. Only touch the files Lane P owns.

### Task P1: Platform practices index and custom domain

**Files:**
- Create: `app/controllers/platform/base_controller.rb`
- Create: `app/controllers/platform/practices_controller.rb`
- Create: `app/views/platform/practices/index.html.erb`, `app/views/platform/practices/show.html.erb`
- Create: `test/controllers/platform/practices_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/platform/practices_controller_test.rb
require "test_helper"

class Platform::PracticesControllerTest < ActionDispatch::IntegrationTest
  test "non-admin counselors get 404" do
    sign_in_counselor_as counselors(:sam)
    get platform_root_path
    assert_response :not_found
  end

  test "anonymous is sent to counselor login" do
    get platform_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "admin sees every practice with host, owner, counts, and trial" do
    users(:danny).update_columns(last_synced_at: 1.day.ago)
    sign_in_counselor_as counselors(:logan)
    get platform_root_path
    assert_response :success
    assert_select "td", text: "Crossroads Professional Counseling"
    assert_select "td", text: "app.crossroadcounselor.com"
    assert_select "td", text: "riverbend.example.com"
    assert_select "td", text: "logan@crossroadcounselor.com"
  end

  test "admin sets a custom domain" do
    sign_in_counselor_as counselors(:logan)
    patch platform_practice_path(practices(:riverbend)), params: { practice: { custom_domain: "App.Riverbend.Example" } }
    assert_redirected_to platform_practice_path(practices(:riverbend))
    assert_equal "app.riverbend.example", practices(:riverbend).reload.custom_domain
  end

  test "a duplicate custom domain is refused" do
    sign_in_counselor_as counselors(:logan)
    patch platform_practice_path(practices(:riverbend)), params: { practice: { custom_domain: "app.crossroadcounselor.com" } }
    assert_response :unprocessable_entity
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/platform/practices_controller_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/platform/base_controller.rb
class Platform::BaseController < Dashboard::BaseController
  before_action :require_platform_admin

  private

  # 404 rather than 403: non-admins should not learn the pages exist.
  def require_platform_admin
    head :not_found unless current_counselor.platform_admin?
  end
end
```

```ruby
# app/controllers/platform/practices_controller.rb
class Platform::PracticesController < Platform::BaseController
  before_action :set_practice, only: %i[ show update ]

  def index
    @practices = Practice.includes(:counselors).order(:name)
  end

  def show
  end

  # The only place a custom domain is set: each one needs DNS and a Hatchbox
  # domain entry, which is operator work.
  def update
    if @practice.update(params.require(:practice).permit(:custom_domain, :client_limit_per_counselor, :trial_ends_at))
      redirect_to platform_practice_path(@practice), notice: "Saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_practice
    @practice = Practice.find(params[:id])
  end
end
```

```erb
<%# app/views/platform/practices/index.html.erb %>
<% content_for :title, "Platform" %>
<h2>Practices</h2>
<p><%= link_to "Invite a practice owner", new_platform_practice_invite_path, class: "btn" %></p>
<table class="c-table">
  <thead><tr><th>Practice</th><th>Host</th><th>Owner</th><th>Counselors</th><th>Active clients</th><th>Trial ends</th></tr></thead>
  <tbody>
    <% @practices.each do |p| %>
      <tr>
        <td><%= link_to p.name, platform_practice_path(p) %></td>
        <td><%= p.host %></td>
        <td><%= p.counselors.find(&:owner?)&.email_address || "—" %></td>
        <td><%= p.active_counselors.count %></td>
        <td><%= p.active_client_count %> / <%= p.client_limit %></td>
        <td><%= p.trial_ends_at&.to_date || "—" %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

```erb
<%# app/views/platform/practices/show.html.erb %>
<% content_for :title, @practice.name %>
<h2><%= @practice.name %></h2>
<p class="c-muted">Slug <code><%= @practice.slug %></code> · host <code><%= @practice.host %></code></p>
<% if @practice.errors.any? %><div class="form-error"><%= @practice.errors.full_messages.to_sentence %></div><% end %>

<%= form_with model: @practice, url: platform_practice_path(@practice), method: :patch do |f| %>
  <div class="card">
    <div class="field">
      <%= f.label :custom_domain, "Custom domain (needs DNS and a Hatchbox domain entry first)" %>
      <%= f.text_field :custom_domain, placeholder: "app.example.com" %>
    </div>
    <div class="c-row">
      <div class="field"><%= f.label :client_limit_per_counselor, "Client limit per counselor" %><%= f.number_field :client_limit_per_counselor, min: 1 %></div>
      <div class="field"><%= f.label :trial_ends_at, "Trial ends" %><%= f.date_field :trial_ends_at, value: @practice.trial_ends_at&.to_date %></div>
    </div>
  </div>
  <div class="actions"><%= f.submit "Save", class: "btn" %></div>
<% end %>

<h3 style="margin-top:20px;">Counselors</h3>
<table class="c-table">
  <tbody>
    <% @practice.counselors.each do |c| %>
      <tr><td><%= c.name %></td><td><%= c.email_address %></td><td><%= c.role %></td><td><%= c.removed? ? "removed" : "active" %></td></tr>
    <% end %>
  </tbody>
</table>
<p style="margin-top:12px;"><%= link_to "Invite an owner for this practice", new_platform_practice_invite_path(practice_id: @practice.id) %></p>
```

- [ ] **Step 4: Run the tests, commit**

Run: `bin/rails test test/controllers/platform/practices_controller_test.rb`
Expected: PASS.

```bash
git add app/controllers/platform test/controllers/platform/practices_controller_test.rb app/views/platform/practices
git commit -m "Platform admin: practices list and custom domains"
```

### Task P2: Platform practice invites

**Files:**
- Create: `app/controllers/platform/practice_invites_controller.rb`
- Create: `app/views/platform/practice_invites/new.html.erb`, `app/views/platform/practice_invites/show.html.erb`
- Create: `test/controllers/platform/practice_invites_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/platform/practice_invites_controller_test.rb
require "test_helper"

class Platform::PracticeInvitesControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { sign_in_counselor_as counselors(:logan) }

  test "inviting an owner for a new practice sends the setup link and shows it" do
    assert_enqueued_emails 1 do
      assert_difference -> { CounselorInvite.count }, 1 do
        post platform_practice_invites_path, params: { practice_invite: { email_address: "pat@example.com", practice_name: "Calm Waters" } }
      end
    end
    invite = CounselorInvite.last
    assert_equal "owner", invite.role
    assert_equal "Calm Waters", invite.practice_name
    assert_nil invite.practice
    assert_response :success
    assert_select "input[value*=?]", "/counselor/setup/#{invite.token}"
  end

  test "inviting an owner into an existing practice" do
    post platform_practice_invites_path, params: { practice_invite: { email_address: "logan2@example.com", practice_id: practices(:crossroads).id } }
    invite = CounselorInvite.last
    assert_equal practices(:crossroads), invite.practice
    assert_equal "owner", invite.role
    assert_select "input[value*=?]", "https://app.crossroadcounselor.com/counselor/setup/"
  end

  test "both or neither target is refused" do
    assert_no_difference -> { CounselorInvite.count } do
      post platform_practice_invites_path, params: { practice_invite: { email_address: "x@example.com" } }
    end
    assert_response :unprocessable_entity
  end

  test "non-admins get 404" do
    sign_in_counselor_as counselors(:sam)
    get new_platform_practice_invite_path
    assert_response :not_found
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/platform/practice_invites_controller_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/platform/practice_invites_controller.rb
class Platform::PracticeInvitesController < Platform::BaseController
  def new
    @invite = CounselorInvite.new(role: "owner", practice_id: params[:practice_id])
    @practices = Practice.order(:name)
  end

  # Either a brand new practice (practice_name) or an owner for one that
  # already exists (practice_id, used for the seeded Crossroads practice).
  def create
    attrs = params.require(:practice_invite).permit(:email_address, :practice_name, :practice_id)
    @invite = CounselorInvite.new(attrs.merge(role: "owner", invited_by: current_counselor))
    if @invite.save
      CounselorInvitesMailer.invite(@invite).deliver_later
      @setup_url = counselor_setup_url(@invite.token, host: Brand.new(@invite.practice).host, protocol: "https")
      render :show
    else
      @practices = Practice.order(:name)
      render :new, status: :unprocessable_entity
    end
  end
end
```

```erb
<%# app/views/platform/practice_invites/new.html.erb %>
<% content_for :title, "Invite a practice owner" %>
<h2>Invite a practice owner</h2>
<% if @invite.errors.any? %><div class="form-error"><%= @invite.errors.full_messages.to_sentence %></div><% end %>
<%= form_with model: @invite, scope: :practice_invite, url: platform_practice_invites_path do |f| %>
  <div class="card">
    <div class="field"><%= f.label :email_address, "Owner's email" %><%= f.email_field :email_address, required: true %></div>
    <div class="field"><%= f.label :practice_name, "New practice name" %><%= f.text_field :practice_name %></div>
    <div class="field">
      <%= f.label :practice_id, "…or an existing practice" %>
      <%= f.collection_select :practice_id, @practices, :id, :name, include_blank: "—" %>
    </div>
    <p class="field-hint">Fill in one or the other.</p>
  </div>
  <div class="actions"><%= f.submit "Send invite", class: "btn" %></div>
<% end %>
```

```erb
<%# app/views/platform/practice_invites/show.html.erb %>
<% content_for :title, "Invite sent" %>
<h2>Invite sent to <%= @invite.email_address %></h2>
<div class="card" data-controller="clipboard">
  <p class="subtitle">Emailed, and here it is to text as well:</p>
  <input type="text" readonly value="<%= @setup_url %>" data-clipboard-target="source">
  <button type="button" class="btn btn-o" style="margin-top:8px;" data-clipboard-target="button" data-action="click->clipboard#copy">Copy link</button>
</div>
<p><%= link_to "Back to practices", platform_root_path %></p>
```

- [ ] **Step 4: Run the tests, commit**

Run: `bin/rails test test/controllers/platform`
Expected: PASS.

```bash
git add app/controllers/platform/practice_invites_controller.rb app/views/platform/practice_invites test/controllers/platform/practice_invites_controller_test.rb
git commit -m "Platform admin: invite practice owners"
```

### Task P3: Generic assets and the Crossroads seed

**Files:**
- Create: `app/assets/images/generic/icon-192.png`, `icon-512.png`, `apple-touch-icon.png`, `wordmark.svg`
- Move: `public/icon-192.png`, `public/icon-512.png`, `public/apple-touch-icon.png`, `public/icon.svg` → `db/seeds/crossroads/`
- Delete: `public/manifest.json`
- Modify: `db/seeds.rb`
- Create: `test/integration/seeds_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/seeds_test.rb
require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeds are idempotent and recreate Crossroads exactly" do
    ENV["PLATFORM_ADMIN_EMAIL"] = "ops@example.com"
    2.times { Rails.application.load_seed }

    crossroads = Practice.find_by!(slug: "crossroads")
    assert_equal "app.crossroadcounselor.com", crossroads.custom_domain
    assert_equal "#32b1c3", crossroads.primary_color
    assert crossroads.icon.attached?
    assert_equal 2, crossroads.resource_links.count
    assert_equal "https://www.therapyportal.com/p/crossroadspc/", crossroads.booking_url

    platform = Practice.find_by!(slug: "platform")
    admin = Counselor.find_by!(email_address: "ops@example.com")
    assert admin.platform_admin?
    assert_equal platform, admin.practice
    assert_equal 1, Counselor.where(email_address: "ops@example.com").count, "re-running seeds must not duplicate the admin"
  ensure
    ENV.delete("PLATFORM_ADMIN_EMAIL")
  end
end
```

Fixtures already include a `crossroads` practice, so the seed must find it by slug and update it rather than create a duplicate; that is the same property that makes it idempotent in production.

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/integration/seeds_test.rb`
Expected: FAIL (seeds do nothing yet).

- [ ] **Step 3: Move the Crossroads assets and make the generic ones**

```bash
mkdir -p db/seeds/crossroads app/assets/images/generic
git mv public/icon-192.png public/icon-512.png public/apple-touch-icon.png public/icon.svg db/seeds/crossroads/
git rm public/manifest.json
```

Generate placeholder generic icons (a solid product-teal square; swapped for real artwork when the product has a name):

```bash
bin/rails runner '
  require "vips"
  { "icon-192.png" => 192, "icon-512.png" => 512, "apple-touch-icon.png" => 180 }.each do |name, px|
    img = Vips::Image.black(px, px, bands: 3) + [ 50, 177, 195 ]
    img.cast("uchar").write_to_file(Rails.root.join("app/assets/images/generic", name).to_s)
  end
'
```

`app/assets/images/generic/wordmark.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="240" height="40" viewBox="0 0 240 40"><text x="0" y="28" font-family="Lora, serif" font-size="22" letter-spacing="2" fill="#583c25">COUNSELING APP</text></svg>
```

Check `public/service-worker.js` for a pre-cache list naming `/manifest.json` or the icons; if present, remove those entries and bump `CACHE_NAME` (the file is in `public/`, which Lane P owns).

- [ ] **Step 4: Seeds**

```ruby
# db/seeds.rb
#
# Idempotent. Run on every deploy that needs it:
#   PLATFORM_ADMIN_EMAIL=you@example.com bin/rails db:seed
#
# 1. The Crossroads practice, exactly as the app looked before practices
#    existed, on its own domain. Finds by slug, so re-running updates rather
#    than duplicates. Never overwrites an icon the owner has since replaced.
crossroads = Practice.find_or_initialize_by(slug: "crossroads")
crossroads.assign_attributes(
  name: "Crossroads Professional Counseling",
  custom_domain: "app.crossroadcounselor.com",
  primary_color: "#32b1c3",
  accent_color: "#f06623",
  website_url: "https://crossroadcounselor.com/",
  booking_url: "https://www.therapyportal.com/p/crossroadspc/",
  phone: "(225) 341-4147",
  appointment_email: "logan@crossroadcounselor.com"
)
crossroads.trial_ends_at ||= 10.years.from_now
unless crossroads.icon.attached?
  crossroads.icon.attach(io: File.open(Rails.root.join("db/seeds/crossroads/icon-512.png")), filename: "icon-512.png", content_type: "image/png")
end
crossroads.save!
if crossroads.resource_links.none?
  crossroads.resource_links.create!([
    { title: "Crossroads Counseling Website", url: "https://crossroadcounselor.com/",
      description: "Learn about Crossroads Counseling and the services available.", position: 1 },
    { title: "Schedule an Appointment", url: "https://www.therapyportal.com/p/crossroadspc/",
      description: "Visit the client portal to schedule a counseling appointment.", position: 2 }
  ])
end

# 2. The operator's own practice and the platform admin. The password is
#    random and never printed; set it through the reset link printed below.
if (email = ENV["PLATFORM_ADMIN_EMAIL"].presence)
  platform = Practice.find_or_create_by!(slug: "platform") do |p|
    p.name = Rails.application.config.x.product_name
    p.trial_ends_at = 100.years.from_now
  end
  unless Counselor.exists?(email_address: email)
    admin = platform.counselors.create!(
      email_address: email, name: "Platform admin", role: "owner", platform_admin: true,
      password: SecureRandom.base58(32)
    )
    url = Rails.application.routes.url_helpers.edit_counselor_password_url(
      admin.password_reset_token, host: Rails.application.config.x.product_host, protocol: "https"
    )
    puts "Platform admin #{email} created. Set a password within 15 minutes at:\n#{url}"
  end
end
```

- [ ] **Step 5: Run the test, then the whole suite, commit**

Run: `bin/rails test test/integration/seeds_test.rb && bin/rails test`
Expected: PASS. Lane T's manifest test (`generic/icon-192`) and layout tests now find the real asset files.

```bash
git add db/seeds.rb db/seeds/crossroads app/assets/images/generic public test/integration/seeds_test.rb
git commit -m "Seed the Crossroads practice and add generic brand assets"
```

### Task P4: Lockdown test and README

**Files:**
- Modify: `test/integration/authentication_lockdown_test.rb`
- Modify: `README.md`

- [ ] **Step 1: Extend the lockdown test**

Add to `test/integration/authentication_lockdown_test.rb`:

```ruby
  COUNSELOR_PAGES = -> {
    [ counselor_root_path, counselor_invites_path, edit_counselor_practice_path,
      counselor_members_path, edit_counselor_account_path ]
  }

  test "every counselor page requires a counselor login" do
    instance_exec(&COUNSELOR_PAGES).each do |path|
      get path
      assert_redirected_to new_counselor_session_path, "expected #{path} to redirect to counselor login"
    end
    patch archive_counselor_client_path(users(:danny))
    assert_redirected_to new_counselor_session_path
    post counselor_invites_path
    assert_redirected_to new_counselor_session_path
  end

  test "a client login does not open counselor pages" do
    sign_in_as users(:danny)
    get counselor_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "platform pages need a platform admin" do
    get platform_root_path
    assert_redirected_to new_counselor_session_path
    sign_in_counselor_as counselors(:sam)
    get platform_root_path
    assert_response :not_found
  end

  test "counselor login, password reset, setup, and the manifest stay public" do
    get new_counselor_session_path
    assert_response :success
    get new_counselor_password_path
    assert_response :success
    get counselor_setup_path("bogus")
    assert_response :not_found
    get manifest_path
    assert_response :success
  end
```

Run: `bin/rails test test/integration/authentication_lockdown_test.rb`
Expected: PASS once Lanes C and T have landed; before that, the missing controllers error. Wait for them rather than skipping.

- [ ] **Step 2: README**

In `README.md`: remove the `admin:` key from the credentials example and the paragraph about `/admin/invites` and HTTP Basic. Add a `wasabi:` block (`bucket`, `access_key_id`, `secret_access_key`) to the credentials example. Add a section:

```markdown
## Practices and the platform admin

Every counselor belongs to a practice. The practice is resolved from the
request host: a custom domain (`app.crossroadcounselor.com` for Crossroads)
or `<slug>.$PRODUCT_HOST`. The bare product host shows the generic brand.

Environment: `PRODUCT_HOST` (e.g. `app.example.com`), `PRODUCT_NAME`, and
`PLATFORM_ADMIN_EMAIL` for seeding the platform admin.

Seeds are idempotent and create the Crossroads practice plus the platform
admin (printing a one-time password reset link):

    PLATFORM_ADMIN_EMAIL=you@example.com bin/rails db:seed

The platform admin invites practice owners from `/platform`. Custom domains
are set there too and need DNS plus a Hatchbox domain entry first. In
development, practices are reachable at `<slug>.lvh.me:3000`.
```

- [ ] **Step 3: Commit**

```bash
git add test/integration/authentication_lockdown_test.rb README.md
git commit -m "Lock down counselor and platform routes; document practices"
```

### Task P5: Report done

Run `bin/rails test && bin/rubocop`, then tell the driver Lane P is complete with the list of commits and any deviations.

---

## Integration (driver)

- [ ] **Step 1: Wait for all three lanes**, confirm `git status` is clean and every lane's commits are on `product-ready`.

- [ ] **Step 2: Grep for leftovers**

Run: `grep -rn 'crossroad\|CROSSROADS\|logan@\|therapyportal\|341-4147' app config public --include='*.rb' --include='*.erb' --include='*.js' --include='*.json' --include='*.yml' --include='*.css' | grep -v 'db/seeds'`
Expected: only `config/environments/production.rb` defaults for `PRODUCT_HOST` / mailer host until the product domain exists. Everything else is gone.

- [ ] **Step 3: Full CI**

Run: `bin/ci`
Expected: all green.

- [ ] **Step 4: Manual checks** against a test-environment server (`RAILS_ENV=test bin/rails server -p 3457`; development has no credentials key in this worktree). Seed first with `RAILS_ENV=test PLATFORM_ADMIN_EMAIL=ops@example.com bin/rails db:seed`. Map hosts in `/etc/hosts` or use `lvh.me` with `PRODUCT_HOST=lvh.me`.

1. `http://crossroads.lvh.me:3457/session/new` wears Crossroads; `http://lvh.me:3457/session/new` wears the generic brand; `/manifest.json` differs between the two.
2. Use the seed's printed reset link to set the platform admin password, log in at `/counselor/session/new`, open `/platform`, invite an owner into the Crossroads practice, open the setup link, create the owner.
3. As the owner: set colors and upload a 512 px icon, see the live preview, save, reload the client login page and see the colors. Add a resource link and booking URL.
4. Create a client invite, copy the link, open it in a fresh browser profile, sign up, log in, open Resources and Schedule and see the practice's content.
5. Archive the client; confirm the client can still log in and sync; the active count is unchanged.
6. Set `client_limit_per_counselor` to 1 from `/platform`; confirm a second invite is refused with the limit message.
7. Invite a member from Members, accept, log in as the member, confirm they see no clients and no Practice or Members links.

- [ ] **Step 5: Push and open the PR to `main`**

```bash
git push
gh pr create --base main --title "Practices, counselors, and white-label branding" --body-file docs/superpowers/specs/2026-09-22-multi-tenancy-design.md
```

- [ ] **Step 6: Deploy notes for the user**, in plain words: add the Wasabi keys to production credentials, set `PRODUCT_HOST`, `PRODUCT_NAME`, and `PLATFORM_ADMIN_EMAIL`, add wildcard DNS and the Hatchbox domain entries, deploy, run `bin/rails db:seed` on the server and use the printed link, then invite the Crossroads owner from `/platform`.
