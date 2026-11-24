# This seeder updates end dates for expired allocations based on the last time entry
# It only updates allocations that have expired (end_date < Date.today)

puts "Updating end dates for expired allocations based on last time entry..."

# Find all expired memberships
expired_memberships = Member.where("end_date < ?", Date.today)
                           .where("allocation_percentage > 0")

total = expired_memberships.count
puts "Found #{total} expired memberships to process"

expired_memberships.find_each.with_index(1) do |membership, index|
  # Find the last time entry for this user in this project
  last_time_entry = TimeEntry.where(user_id: membership.user_id, project_id: membership.project_id)
                            .order(spent_on: :desc)
                            .first

  if last_time_entry
    # Update the end date to the last time entry date
    membership.update_column(:end_date, last_time_entry.spent_on)
    puts "[#{index}/#{total}] Updated membership ##{membership.id} end date to #{last_time_entry.spent_on}"
  else
    puts "[#{index}/#{total}] No time entries found for membership ##{membership.id}"
  end
end

puts "Finished updating end dates for expired allocations"
