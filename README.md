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

admin:
  password: "your_secure_admin_password"

mailgun:
  api_key: "your_mailgun_api_key"
```

> **Note:** `config/honeybadger.yml` reads the Honeybadger API key from
> `Rails.application.credentials.honeybadger&.dig(:api_key)`. The safe navigation
> allows the app (and `rails credentials:edit`) to boot even when the key is not
> configured.
>
> The admin dashboard at `/admin/invites` uses HTTP Basic Auth with username
> `admin` and the password from `Rails.application.credentials.admin&.dig(:password)`,
> falling back to `changeme`. Configure a real password before deploying.
>
> Mailgun is configured for transactional email. Add the `mailgun.api_key`
> credential to enable invite-code emails from the admin dashboard.

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

Deployment is managed with Kamal. See `config/deploy.yml` for server and Docker
configuration.

```bash
# Deploy to production
kamal deploy
```

## Useful links

- [Rails Guides](https://guides.rubyonrails.org/)
- [Honeybadger Ruby docs](https://docs.honeybadger.io/lib/ruby/)
- [Kamal docs](https://kamal-deploy.org/)
