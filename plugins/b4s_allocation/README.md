# b4s_allocation

Biz4Solutions customisations for Redmine: project allocation percentages
with start/end dates, bench and billable tracking, uppercase project
identifiers, and the (currently dormant) time entry approval workflow with
weekly timesheets.

Requires Redmine 6.1 or later.

## Layout

| What | Where |
|---|---|
| New models, controllers, views, mailer templates | `app/` |
| Changes to core classes | `lib/b4s_allocation/patches/*_patch.rb`, applied in `init.rb` |
| View hooks (project form, context menu, stylesheet) | `lib/b4s_allocation/hooks.rb`, `app/views/b4s_allocation/hooks/` |
| Permission, menu item | `init.rb` |
| Routes | `config/routes.rb` (plus one route prepended in `init.rb`) |
| Translations | `config/locales/` |
| Migrations | `db/migrate/` |
| Rake tasks | `lib/tasks/` |

## Migrations

The migrations keep the version numbers they had when they lived in core
`db/migrate`. Each one skips itself when that version is already recorded as
a core migration, so a database that ran them as core migrations only records
the plugin version:

    bundle exec rake redmine:plugins:migrate NAME=b4s_allocation RAILS_ENV=production

## Upgrading Redmine

Core files with no usable hook are overridden by full copies at the same path
under `app/views`. After every Redmine upgrade, diff each one against the new
upstream file and carry over upstream changes:

    git diff <old-tag> <new-tag> -- app/views/members/_edit.html.erb   # etc.

Overridden views: `members/` (`_edit`, `_new_form`, `create.js`, `update.js`,
`index.api`, `show.api`), `principal_memberships/` (`_edit`, `_index`,
`_new_form`, `create.js`, `update.js`), `projects/settings/_members`,
`projects/show`, `timelog/index.api`, `timelog/show.api`, `users/show`,
`users/show.api`.

Copied core methods: `Member.create_principal_memberships`,
`MemberRole#add_role_to_subprojects`, `MembersController#create/#update`,
`PrincipalMembershipsController#create/#update`, `MyController#page`,
`MembersHelper#render_principals_for_new_members`,
`MyHelper#block_select_tag`. Re-check these against upstream too.

Project identifier rules are replaced by removing core's `identifier` length
and format validators (see `ProjectPatch`); re-check if upstream changes them.

## Tests

    bundle exec rake redmine:plugins:test NAME=b4s_allocation RAILS_ENV=test

Tests skipped with a `BUG:` note fail against the current code on purpose and
document known defects.
