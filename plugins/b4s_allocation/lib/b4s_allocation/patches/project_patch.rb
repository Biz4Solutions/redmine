module B4sAllocation
  module Patches
    # Uppercase project identifiers (max 20 chars), the bench project flag, and
    # expiring member allocations when a project is closed, archived or
    # scheduled for deletion.
    module ProjectPatch
      extend ActiveSupport::Concern

      IDENTIFIER_MAX_LENGTH = 20
      IDENTIFIER_PATTERN_STR = '^[A-Z0-9][A-Z0-9\-_]*$'
      IDENTIFIER_PATTERN = /\A#{IDENTIFIER_PATTERN_STR}\z/

      prepended do
        # Replace core's identifier length (100) and lowercase format rules.
        # Core forms read Project::IDENTIFIER_MAX_LENGTH, so swap the constant too.
        identifier_rules = _validate_callbacks.map(&:filter).select do |v|
          (v.is_a?(ActiveModel::Validations::LengthValidator) ||
            v.is_a?(ActiveModel::Validations::FormatValidator)) && v.attributes == [:identifier]
        end
        identifier_rules.each { |v| skip_callback(:validate, :before, v) }
        _validators[:identifier] -= identifier_rules
        remove_const(:IDENTIFIER_MAX_LENGTH)
        const_set(:IDENTIFIER_MAX_LENGTH, ProjectPatch::IDENTIFIER_MAX_LENGTH)

        validates_length_of :identifier, :maximum => IDENTIFIER_MAX_LENGTH
        validates_format_of :identifier, :with => IDENTIFIER_PATTERN,
                            :if => proc {|p| p.identifier_changed?}

        after_update :expire_member_allocations,
                     :if => proc {|project|
                       project.saved_change_to_status? &&
                                    [Project::STATUS_CLOSED, Project::STATUS_ARCHIVED, Project::STATUS_SCHEDULED_FOR_DELETION].include?(project.status)
                     }

        safe_attributes 'bench_project'
      end

      class_methods do
        def mark_for_deletion(projects)
          ids = Array(projects).flat_map {|p| p.reload.self_and_descendants.pluck(:id)}
          Member.expire_allocations_for_project(ids, Date.today)
          super
        end
      end

      # Core closes with update_all, which skips the after_update expiry callback.
      def close
        Member.expire_allocations_for_project(self_and_descendants.status(Project::STATUS_ACTIVE).ids, Date.today)
        super
      end

      def expire_member_allocations
        # Expire all member allocations for this project when it's closed, archived, or scheduled for deletion
        Member.expire_allocations_for_project(id, Date.today)
      end
    end
  end
end
