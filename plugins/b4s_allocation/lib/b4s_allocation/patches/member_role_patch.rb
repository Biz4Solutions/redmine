module B4sAllocation
  module Patches
    # Members inherited by subprojects start with 0% allocation.
    module MemberRolePatch
      private

      # Copy of core MemberRole#add_role_to_subprojects that sets 0% allocation
      # on newly created inherited memberships.
      def add_role_to_subprojects
        return if member.project.leaf?

        member.project.children.where(:inherit_members => true).ids.each do |subproject_id|
          child_member = Member.find_or_initialize_by(:project_id => subproject_id, :user_id => member.user_id)
          child_member.allocation_percentage = 0 if child_member.new_record?
          child_member.member_roles << MemberRole.new(:role => role, :inherited_from => id)
          child_member.save!
        end
      end
    end
  end
end
