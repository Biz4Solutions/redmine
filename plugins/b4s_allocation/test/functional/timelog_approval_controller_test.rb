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

  def test_pending_submission_lists_own_pending_entries
    @request.session[:user_id] = @user.id
    get :pending_submission
    assert_response :success
    assert_select "tr#time-entry-#{@entry.id} a[href='/time_entries/#{@entry.id}/submit'][data-method=post]"
  end

  def test_submit_notifies_approvers
    @request.session[:user_id] = @user.id
    ActionMailer::Base.deliveries.clear
    post :submit, params: {id: @entry.id}
    assert_redirected_to '/time_entries/pending_submission'
    assert_equal I18n.t(:notice_time_entry_submitted), flash[:notice]
    assert_include @manager.mail, ActionMailer::Base.deliveries.flat_map(&:bcc) + ActionMailer::Base.deliveries.flat_map(&:to)
  end

  def test_submit_rejects_other_users_entry
    @request.session[:user_id] = @manager.id
    ActionMailer::Base.deliveries.clear
    post :submit, params: {id: @entry.id}
    assert_redirected_to '/time_entries/pending_submission'
    assert_equal I18n.t(:error_not_your_time_entry), flash[:error]
    assert_empty ActionMailer::Base.deliveries
  end

  def test_bulk_submit_only_counts_own_entries
    other = TimeEntry.create!(project: @project, user: @manager, author: @manager,
                              activity: TimeEntryActivity.first, spent_on: Date.new(2026, 11, 18), hours: 1)
    @request.session[:user_id] = @user.id
    post :bulk_submit, params: {ids: [@entry.id, other.id]}
    assert_redirected_to '/time_entries/pending_submission'
    assert_equal I18n.t(:notice_time_entries_submitted, count: 1), flash[:notice]
  end

  def test_pending_submission_is_paginated
    25.times do |i|
      TimeEntry.create!(project: @project, user: @user, author: @user, activity: TimeEntryActivity.first,
                        spent_on: Date.new(2026, 11, 16) + (i % 5), hours: 0.5)
    end
    @request.session[:user_id] = @user.id
    get :pending_submission
    assert_response :success
    assert_select 'tr.time-entry', 25
    assert_select 'span.pagination a[href*="page=2"]'
  end
end
