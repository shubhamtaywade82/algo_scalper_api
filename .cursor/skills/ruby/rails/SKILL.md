---
name: rails-style
description: Rails Style Guide (rails.rubystyle.guide) conventions for configuration, routing, controllers, models, Active Record, migrations, views, mailers, and testing. Use when writing or reviewing Rails/Ruby on Rails code.
---

# Rails Style Guide

This skill applies the [Rails Style Guide](https://rails.rubystyle.guide/) — best practices for Ruby on Rails. Use when writing or reviewing Rails apps. [RuboCop Rails](https://github.com/rubocop/rubocop-rails) is based on this guide.

## Configuration

- **Initializers:** Put custom startup code in `config/initializers`. One file per gem (e.g. `carrierwave.rb`).
- **Environments:** Keep dev/test/prod settings in `config/environments/`. Use env vars for staging-like config; avoid extra env files.
- **App config:** App-wide settings in `config/application.rb`. Use `config.load_defaults` matching your Rails version.
- **YAML:** Extra config in YAML under `config/`; load with `Rails.application.config_for(:yaml_file)`.

## Routing

- **Member/collection:** Use `member` and `collection` for extra REST actions, not separate `get` routes.
- **Nested routes:** Use nesting to express AR relationships; use `shallow: true` if nesting more than one level.
- **Namespaced routes:** Use `namespace` to group related actions (e.g. `namespace :admin`).
- **No wild routes:** Never use the legacy `match ':controller(/:action(/:id))'`. Don't use `match` unless mapping multiple HTTP methods with `:via`.

```ruby
# good
resources :subscriptions do
  get 'unsubscribe', on: :member
end
resources :photos do
  get 'search', on: :collection
end
```

## Controllers

- **Skinny controllers:** Only fetch data for the view; no business logic (logic in models/services).
- **One method:** Each action should (ideally) call at most one meaningful method besides find/new.
- **Few instance variables:** Minimize instance variables passed to the view.
- **Lexically scoped filters:** Put `before_action`/`after_action` next to the actions they affect so scope is clear.
- **Rendering:** Prefer templates over `render inline:`. Use `render plain:` not `render text:`. Prefer status symbols (e.g. `:forbidden`) over numeric codes.

## Models

- **Meaningful names:** Short, meaningful model names; no abbreviations.
- **Non-AR models:** Use `ActiveModel::Model` (and optionally `ActiveModel::Attributes`) for form-like objects with validations but no DB.
- **Business logic in models:** Keep formatting/presentation in helpers or decorators; models hold business logic and persistence only.

## Active Record

- **Defaults:** Avoid changing AR defaults (table name, primary key) unless necessary.
- **ignored_columns:** Use `self.ignored_columns += %i[col]`, not `self.ignored_columns =`, so you don't overwrite existing list.
- **Enums:** Prefer hash syntax for `enum` so values are explicit and order-independent.
- **Macro order:** Group macros at the top: default_scope, constants, attr, enum, associations, validations, callbacks.
- **has_many :through:** Prefer over `has_and_belongs_to_many` when you need attributes or validations on the join.
- **Read/write attributes:** Prefer `self[:attr]` and `self[:attr] = value` over `read_attribute`/`write_attribute`.
- **Validations:** Use new-style `validates :email, presence: true, length: { maximum: 100 }`. One attribute per validation line. Custom validators in `app/validators`; name them so they read like "validate …" (e.g. `validate :expiration_date_cannot_be_in_the_past`).
- **Scopes:** Use named scopes; use class methods when a lambda gets too complex and must return a relation.
- **Callbacks order:** Declare callbacks in execution order (see Rails docs).
- **Dependent:** Always set `dependent` on `has_many`/`has_one` (e.g. `dependent: :destroy`).
- **before_destroy:** Use `prepend: true` for validation-style `before_destroy` so it runs before dependent destroy.
- **Persistence:** Prefer bang methods (`create!`, `save!`, `update!`) or explicitly check return value; avoid silent failures.
- **find_each:** Use `find_each` (not `.all.each`) for batch processing of large collections.
- **User-friendly URLs:** Override `to_param` or use something like FriendlyId for readable slugs.

## Active Record Queries

- **No interpolation:** Never interpolate user input into SQL; use placeholders or named params.
- **Hash conditions:** Prefer `where(attr: value)` and `where.not(attr: value)` over raw SQL fragments.
- **find vs find_by:** Use `find(id)` when you want `RecordNotFound`; use `find_by(attr: value)` when you want `nil` if missing.
- **Order:** Use symbols (e.g. `order(created_at: :desc)`). Don't order by `id` for "chronological"; use a timestamp column.
- **pluck / pick / ids:** Use `pluck(:col)` for many values, `pick(:col)` for one, `ids` instead of `pluck(:id)`.
- **size:** Prefer `size` over `count` when the collection might be loaded (avoids extra query); use `length` if you need the in-memory count.
- **Ranges:** Use range conditions: `where(created_at: 30.days.ago..7.days.ago)`. Rails 6.1+: `where.missing(:association)` for missing relations.
- **where.not:** With multiple attributes, use an explicit condition (e.g. string with placeholders); multi-attr `where.not` semantics changed in 6.1.
- **Redundant all:** Omit `.all` when it doesn't change behavior (e.g. `User.find`, `user.articles.order(...)`). Keep it for `delete`/`destroy` etc. when the docs say it matters.
- **find_by memoization:** Don't use `||=` with `find_by` (it can return `nil`). Use `defined?(@var)` or explicit assign-and-check.

## Migrations

- **Schema:** Keep `schema.rb` (or `structure.sql`) in version control. Use `db:schema:load` for a fresh DB.
- **Defaults in DB:** Enforce default values in migrations, not only in the app. For booleans, set `default:` and `null: false`.
- **Foreign keys:** Add foreign key constraints (e.g. `t.references :user, foreign_key: true`). Name FKs explicitly when needed.
- **change:** Prefer `change` over `up`/`down` for reversible migrations. Use `reversible` or `up`/`down` for non-reversible operations.
- **Models in migrations:** If you reference a model in a migration, define a dedicated class (e.g. `MigrationUser`) with `self.table_name = :users` so future model renames don't break the migration.
- **Reversible:** Don't use non-reversible commands inside `change` unless the migration supports it.

## Views

- **No direct model in view:** Don't call the model layer directly from the view; use helpers, decorators, or presenters.
- **No complex formatting in views:** Use helpers for simple cases; decorators/presenters for complex formatting.
- **Partials:** Use partials and layouts to reduce duplication.
- **Partials and locals:** Pass data to partials via local variables (e.g. `render 'course_description', course: @course`), not instance variables.

## Internationalization (I18n)

- **No raw strings in views/models/controllers:** Use I18n. Put texts in `config/locales`. Use `activerecord` scope for model/attribute labels.
- **Short form:** Use `I18n.t` and `I18n.l`. Use lazy lookup in views (e.g. `t '.title'`). Prefer dot-separated keys (e.g. `'activerecord.errors.messages.record_invalid'`).

## Mailers

- **Naming:** Name mailers `SomethingMailer`. Provide both HTML and plain-text templates.
- **Config:** Set `raise_delivery_errors = true` in development. Use local SMTP (e.g. Mailcatcher) in dev. Set `default_url_options` for host. Format from/to with name (e.g. `email_address_with_name`).
- **Test:** Use `delivery_method = :test` in test. Use background jobs (e.g. Sidekiq) for sending in production so the request doesn't block.

## Time and duration

- **Time zone:** Configure `config.time_zone` in `application.rb`. Use `Time.zone.parse`, `Time.zone.now`, `Time.current` — not `Time.parse`, `Time.now`, or `String#to_time`.
- **Ranges:** Prefer `all_day`, `all_week`, `all_month`, `all_quarter`, `all_year` over manual `beginning_of_... .. end_of_...`.
- **Duration:** Use `from_now`/`ago` without args; use `since`/`after`/`until`/`before` with an argument. Prefer positive literals (e.g. `5.hours.ago` not `-5.hours.from_now`). Use duration methods (e.g. `2.days.from_now`) instead of `Time.current + 2.days`.

## Active Support

- **Safe navigation:** Prefer `&.` over `try!`. Prefer Ruby stdlib over AS aliases (e.g. `start_with?` over `starts_with?`). Prefer `include?` over `in?` for clarity. Use `exclude?` instead of `!include?`. Prefer `<<~HEREDOC` over `strip_heredoc`. Rails 7+: prefer `to_fs` over `to_formatted_s`.

## Bundler and testing

- **Gemfile:** Put dev/test-only gems in the right group. Rely on well-maintained gems. Keep `Gemfile.lock` in version control.
- **Controller tests:** Prefer integration-style tests (`ActionDispatch::IntegrationTest`) over functional controller tests.
- **Time in tests:** Use `freeze_time` (from `ActiveSupport::Testing::TimeHelpers`) instead of `travel_to(Time.current)` when you want to freeze the current time.

## Summary checklist

- [ ] Skinny controllers; one meaningful method per action
- [ ] Routing: member/collection, shallow nesting, no wild/match
- [ ] Models: validations, scopes, dependent, find_each, bang persistence
- [ ] Queries: no interpolation, hash conditions, find/find_by, size/pluck/pick/ids
- [ ] Migrations: foreign keys, defaults, reversible, no bare model references
- [ ] Views: no direct model, partials with locals
- [ ] I18n for all user-facing strings; lazy lookup and dot-separated keys
- [ ] Mailers: both formats, default host, background in production
- [ ] Time: `Time.zone`/`Time.current`; `all_*` and duration helpers
- [ ] RuboCop Rails for automated checks

## Reference

- [Rails Style Guide](https://rails.rubystyle.guide/) — full guide
- [RuboCop Rails](https://github.com/rubocop/rubocop-rails) — linter based on this guide
- [Ruby Style Guide](https://rubystyle.guide/) — complementary Ruby conventions
