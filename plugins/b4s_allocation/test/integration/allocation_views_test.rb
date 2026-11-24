require_relative '../test_helper'

# Pins what the custom views render, so moving them into the plugin
# (overrides and hooks) can be checked against the original output.
class AllocationViewsTest < Redmine::IntegrationTest
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def setup
    @user = create_user!('view_user')
    @project = create_project!('PROJ-V')
    @bench = create_project!('BENCH-V', bench: true)
    @member = add_member!(@project, @user, 60, billable: false)
    add_member!(@bench, @user, 40)
    log_user('admin', 'admin')
  end

  def test_user_profile_shows_allocation_tabs
    get "/users/#{@user.id}"
    assert_response :success
    assert_select 'div.allocations-container div.tab-button[data-tab=active-allocations]'
    assert_select 'div.total-allocation', /100/
    assert_select 'div.allocations-table div.table-row', :minimum => 1
  end

  def test_project_settings_members_shows_allocation_columns
    get "/projects/#{@project.identifier}/settings/members"
    assert_response :success
    assert_select 'table.members th', :text => I18n.t(:field_allocation_percentage)
    assert_select "tr#member-#{@member.id} td.allocation", /60/
    assert_select "tr#member-#{@member.id} td.billable", I18n.t(:general_text_no)
    assert_select "tr#member-#{@member.id}", /Max Availability - 40/
  end

  def test_project_form_has_bench_checkbox
    get "/projects/#{@project.identifier}/settings"
    assert_response :success
    assert_select 'input[type=checkbox][name="project[bench_project]"]'
  end

  def test_bench_project_overview_shows_bench_label
    get "/projects/#{@bench.identifier}"
    assert_response :success
    assert_select 'li', /#{I18n.t(:label_bench_project)}/
    get "/projects/#{@project.identifier}"
    assert_select 'li', :text => /#{I18n.t(:label_bench_project)}/, :count => 0
  end

  def test_user_memberships_tab_shows_allocation
    get "/users/#{@user.id}/edit", params: {tab: 'memberships'}
    assert_response :success
    assert_select "tr#member-#{@member.id}", /60/
  end

  def test_new_user_membership_form_has_allocation_fields
    get "/users/#{@user.id}/memberships/new", xhr: true
    assert_response :success
    assert_include 'membership[allocation_percentage]', response.body
  end

  def test_member_edit_form_has_allocation_fields
    get "/memberships/#{@member.id}/edit", xhr: true
    assert_response :success
    assert_include 'membership[allocation_percentage]', response.body
  end

  def test_time_entry_context_menu_has_reject_dialog_for_approvers
    entry = TimeEntry.create!(project: @project, user: @user, author: @user, activity: TimeEntryActivity.first,
                              spent_on: Date.new(2026, 11, 18), hours: 1)
    get '/time_entries/context_menu', params: {ids: [entry.id]}, xhr: true
    assert_response :success
    assert_select '#bulk-reject-dialog', 1
  end

  def test_stylesheet_rule_for_member_picker_is_served
    get '/'
    css_hrefs = css_select('link[rel=stylesheet]').map { |l| l['href'] }
    body = css_hrefs.map { |h| get(h.sub(%r{\Ahttps?://[^/]+}, '')); response.body }.join
    assert_include '#principals_for_new_member .objects-selection #principals', body
  end
end
