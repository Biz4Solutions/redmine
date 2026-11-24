require_relative '../../test_helper'

class B4sAllocationRoutingTest < Redmine::RoutingTest
  def test_time_entry_approval
    should_route 'POST /time_entries/22/approve' => 'timelog#approve', :id => '22'
    should_route 'POST /time_entries/22/reject' => 'timelog#reject', :id => '22'
    should_route 'POST /time_entries/bulk_approve' => 'timelog#bulk_approve'
    should_route 'POST /time_entries/bulk_reject' => 'timelog#bulk_reject'
    should_route 'POST /time_entries/1/submit' => 'timelog#submit', :id => '1'
    should_route 'POST /time_entries/bulk_submit' => 'timelog#bulk_submit'
  end

  def test_pending_submission
    should_route 'GET /time_entries/pending_submission' => 'timelog#pending_submission'
  end

  def test_timesheets
    should_route 'GET /timesheets' => 'timesheets#index'
    should_route 'GET /timesheets/new' => 'timesheets#new'
    should_route 'POST /timesheets' => 'timesheets#create'
    should_route 'GET /timesheets/3' => 'timesheets#show', :id => '3'
    should_route 'GET /timesheets/3/edit' => 'timesheets#edit', :id => '3'
    should_route 'PATCH /timesheets/3' => 'timesheets#update', :id => '3'
    should_route 'DELETE /timesheets/3' => 'timesheets#destroy', :id => '3'
    should_route 'POST /timesheets/3/submit' => 'timesheets#submit', :id => '3'
    should_route 'POST /timesheets/bulk_submit' => 'timesheets#bulk_submit'
    should_route 'POST /timesheets/bulk_approve' => 'timesheets#bulk_approve'
    should_route 'POST /timesheets/bulk_reject' => 'timesheets#bulk_reject'
    should_route 'GET /timesheets/pending_approval' => 'timesheets#pending_approval'
  end

  def test_max_availability
    should_route 'GET /members/max_availability/7' => 'members#max_availability', :user_id => '7'
  end

  def test_route_helpers_exist
    h = Rails.application.routes.url_helpers
    assert_equal '/time_entries/1/approve', h.approve_time_entry_path(1)
    assert_equal '/time_entries/bulk_approve', h.bulk_approve_time_entries_path
    assert_equal '/time_entries/pending_submission', h.pending_submission_time_entries_path
    assert_equal '/timesheets/1/submit', h.submit_timesheet_path(1)
    assert_equal '/timesheets/pending_approval', h.pending_approval_timesheets_path
  end
end
