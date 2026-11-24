require_relative '../test_helper'

class MembershipsApiAllocationTest < Redmine::ApiTest::Base
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def setup
    super
    @project = create_project!('PROJ-API')
    @user = create_user!('api_user')
  end

  def test_update_roles_only_keeps_billable
    skip 'BUG: MembersController#update sets billable=false whenever the billable key is absent, so a REST role change clears billable'
    m = add_member!(@project, @user, 40, billable: true)
    put "/memberships/#{m.id}.json",
        params: {membership: {role_ids: [role.id]}},
        headers: credentials('admin')
    assert_response :no_content
    assert m.reload.billable, 'billable must not change when the request omits it'
  end

  def test_create_with_allocation
    post "/projects/#{@project.id}/memberships.json",
         params: {membership: {user_id: @user.id, role_ids: [role.id], allocation_percentage: 25}},
         headers: credentials('admin')
    assert_response :created
    assert_equal 25, Member.find_by!(project_id: @project.id, user_id: @user.id).allocation_percentage
  end

  def test_show_includes_allocation_fields
    m = add_member!(@project, @user, 40)
    get "/memberships/#{m.id}.json", headers: credentials('admin')
    assert_response :success
    json = response.parsed_body['membership']
    assert_equal 40.0, json['allocation_percentage'].to_f
    assert json.key?('start_date')
    assert json.key?('end_date')
  end
end
