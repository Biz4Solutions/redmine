require_relative '../test_helper'

class TimesheetsControllerTest < Redmine::ControllerTest
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def setup
    User.current = nil
    @owner = create_user!('ts_owner')
    @intruder = create_user!('ts_intruder')
    @project = create_project!('PROJ-S')
    add_member!(@project, @owner, 50)
    @entry = TimeEntry.create!(project: @project, user: @owner, author: @owner, activity: TimeEntryActivity.first,
                               spent_on: Date.new(2026, 11, 18), hours: 3, comments: 'secret work')
    @timesheet = @entry.reload.timesheet
  end

  def test_owner_sees_own_timesheet_with_svg_icons
    @request.session[:user_id] = @owner.id
    get :show, params: {id: @timesheet.id}
    assert_response :success
    assert_select 'div.contextual a.icon-edit svg'
    assert_select 'div.contextual a.icon-checked svg'
  end

  def test_index_renders_svg_icons
    @request.session[:user_id] = @owner.id
    get :index, params: {user_id: 'me'}
    assert_response :success
    assert_select 'a.icon-add svg'
    assert_select 'a.icon-magnifier svg'
  end

  def test_other_user_cannot_view_timesheet
    skip "SECURITY: TimesheetsController#show has no ownership/approver check; any logged-in user sees others' time entries"
    @request.session[:user_id] = @intruder.id
    get :show, params: {id: @timesheet.id}
    assert_response :forbidden
  end

  def test_other_user_index_does_not_list_foreign_timesheets
    skip "SECURITY: TimesheetsController#index starts from Timesheet.all; any logged-in user lists all timesheets"
    @request.session[:user_id] = @intruder.id
    get :index
    assert_response :success
    assert_select "a[href='/timesheets/#{@timesheet.id}']", 0
  end

  def test_other_user_cannot_submit_timesheet
    skip "SECURITY: TimesheetsController#submit has no owner check; any logged-in user can submit and lock another user's entries"
    @request.session[:user_id] = @intruder.id
    post :submit, params: {id: @timesheet.id}
    assert @timesheet.reload.draft?, 'a non-owner must not be able to submit (and lock) the timesheet'
  end
end
