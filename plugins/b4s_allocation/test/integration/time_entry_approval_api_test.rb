require_relative '../test_helper'

class TimeEntryApprovalApiTest < Redmine::ApiTest::Base
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def test_approve_via_api_key
    user = create_user!('api_te_user')
    manager = create_user!('api_te_manager')
    manager.password = manager.password_confirmation = 'Secret-pass-1'
    manager.save!
    project = create_project!('PROJ-AA')
    add_member!(project, user, 50)
    add_member!(project, manager, 50)
    role.add_permission!(:approve_time_entries)
    entry = TimeEntry.create!(project: project, user: user, author: user, activity: TimeEntryActivity.first,
                              spent_on: Date.new(2026, 11, 18), hours: 1)
    post "/time_entries/#{entry.id}/approve.json", headers: credentials(manager.login, 'Secret-pass-1')
    assert_response :no_content
    assert entry.reload.approved?
  end
end
