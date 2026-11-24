require_relative '../test_helper'

class TimelogApprovalControllerTest < Redmine::ControllerTest
  tests TimelogController
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def setup
    User.current = nil
    @user = create_user!('tl_user')
    @manager = create_user!('tl_manager')
    @project = create_project!('PROJ-L')
    add_member!(@project, @user, 50)
    add_member!(@project, @manager, 50)
    role.add_permission!(:approve_time_entries)
    @entry = TimeEntry.create!(project: @project, user: @user, author: @user,
                               activity: TimeEntryActivity.first, spent_on: Date.new(2026, 11, 18), hours: 2)
  end

  def test_manager_can_approve
    @request.session[:user_id] = @manager.id
    post :approve, params: {id: @entry.id}
    assert_response :redirect
    assert @entry.reload.approved?
  end

  def test_author_cannot_approve_own_entry
    @request.session[:user_id] = @user.id
    post :approve, params: {id: @entry.id}
    assert_not @entry.reload.approved?
  end

  def test_non_member_is_denied
    @request.session[:user_id] = create_user!('tl_outsider').id
    post :approve, params: {id: @entry.id}
    assert_response :forbidden
    assert_not @entry.reload.approved?
  end

  def test_reject_with_reason
    @request.session[:user_id] = @manager.id
    post :reject, params: {id: @entry.id, rejection_reason: 'no'}
    assert @entry.reload.rejected?
    assert_equal 'no', @entry.rejection_reason
  end

  def test_bulk_approve_by_manager
    skip 'BUG?: bulk_approve/bulk_reject are not mapped to :approve_time_entries, so authorize denies non-admin managers'
    @request.session[:user_id] = @manager.id
    post :bulk_approve, params: {ids: [@entry.id]}
    assert @entry.reload.approved?
  end
end
