require_relative '../test_helper'

class TimeEntryApprovalTest < ActiveSupport::TestCase
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def setup
    User.current = nil
    ActionMailer::Base.deliveries.clear
    @user = create_user!('te_user')
    @manager = create_user!('te_manager')
    @project = create_project!('PROJ-T')
    add_member!(@project, @user, 50)
    add_member!(@project, @manager, 50)
    role.add_permission!(:approve_time_entries)
    @activity = TimeEntryActivity.find_by(is_default: true) || TimeEntryActivity.first
  end

  def log_time(user: @user, spent_on: Date.new(2026, 11, 18), hours: 2)
    TimeEntry.create!(project: @project, user: user, author: user, activity: @activity,
                      spent_on: spent_on, hours: hours)
  end

  # --- membership requirement ---

  def test_time_entry_requires_membership_in_project
    outsider = create_user!('te_outsider')
    entry = TimeEntry.new(project: @project, user: outsider, author: outsider, activity: @activity,
                          spent_on: Date.today, hours: 1)
    assert_not entry.valid?
    assert_includes entry.errors[:base], I18n.t(:error_user_not_allocated_to_project)
  end

  # --- default status and timesheet auto-assignment ---

  def test_new_entry_is_pending_and_assigned_to_weekly_draft_timesheet
    entry = log_time(spent_on: Date.new(2026, 11, 18)) # Wednesday
    assert_equal TimeEntry::STATUS_PENDING, entry.reload.status
    sheet = entry.timesheet
    assert sheet
    assert_equal Date.new(2026, 11, 16), sheet.start_date # Monday
    assert_equal Date.new(2026, 11, 22), sheet.end_date
    assert sheet.draft?
  end

  def test_entries_in_same_week_share_one_timesheet
    a = log_time(spent_on: Date.new(2026, 11, 16))
    b = log_time(spent_on: Date.new(2026, 11, 22))
    assert_equal a.reload.timesheet_id, b.reload.timesheet_id
  end

  def test_moving_entry_to_another_week_moves_it_and_drops_empty_timesheet
    entry = log_time(spent_on: Date.new(2026, 11, 18))
    old_id = entry.reload.timesheet_id
    entry.update!(spent_on: Date.new(2026, 11, 25))
    assert_not_equal old_id, entry.reload.timesheet_id
    assert_not Timesheet.exists?(old_id)
  end

  def test_creating_entry_sends_no_mail_while_timesheet_is_draft
    log_time
    assert_empty ActionMailer::Base.deliveries
  end

  # --- approval ---

  def test_manager_can_approve_pending_entry
    entry = log_time
    assert entry.can_approve?(@manager)
    assert entry.approve(@manager)
    entry.reload
    assert entry.approved?
    assert_equal @manager.id, entry.approved_by_id
    assert_not_nil entry.approved_on
  end

  def test_user_cannot_approve_own_entry
    entry = log_time
    assert_not entry.can_approve?(@user)
    assert_not entry.approve(@user)
  end

  def test_user_without_permission_cannot_approve
    role.remove_permission!(:approve_time_entries)
    entry = log_time
    assert_not entry.can_approve?(@manager)
  end

  def test_approval_sends_mail_to_author
    entry = log_time
    ActionMailer::Base.deliveries.clear
    entry.approve(@manager)
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_includes ActionMailer::Base.deliveries.last.to, @user.mail
  end

  def test_reject_stores_reason_and_sends_mail
    entry = log_time
    ActionMailer::Base.deliveries.clear
    assert entry.reject(@manager, 'wrong project')
    entry.reload
    assert entry.rejected?
    assert_equal 'wrong project', entry.rejection_reason
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  def test_approved_entry_hours_cannot_be_changed
    entry = log_time
    entry.approve(@manager)
    entry.reload.hours = 5
    assert_not entry.save
    assert_includes entry.errors[:base], I18n.t(:error_cannot_modify_approved_time_entry)
  end

  def test_approved_entry_comment_can_still_be_changed
    entry = log_time
    entry.approve(@manager)
    entry.reload.comments = 'note'
    assert entry.save
  end

  # --- timesheet ---

  def test_timesheet_must_span_exactly_one_week
    sheet = Timesheet.new(user: @user, start_date: Date.new(2026, 11, 16), end_date: Date.new(2026, 11, 20),
                          status: Timesheet::STATUS_DRAFT)
    assert_not sheet.valid?
  end

  def test_timesheets_cannot_overlap
    log_time(spent_on: Date.new(2026, 11, 18))
    sheet = Timesheet.new(user: @user, start_date: Date.new(2026, 11, 18), end_date: Date.new(2026, 11, 24),
                          status: Timesheet::STATUS_DRAFT)
    assert_not sheet.valid?
  end

  def test_submit_then_approve_timesheet_approves_entries
    entry = log_time
    sheet = entry.reload.timesheet
    assert sheet.submit
    assert sheet.reload.pending_approval?
    assert sheet.approve(@manager)
    assert sheet.reload.approved?
    assert entry.reload.approved?
  end

  def test_entries_of_submitted_timesheet_are_locked
    entry = log_time
    entry.reload.timesheet.submit
    entry.reload.hours = 7
    assert_not entry.save
    assert_includes entry.errors[:base], I18n.t(:error_cannot_modify_time_entry_in_submitted_timesheet)
  end

  def test_timesheet_reject_requires_reason
    entry = log_time
    sheet = entry.reload.timesheet
    sheet.submit
    assert_not sheet.reject(@manager, '')
    assert sheet.reject(@manager, 'missing day')
    assert entry.reload.rejected?
  end
end
