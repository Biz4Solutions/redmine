class AddApproveTimeEntriesPermissionToManager < ActiveRecord::Migration[6.1]
  def up
    manager_role = Role.where(name: 'Manager').first
    if manager_role
      manager_role.add_permission!(:approve_time_entries)
    end
  end

  def down
    manager_role = Role.where(name: 'Manager').first
    if manager_role
      manager_role.remove_permission!(:approve_time_entries)
    end
  end
end 