require_relative '../test_helper'

class PrincipalMembershipsAllocationControllerTest < Redmine::ControllerTest
  tests PrincipalMembershipsController
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def setup
    User.current = nil
    @request.session[:user_id] = 1
    @user = create_user!('pm_user')
    @project = create_project!('PROJ-PM')
  end

  def test_create_saves_allocation
    post :create, params: {user_id: @user.id,
                           membership: {project_ids: [@project.id], role_ids: [role.id],
                                        allocation_percentage: 30, start_date: '2026-11-01', end_date: '2027-02-28'}}
    assert_redirected_to "/users/#{@user.id}/edit?tab=memberships"
    m = Member.find_by!(project_id: @project.id, user_id: @user.id)
    assert_equal 30, m.allocation_percentage
    assert_equal Date.new(2027, 2, 28), m.end_date
  end

  def test_create_over_100_percent_shows_error
    add_member!(create_project!('PROJ-PM2'), @user, 90)
    post :create, params: {user_id: @user.id,
                           membership: {project_ids: [@project.id], role_ids: [role.id], allocation_percentage: 30}}
    assert_match(/exceed 100%/, flash[:error])
    assert_not Member.where(project_id: @project.id, user_id: @user.id).exists?
  end

  def test_update_changes_allocation
    m = add_member!(@project, @user, 30)
    put :update, params: {user_id: @user.id, id: m.id, membership: {role_ids: [role.id], allocation_percentage: 45}}
    assert_equal 45, m.reload.allocation_percentage
    assert_equal I18n.t(:notice_successful_update), flash[:notice]
  end

  def test_update_changes_dates
    m = add_member!(@project, @user, 30)
    put :update, params: {user_id: @user.id, id: m.id,
                          membership: {role_ids: [role.id], start_date: '2026-12-01', end_date: '2027-03-31'}}
    m.reload
    assert_equal Date.new(2026, 12, 1), m.start_date
    assert_equal Date.new(2027, 3, 31), m.end_date
  end

  def test_update_billable_checkbox
    m = add_member!(@project, @user, 30, billable: false)
    put :update, params: {user_id: @user.id, id: m.id, membership: {role_ids: [role.id], billable: '1'}}
    assert m.reload.billable
    put :update, params: {user_id: @user.id, id: m.id, membership: {role_ids: [role.id]}}
    assert_not m.reload.billable
  end
end
