require File.expand_path('../../../test/test_helper', __dir__)

module B4sAllocation
  # Builds isolated records so totals never include core fixture members
  # (whose allocation_percentage defaults to 100).
  module TestHelpers
    def create_user!(login)
      user = User.new(firstname: login, lastname: 'Test', mail: "#{login}@example.test")
      user.login = login
      user.save!
      user
    end

    def create_project!(identifier, bench: false, parent: nil, inherit_members: false)
      project = Project.new(name: identifier, identifier: identifier, bench_project: bench,
                            inherit_members: inherit_members)
      project.enabled_module_names = %w(time_tracking)
      project.save!
      project.set_parent!(parent) if parent
      project.reload
    end

    def role
      @role ||= Role.find(1)
    end

    def add_member!(project, user, percent, **attrs)
      Member.create!({project: project, principal: user, role_ids: [role.id],
                      allocation_percentage: percent}.merge(attrs))
    end

    def build_member(project, user, percent, **attrs)
      Member.new({project: project, principal: user, role_ids: [role.id],
                  allocation_percentage: percent}.merge(attrs))
    end
  end
end
