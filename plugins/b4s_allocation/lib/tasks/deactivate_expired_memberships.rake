namespace :redmine do
  desc 'Deactivate expired memberships'
  task :deactivate_expired_memberships => :environment do
    Member.deactivate_expired
  end
end
