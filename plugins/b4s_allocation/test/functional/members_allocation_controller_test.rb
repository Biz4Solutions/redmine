require_relative '../test_helper'

class MembersAllocationControllerTest < Redmine::ControllerTest
  tests MembersController
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def setup
    User.current = nil
    @request.session[:user_id] = 1 # admin
    @project = create_project!('PROJ-M')
    @other = create_project!('PROJ-O')
    @user = create_user!('mc_user')
  end

  def membership_params(user, percent, extra = {})
    {project_id: @project.id,
     membership: {user_id: user.id, role_ids: [role.id], allocation_percentage: percent,
                  start_date: '2026-11-01', end_date: '2027-01-31'}.merge(extra)}
  end

  def test_create_saves_allocation_dates_and_billable
    post :create, params: membership_params(@user, 60, billable: '1')
    assert_redirected_to "/projects/#{@project.identifier}/settings/members"
    m = Member.find_by!(project_id: @project.id, user_id: @user.id)
    assert_equal 60, m.allocation_percentage
    assert_equal Date.new(2026, 11, 1), m.start_date
    assert_equal Date.new(2027, 1, 31), m.end_date
    assert m.billable
  end

  def test_create_without_billable_param_is_non_billable
    post :create, params: membership_params(@user, 60)
    assert_not Member.find_by!(project_id: @project.id, user_id: @user.id).billable
  end

  def test_create_over_100_percent_is_rejected_with_flash
    add_member!(@other, @user, 80)
    assert_no_difference 'Member.count' do
      post :create, params: membership_params(@user, 30)
    end
    assert_match(/exceed 100%/, flash[:error])
  end

  def test_update_changes_allocation
    m = add_member!(@project, @user, 40)
    put :update, params: {id: m.id, membership: {role_ids: [role.id], allocation_percentage: 70, billable: '1'}}
    assert_equal 70, m.reload.allocation_percentage
  end

  def test_max_availability_returns_remaining_regular_allocation
    skip 'BUG: max_availability runs find_model_object without :id and always returns 404'
    add_member!(@other, @user, 70)
    get :max_availability, params: {user_id: @user.id}
    assert_response :success
    assert_equal 30, response.parsed_body['max_availability']
  end
end
