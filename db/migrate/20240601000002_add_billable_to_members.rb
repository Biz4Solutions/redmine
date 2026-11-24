class AddBillableToMembers < ActiveRecord::Migration[6.1]
  def change
    add_column :members, :billable, :boolean, default: true, null: false
  end
end
