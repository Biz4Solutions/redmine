class AddBenchProjectFlag < ActiveRecord::Migration[6.1]
  include B4sAllocation::CoreMigration

  def change
    return if applied_in_core?

    add_column :projects, :bench_project, :boolean, default: false, null: false
  end
end
