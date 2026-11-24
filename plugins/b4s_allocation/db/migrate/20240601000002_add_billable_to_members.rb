class AddBillableToMembers < ActiveRecord::Migration[6.1]
  include B4sAllocation::CoreMigration

  def change
    return if applied_in_core?

    add_column :members, :billable, :boolean, default: true, null: false
  end
end
