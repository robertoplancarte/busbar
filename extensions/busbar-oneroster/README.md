# busbar-oneroster

OneRoster 1.2 CSV support for the BusBar Rails engine. Add the gem and a host
app can accept OneRoster zip packages (bulk or delta) through any BusBar
channel: upload, SFTP, bucket, email or HTTPS push.

```ruby
# Gemfile
gem "busbar"
gem "busbar-oneroster"
```

Nothing else is required to recognise packages. The gem registers itself when
the engine runs its `:busbar` load hook.

## What it registers

| Engine piece | Registered as | Purpose |
| --- | --- | --- |
| Package handler | `Busbar::OneRoster::PackageHandler` | Detects a zip with `manifest.csv`, validates it, and expands it into one child run per file in dependency order |
| Schemas | `oneroster_orgs`, `oneroster_academic_sessions`, `oneroster_courses`, `oneroster_classes`, `oneroster_users`, `oneroster_demographics`, `oneroster_roles`, `oneroster_enrollments` | Fields are the snake_cased OneRoster columns, natural key `sourced_id`, scoped by `source_system` |
| Templates | One per schema, same names | Headers are fixed by the standard, so runs skip column mapping |
| Transform | `oneroster_row` | Types each row (dates, UTC timestamps, booleans, multi-value lists, vocabularies with `ext:` terms) and sets its action |

## Bulk and delta

| Manifest mode | Load mode | Row action |
| --- | --- | --- |
| `bulk` | `snapshot_deactivate`, scoped to the manifest's source system | Every row upserts; `status` and `dateLastModified` must be empty |
| `delta` | `incremental` | `active` upserts, `tobedeleted` deactivates; both columns required |

## Loading into your models

The schemas describe OneRoster data; your app decides where it goes. Register
a loader per schema you care about. Schemas without a loader are validated and
staged but not loaded, and the run reports them as skipped.

```ruby
Busbar.register_loader :oneroster_users, OneRosterUserLoader
Busbar.register_loader :oneroster_enrollments, OneRosterEnrollmentLoader

class OneRosterUserLoader < Busbar::Loader
  def load(rows, context)
    User.upsert_all(
      rows.map do |r|
        { account_id: context.tenant.id, external_id: r["sourced_id"], email: r["email"],
          first_name: r["preferred_given_name"] || r["given_name"], last_name: r["family_name"],
          active: r["enabled_user"] }
      end,
      unique_by: %i[account_id external_id]
    )
  end

  def deactivate(keys, context)
    User.where(account_id: context.tenant.id, external_id: keys).update_all(active: false)
  end
end
```

## Package rules enforced

- Files sit at the zip root; nested folders, duplicate names and zip bombs are rejected
- `manifest.version` is `1.0` and `oneroster.version` is `1.2`
- A file declared `bulk` or `delta` must be present; a file present but declared `absent` is processed with its mode inferred, and a warning is recorded
- Every file's header matches the 1.2 column list exactly, in order
- Gradebook and resource files are reported as skipped, not rejected

## Not yet supported

- Gradebook and resources files (`lineItems`, `results`, `resources`, `userProfiles`, ...)
- OneRoster 1.1 packages
- The OneRoster REST binding (a future channel, pulling with OAuth 2 client credentials)

## Development

```sh
bundle install
bundle exec rake test
```

The tests cover the parts of the gem that do not need the engine: file
specs, manifest parsing, the package reader, value parsing, row conversion,
and a contract test of the calls the gem makes against the engine's extension
API.

Column lists come from the [1EdTech OneRoster 1.2 CSV binding](https://standards.1edtech.org/oneroster/specifications/standards/v1p2/csv).
Required-field lists should be checked against the official conformance test
packages before release.
