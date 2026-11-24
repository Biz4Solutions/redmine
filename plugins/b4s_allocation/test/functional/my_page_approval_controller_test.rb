require_relative '../test_helper'

class MyPageApprovalControllerTest < Redmine::ControllerTest
  tests MyController
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def setup
    User.current = nil
    @user = create_user!('mp_user')
    @project = create_project!('PROJ-MP')
    add_member!(@project, @user, 50)
    @request.session[:user_id] = @user.id
  end

  def test_page_removes_pending_timesheets_block_without_permission
    @user.pref.my_page_layout = {'top' => ['issuesassignedtome', 'pending_timesheets']}
    @user.pref.save!
    get :page
    assert_response :success
    assert_not_includes @user.pref.reload.my_page_layout.values.flatten, 'pending_timesheets'
  end

  def test_page_gives_approvers_the_approver_default_layout
    role.add_permission!(:approve_time_entries)
    get :page
    assert_response :success
    assert_equal Redmine::MyPage.default_layout_for_approvers, @user.pref.reload.my_page_layout
  end

  def test_block_select_hides_pending_timesheets_option_without_permission
    get :page
    assert_select 'select#block-select option[value=pending_timesheets]', 0
  end

  def test_dormant_timesheet_blocks_are_not_offered
    keys = Redmine::MyPage.blocks.keys
    %w(pending_timesheets my_pending_time_entries my_timesheets pending_timesheet_approvals).each do |block|
      assert_not_includes keys, block
    end
  end
end
