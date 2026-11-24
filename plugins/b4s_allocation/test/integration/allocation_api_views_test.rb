require_relative '../test_helper'

class AllocationApiViewsTest < Redmine::ApiTest::Base
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def setup
    super
    @user = create_user!('apiv_user')
    @project = create_project!('PROJ-AV')
    @member = add_member!(@project, @user, 60)
  end

  def test_project_memberships_index_includes_allocation
    get "/projects/#{@project.id}/memberships.json", headers: credentials('admin')
    m = response.parsed_body['memberships'].find { |x| x['id'] == @member.id }
    assert_equal 60.0, m['allocation_percentage'].to_f
  end

  def test_user_show_includes_membership_allocation
    get "/users/#{@user.id}.json", params: {include: 'memberships'}, headers: credentials('admin')
    m = response.parsed_body['user']['memberships'].first
    assert_equal 60.0, m['allocation_percentage'].to_f
    assert m.key?('active')
    assert m.key?('expired')
  end

  def test_time_entry_show_includes_status
    entry = TimeEntry.create!(project: @project, user: @user, author: @user, activity: TimeEntryActivity.first,
                              spent_on: Date.new(2026, 11, 18), hours: 1)
    get "/time_entries/#{entry.id}.json", headers: credentials('admin')
    assert_equal 'pending', response.parsed_body['time_entry']['status']
    get "/time_entries.json", params: {project_id: @project.id}, headers: credentials('admin')
    assert_equal 'pending', response.parsed_body['time_entries'].first['status']
  end
end
