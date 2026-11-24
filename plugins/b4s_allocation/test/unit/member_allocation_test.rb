require_relative '../test_helper'

class MemberAllocationTest < ActiveSupport::TestCase
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations

  def setup
    User.current = nil
    @user = create_user!('alloc_user')
    @proj_a = create_project!('PROJ-A')
    @proj_b = create_project!('PROJ-B')
    @proj_c = create_project!('PROJ-C')
    @bench = create_project!('BENCH', bench: true)
  end

  # --- range ---

  def test_allocation_must_be_between_1_and_100_for_direct_members
    [0, -5, 101].each do |percent|
      member = build_member(@proj_a, @user, percent)
      assert_not member.valid?, "#{percent}% should be invalid"
      assert member.errors[:allocation_percentage].any?
    end
    assert build_member(@proj_a, @user, 100).valid?
  end

  # --- total cap across projects ---

  def test_total_allocation_up_to_100_is_allowed
    add_member!(@proj_a, @user, 60)
    assert build_member(@proj_b, @user, 40).valid?
  end

  def test_total_allocation_over_100_is_rejected
    add_member!(@proj_a, @user, 60)
    member = build_member(@proj_b, @user, 50)
    assert_not member.valid?
    assert_match(/exceed 100%/, member.errors[:allocation_percentage].join)
  end

  def test_total_counts_each_other_allocation_even_when_percentages_are_equal
    add_member!(@proj_a, @user, 40)
    add_member!(@proj_b, @user, 40)
    member = build_member(@proj_c, @user, 40)
    assert_not member.valid?, '40+40+40 = 120% must be rejected'
  end

  def test_updating_a_member_does_not_count_its_own_previous_value
    member = add_member!(@proj_a, @user, 80)
    member.allocation_percentage = 100
    assert member.valid?
  end

  def test_memberships_in_closed_projects_do_not_count
    add_member!(@proj_a, @user, 80)
    @proj_a.reload.close
    assert build_member(@proj_b, @user, 100).valid?
  end

  def test_expired_memberships_do_not_count
    m = add_member!(@proj_a, @user, 80)
    m.update_columns(start_date: Date.today - 30, end_date: Date.today - 1)
    assert build_member(@proj_b, @user, 100).valid?
  end

  def test_future_memberships_do_not_count_against_today
    m = add_member!(@proj_a, @user, 80)
    m.update_columns(start_date: Date.today + 10, end_date: Date.today + 40)
    assert build_member(@proj_b, @user, 100).valid?
  end

  # --- bench reduction ---

  def test_bench_allocation_is_reduced_by_the_excess_only
    bench = add_member!(@bench, @user, 100)
    add_member!(@proj_a, @user, 30)
    assert_equal 70, bench.reload.allocation_percentage
  end

  def test_bench_reduction_spans_several_bench_projects_by_the_exact_excess
    bench2_project = create_project!('BENCH2', bench: true)
    b1 = add_member!(@bench, @user, 30)
    b2 = add_member!(bench2_project, @user, 50)
    add_member!(@proj_a, @user, 60) # total 140 -> excess 40: b1 30->0, b2 50->40
    assert_equal 0, b1.reload.allocation_percentage
    assert_equal 40, b2.reload.allocation_percentage
  end

  def test_rejected_save_does_not_modify_bench_allocations
    add_member!(@proj_a, @user, 90)
    bench = add_member!(@bench, @user, 10)
    member = build_member(@proj_b, @user, 50) # 90 regular + 50 = 140, bench 10 cannot cover
    assert_not member.save
    assert_equal 10, bench.reload.allocation_percentage
  end

  def test_bench_membership_is_saved_even_when_regular_allocation_is_full
    add_member!(@proj_a, @user, 100)
    assert build_member(@bench, @user, 50).save
  end

  def test_adding_bench_membership_reduces_other_bench_memberships
    other_bench = add_member!(create_project!('BENCH2', bench: true), @user, 80)
    add_member!(@bench, @user, 50)
    assert_equal 50, other_bench.reload.allocation_percentage
  end

  def test_calling_valid_alone_does_not_modify_bench_allocations
    bench = add_member!(@bench, @user, 100)
    build_member(@proj_a, @user, 30).valid?
    assert_equal 100, bench.reload.allocation_percentage
  end

  # --- availability helpers ---

  def test_regular_and_bench_allocation_split
    add_member!(@proj_a, @user, 50)
    add_member!(@bench, @user, 50)
    assert_equal 50, Member.regular_allocation_for_user(@user.id)
    assert_equal 50, Member.bench_allocation_for_user(@user.id)
    assert_equal 100, Member.total_allocation_for_user(@user.id)
    assert_equal 50, Member.available_allocation_for_user(@user.id)
  end

  def test_available_allocation_never_negative
    add_member!(@proj_a, @user, 100)
    Member.where(id: add_member!(@proj_b, create_user!('other'), 50).id).update_all(user_id: @user.id)
    assert_equal 150, Member.regular_allocation_for_user(@user.id)
    assert_equal 0, Member.available_allocation_for_user(@user.id)
  end

  # --- dates ---

  def test_default_dates_are_today_and_three_months
    m = add_member!(@proj_a, @user, 50)
    assert_equal Date.today, m.start_date
    assert_equal 3.months.from_now.to_date, m.end_date
  end

  def test_end_date_before_start_date_is_invalid
    m = build_member(@proj_a, @user, 50, start_date: Date.today, end_date: Date.today - 1)
    assert_not m.valid?
    assert m.errors[:end_date].any?
  end

  def test_active_scope_excludes_expired_and_future_members
    current = add_member!(@proj_a, @user, 50)
    expired = add_member!(@proj_b, create_user!('u_exp'), 50)
    expired.update_columns(start_date: Date.today - 30, end_date: Date.today - 1)
    future = add_member!(@proj_c, create_user!('u_fut'), 50)
    future.update_columns(start_date: Date.today + 1)
    ids = Member.active.where(id: [current.id, expired.id, future.id]).ids
    assert_equal [current.id], ids
  end

  # --- project lifecycle ---

  def test_archiving_a_project_expires_its_allocations
    m = add_member!(@proj_a, @user, 50)
    assert @proj_a.reload.archive
    m.reload
    assert_equal 0, m.allocation_percentage
    assert_equal Date.today, m.end_date
  end

  def test_closing_a_project_expires_its_allocations
    m = add_member!(@proj_a, @user, 50)
    @proj_a.reload.close
    m.reload
    assert_equal 0, m.allocation_percentage
  end

  def test_closing_a_project_expires_allocations_of_its_subprojects
    child = create_project!('CHILD', parent: @proj_a.reload)
    m = add_member!(child, @user, 50)
    @proj_a.reload.close
    assert_equal 0, m.reload.allocation_percentage
    assert_equal Date.today, m.end_date
  end

  def test_scheduling_a_project_for_deletion_expires_its_allocations
    m = add_member!(@proj_a, @user, 50)
    Project.mark_for_deletion(@proj_a.reload)
    m.reload
    assert_equal 0, m.allocation_percentage
    assert_equal Date.today, m.end_date
  end

  def test_closing_a_project_keeps_already_ended_allocations
    m = add_member!(@proj_a, @user, 50)
    m.update_columns(start_date: Date.today - 60, end_date: Date.today - 30)
    @proj_a.reload.close
    assert_equal Date.today - 30, m.reload.end_date
    assert_equal 50, m.allocation_percentage
  end

  # --- inherited members ---

  def test_inherited_member_gets_zero_allocation
    child = create_project!('CHILD', parent: @proj_a.reload, inherit_members: true)
    add_member!(@proj_a.reload, @user, 60)
    inherited = Member.find_by(project_id: child.id, user_id: @user.id)
    assert inherited
    assert_equal 0, inherited.allocation_percentage
  end
end
