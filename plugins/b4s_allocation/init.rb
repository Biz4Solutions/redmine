Redmine::Plugin.register :b4s_allocation do
  name 'B4S Allocation'
  author 'Biz4Solutions'
  description 'Project allocation, bench/billable tracking and time entry approval'
  version '0.1.0'
  requires_redmine version_or_higher: '6.1.0'
end

# Core classes are reloaded in development and init.rb runs on every
# reload (to_prepare), so patch each fresh class once.
{
  Member => B4sAllocation::Patches::MemberPatch,
  MemberRole => B4sAllocation::Patches::MemberRolePatch,
  Project => B4sAllocation::Patches::ProjectPatch,
  TimeEntry => B4sAllocation::Patches::TimeEntryPatch,
  TimeEntryQuery => B4sAllocation::Patches::TimeEntryQueryPatch,
}.each do |klass, patch|
  klass.prepend(patch) unless klass < patch
end
Mailer.include(B4sAllocation::Patches::MailerPatch) unless Mailer < B4sAllocation::Patches::MailerPatch

# Plugin config/routes.rb is drawn after core routes, where core's
# GET /time_entries/:id would capture this path, so prepend it.
Rails.application.routes.prepend do
  get 'time_entries/pending_submission', :to => 'timelog#pending_submission',
      :as => 'pending_submission_time_entries'
end
