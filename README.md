<p align="center">
  <img src="docs/assets/busbar-logo.png" alt="BusBar" width="420">
</p>

# BusBar

BusBar is a mountable Rails engine that makes onboarding a client's data easy.
Clients bring CSV (and TSV, XLSX, JSON or NDJSON) files through an in-app
upload, SFTP, a bucket, email or an HTTPS push, either once when they are
onboarded or continuously on a recurring feed. BusBar maps each client's
columns to a schema, validates and stages every row, shows a review screen,
and upserts the result into your app's own models.

The full design lives in [docs/spec.md](docs/spec.md).

> **Status: phase 1.** The core pipeline (parse, map, stage, validate, diff,
> load, finalize, after-ingestion), code-defined schemas, templates, the step
> library, both loaders, the install generator and the upload, mapping,
> review and run screens are in place. The first host is
> [locke](https://github.com/robertoplancarte/locke). Recurring feeds and SFTP
> are next; see [Roadmap](#roadmap).

## Stack

- Rails 8 engine, gem `busbar`, Ruby namespace `Busbar`
- PostgreSQL (required: the pipeline uses `COPY`, `jsonb` and partial indexes)
- [acts_as_tenant](https://github.com/ErwinM/acts_as_tenant) for row-level multi-tenancy
- [Statesman](https://github.com/gocardless/statesman) for the run state machine and its audit trail
- Hotwire (Turbo and Stimulus) for the UI, no build step required
- ActiveJob for the pipeline, so Solid Queue, Sidekiq and GoodJob all work

## Installing in a host app

```ruby
# Gemfile
gem "busbar", github: "robertoplancarte/busbar"
```

```sh
bin/rails active_storage:install     # if the app doesn't have it yet
bin/rails g busbar:install --tenant-class=Tenant --user-class=User
bin/rails db:migrate
bin/rails busbar:check               # checks schemas against your models and indexes
```

The generator writes the engine migration (foreign keys to your tenant
table), `config/initializers/busbar.rb` and `mount Busbar::Engine, at: "/busbar"`.

## Using it from locke

Locke's users are tenant-scoped through acts_as_tenant, use
`has_secure_password`, encrypt `email` deterministically, and fill
`otp_secret`, `webauthn_id` and `public_id` in create callbacks. The shipped
`user` schema loads them with the per-row save loader, so all of that runs.

```ruby
# config/initializers/busbar.rb
Busbar.configure do |c|
  c.tenant_class  = "Tenant"
  c.tenant_column = :tenant_id
  c.user_class    = "User"
  c.current_user  = -> { Current.user }

  # Denied until you set this. Locke has no roles yet; a per-tenant admin
  # check could be a list on the tenant (admin_user_ids is an example column):
  c.authorize = ->(user, _action, _record) do
    tenant = ActsAsTenant.current_tenant
    user.present? && user.tenant_id == tenant&.id && tenant.admin_user_ids.include?(user.id)
  end

  c.after_ingestion = { user: "UserIngestionHandler" }
end
```

```ruby
# app/busbar/user_ingestion_handler.rb: invite every user an import created.
# context.created skips rows already handled, so re-running sends nothing twice.
class UserIngestionHandler < Busbar::AfterIngestion
  def call(_run, context)
    context.created.each do |row|
      UserMailer.with(user: row.record).invitation_instructions.deliver_later
    end
  end
end
```

```ruby
# Optional: what "deactivate" means for snapshot_deactivate feeds, and the
# password new users start with (random by default; they set their own
# through the invitation).
class UserLoader < Busbar::Loaders::ActiveRecordSave
  def deactivate(keys, context)
    records_for(keys, context).find_each do |user|
      user.update!(status: "inactive")
      user.sessions.find_each(&:log_out)
    end
  end
end
Busbar.register_loader :user, UserLoader
```

Templates for locke map `email`, `name` (or `first_name` and `last_name`)
and `time_zone`, and match existing users by lowercased email. `busbar:check`
warns that locke's `User` has no `external_id`, so templates must not map one.
Locke's `not_pwned` password check calls a web service for every new user;
override `initial_password` or skip that validation for imported users if
that is too slow.

Other record types use the fast upsert loader:

```ruby
Busbar.define_schema :employee do
  natural_key :external_id
  loader :active_record, model: "Employee"   # needs a unique index on (tenant_id, external_id)
  field :external_id, :string, required: true, synonyms: [ "emp id", "employee number" ]
  field :email, :email, required: true
  field :hired_on, :date
  field :status, :enum, values: %w[active leave terminated]
end
```

## Repository layout

| Path | What it is |
| --- | --- |
| `app/`, `config/`, `lib/` | The engine |
| `spec/` | RSpec suite for the engine |
| `spec/dummy/` | Dummy host app shaped like locke: `Tenant`, an encrypted `User` with `has_secure_password` and create callbacks, `Identity`, and a plain `Employee` for the upsert loader |
| `extensions/busbar-oneroster/` | The `busbar-oneroster` extension gem (OneRoster 1.2 CSV packages), developed alongside the engine with its own gemspec and Minitest suite |
| `docs/spec.md` | The engine spec |
| `docs/assets/` | Logo files |

`busbar-oneroster` registers itself through the engine's `:busbar` load hook,
which the engine already fires. The extension API it calls
(`Busbar.register_extension`) lands in phase 3, so the gem is not yet added to
the dummy app.

## Development

You need Ruby 3.3 and a running PostgreSQL.

```sh
bundle install
(cd spec/dummy && bin/rails db:prepare)
bin/rspec          # engine specs
bin/rubocop        # lint

cd extensions/busbar-oneroster
bundle install
bundle exec rake test
```

Set `DATABASE_URL` or `PGHOST`/`PGUSER`/`PGPASSWORD` if Postgres is not on the
default local socket.

## Roadmap

1. **Core pipeline and upload** (built; see docs/spec.md, "Phase 1 as built"). Schemas, templates, step library, pipeline jobs, generic loader, incremental mode, upload, mapping, review and run screens.
2. **Recurring feeds and SFTP.** Feeds, scheduler, hosted and remote SFTP, bucket pull, email-in, HTTPS push, snapshot modes, thresholds, notifications.
3. **Flexibility.** Database-defined schemas, value maps, PGP, JSON API, view generator, extension API with package runs, busbar-oneroster.
4. **Assistance.** LLM mapping suggester, find-and-replace on staged rows, AWS Transfer Family adapter.

## License

MIT. See [MIT-LICENSE](MIT-LICENSE).
