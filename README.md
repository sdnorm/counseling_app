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
```

> **Note:** `config/honeybadger.yml` reads the Honeybadger API key from
> `Rails.application.credentials.honeybadger&.dig(:api_key)`. The safe navigation
> allows the app (and `rails credentials:edit`) to boot even when the key is not
> configured.

## Running tests

```bash
bin/rspec
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
