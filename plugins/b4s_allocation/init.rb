require_relative 'lib/b4s_allocation/core_migration'

Redmine::Plugin.register :b4s_allocation do
  name 'B4S Allocation'
  author 'Biz4Solutions'
  description 'Project allocation, bench/billable tracking and time entry approval'
  version '0.1.0'
  requires_redmine version_or_higher: '6.1.0'
end

# Plugin config/routes.rb is drawn after core routes, where core's
# GET /time_entries/:id would capture this path, so prepend it.
Rails.application.routes.prepend do
  get 'time_entries/pending_submission', :to => 'timelog#pending_submission',
      :as => 'pending_submission_time_entries'
end
