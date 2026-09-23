# Counseling App

A Rails 8 application for managing counseling services.

## Requirements

- Ruby 3.4.1
- Rails 8.1
- PostgreSQL
- Node.js + Yarn (for asset pipeline)
- Redis (for background jobs and caching)

## Setup

1. Install dependencies:

   ```bash
   bundle install
   yarn install
   ```

2. Prepare the database:

   ```bash
   bin/rails db:create db:migrate db:seed
   ```

3. Start the app:

   ```bash
   bin/dev
   ```

## Credentials

This app uses Rails encrypted credentials per environment. To edit credentials:

```bash
# Default / production credentials
bin/rails credentials:edit

# Environment-specific credentials
bin/rails credentials:edit --environment=development
bin/rails credentials:edit --environment=production
```

### Required credential keys

Some third-party services expect specific credential keys. Add them under the
matching environment file if you use those services.

```yaml
honeybadger:
  api_key: "your_honeybadger_api_key"

active_record_encryption:
  primary_key: "generated_primary_key"
  deterministic_key: "generated_deterministic_key"
  key_derivation_salt: "generated_key_derivation_salt"

wasabi:
  bucket: "your_wasabi_bucket"
  access_key_id: "your_wasabi_access_key_id"
  secret_access_key: "your_wasabi_secret_access_key"

mailgun:
  api_key: "your_mailgun_api_key"
  domain: "mg.crossroadcounselor.com"

web_push:
  public_key: "your_vapid_public_key"
  private_key: "your_vapid_private_key"
```

> **Note:** `config/honeybadger.yml` reads the Honeybadger API key from
> `Rails.application.credentials.honeybadger&.dig(:api_key)`. The safe navigation
> allows the app (and `rails credentials:edit`) to boot even when the key is not
> configured.
>
> Generate VAPID keys with:
> ```bash
> bundle exec ruby -r web-push -e 'key = WebPush.generate_key; puts({public_key: key.public_key, private_key: key.private_key}.to_json)'
> ```
>
> Mailgun is configured to send via the Mailgun API using the domain from
> `mailgun.domain` (default `mg.crossroadcounselor.com`). Emails are sent from
> `no-reply@crossroadcounselor.com` regardless of the Mailgun domain.

## Continuous integration

This project uses Rails 8's built-in `ActiveSupport::ContinuousIntegration`
runner. The CI pipeline is defined in `config/ci.rb` and runs via:

```bash
bin/ci
```

`bin/ci` executes setup, the full Minitest suite, Ruby style checks, security
audits, and finally signs off with [`gh-signoff`](https://github.com/basecamp/gh-signoff)
when everything passes.

### Required checks

`gh signoff` must be installed and enabled as a required status check for PR
merges (see repository settings below).

## Running tests manually

```bash
bin/rails test
bin/rails test:system
```

## Background jobs

This app uses Solid Queue for background jobs. In development it is started
automatically by `bin/dev`. To run it manually:

```bash
bin/jobs
```

## Deployment

Deployment is managed with [Hatchbox](https://hatchbox.io/). The app runs on a
DigitalOcean droplet at `app.crossroadcounselor.com`, deployed from the `main`
branch. Trigger deploys from the Hatchbox dashboard (or push to `main` if
auto-deploy is enabled).

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

## Useful links

- [Rails Guides](https://guides.rubyonrails.org/)
- [Honeybadger Ruby docs](https://docs.honeybadger.io/lib/ruby/)
- [Hatchbox](https://hatchbox.io/)
