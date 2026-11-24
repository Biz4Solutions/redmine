Redmine::Plugin.register :b4s_allocation do
  name 'B4S Allocation'
  author 'Biz4Solutions'
  description 'Project allocation, bench/billable tracking and time entry approval'
  version '0.1.0'
  requires_redmine version_or_higher: '6.1.0'

  project_module :time_tracking do
    permission :approve_time_entries, {:timelog => [:approve, :reject]}, :require => :member
  end
end

# Show "Spent time" to anyone who can view or log time (core also requires a
# visible project with time tracking enabled).
Redmine::MenuManager.map :application_menu do |menu|
  menu.delete :time_entries
  menu.push(
    :time_entries,
    {:controller => 'timelog', :action => 'index'},
    :caption => :label_spent_time,
    :after => :issues,
    :if => Proc.new do
      User.current.allowed_to?(:view_time_entries, nil, :global => true) ||
      User.current.allowed_to?(:log_time, nil, :global => true)
    end
  )
end

# Core classes are reloaded in development and init.rb runs on every
# reload (to_prepare), so patch each fresh class once.
{
  Member => B4sAllocation::Patches::MemberPatch,
  MemberRole => B4sAllocation::Patches::MemberRolePatch,
  Project => B4sAllocation::Patches::ProjectPatch,
  TimeEntry => B4sAllocation::Patches::TimeEntryPatch,
  TimeEntryQuery => B4sAllocation::Patches::TimeEntryQueryPatch,
  MembersHelper => B4sAllocation::Patches::MembersHelperPatch,
  MyHelper => B4sAllocation::Patches::MyHelperPatch,
  MembersController => B4sAllocation::Patches::MembersControllerPatch,
  PrincipalMembershipsController => B4sAllocation::Patches::PrincipalMembershipsControllerPatch,
  MyController => B4sAllocation::Patches::MyControllerPatch,
  TimelogController => B4sAllocation::Patches::TimelogControllerPatch,
}.each do |klass, patch|
  klass.prepend(patch) unless klass < patch
end
Redmine::MyPage.singleton_class.prepend(B4sAllocation::Patches::MyPagePatch) unless Redmine::MyPage.singleton_class < B4sAllocation::Patches::MyPagePatch
Mailer.include(B4sAllocation::Patches::MailerPatch) unless Mailer < B4sAllocation::Patches::MailerPatch

# Registers the view hooks (ViewListener subclasses register on load).
B4sAllocation::Hooks

# Plugin config/routes.rb is drawn after core routes, where core's
# GET /time_entries/:id would capture this path, so prepend it.
Rails.application.routes.prepend do
  get 'time_entries/pending_submission', :to => 'timelog#pending_submission',
      :as => 'pending_submission_time_entries'
end
