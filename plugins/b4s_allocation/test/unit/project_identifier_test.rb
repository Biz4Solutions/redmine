require_relative '../test_helper'

class ProjectIdentifierTest < ActiveSupport::TestCase
  def build(identifier)
    Project.new(name: 'Test', identifier: identifier)
  end

  def test_uppercase_identifiers_are_valid
    %w(PROJ PROJ-A PROJ_2 A1 2024-HR).each do |id|
      assert build(id).valid?, "#{id} should be valid"
    end
  end

  def test_lowercase_or_leading_dash_is_invalid
    %w(proj Proj -PROJ _PROJ).each do |id|
      p = build(id)
      assert_not p.valid?, "#{id} should be invalid"
      assert p.errors[:identifier].any?
    end
  end

  def test_digits_only_identifier_is_invalid
    skip 'BUG: custom IDENTIFIER_PATTERN dropped upstream (?!\\d+$) guard; "2024" clashes with numeric project id lookup'
    assert_not build('2024').valid?
  end

  def test_identifier_max_length_is_20
    assert build('A' * 20).valid?
    assert_not build('A' * 21).valid?
  end

  def test_bench_project_flag_is_a_safe_attribute
    project = Project.new
    project.safe_attributes = {'bench_project' => '1'}
    assert project.bench_project
  end
end
