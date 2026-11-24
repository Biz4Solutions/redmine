module B4sAllocation
  module Patches
    # Allocation fields, caps and bench handling on project memberships.
    module MemberPatch
      extend ActiveSupport::Concern

      prepended do
        validate :validate_allocation_percentage
        validate :validate_dates

        before_save :set_default_dates
        after_save :reduce_bench_allocations

        # Only memberships of active users in active projects within their dates.
        scope :active, (lambda do
          joins(:principal, :project).where(:users => {:status => Principal::STATUS_ACTIVE})
            .where(:projects => {:status => Project::STATUS_ACTIVE})
            .where("(members.end_date IS NULL OR members.end_date >= ?)", Date.today)
            .where("(members.start_date IS NULL OR members.start_date <= ?)", Date.today)
        end)
      end

      class_methods do
        # Copy of core Member.create_principal_memberships that also sets the
        # allocation fields before saving each membership.
        def create_principal_memberships(principal, attributes)
          members = []
          if attributes
            project_ids = Array.wrap(attributes[:project_ids] || attributes[:project_id])
            role_ids = Array.wrap(attributes[:role_ids])
            project_ids.each do |project_id|
              member = Member.find_or_initialize_by(:project_id => project_id, :user_id => principal.id)
              member.role_ids |= role_ids

              # Set allocation fields
              member.allocation_percentage = attributes[:allocation_percentage] if attributes[:allocation_percentage].present?
              member.start_date = attributes[:start_date] if attributes[:start_date].present?
              member.end_date = attributes[:end_date] if attributes[:end_date].present?
              member.billable = attributes[:billable] if attributes[:billable].present?

              # Save the member but don't raise an exception if it fails
              # This allows us to collect all errors
              member.save
              members << member
            end
          end
          members
        end
        # Returns the total allocation percentage for a user across all active projects
        def total_allocation_for_user(user_id, date=Date.today)
          joins(:principal, :project)
            .where(user_id: user_id)
            .where(users: { status: Principal::STATUS_ACTIVE })  # Only include active users
            .where(projects: { status: Project::STATUS_ACTIVE })  # Only include active projects
            .where("(end_date IS NULL OR end_date >= ?)", date)  # Only check end date
            .where("allocation_percentage > 0")  # Exclude deactivated memberships
            .sum(:allocation_percentage) || 0
        end

        # Returns the total allocation percentage for a user across all active non-bench projects
        def regular_allocation_for_user(user_id, date=Date.today)
          joins(:principal, :project)
            .where(user_id: user_id)
            .where(users: { status: Principal::STATUS_ACTIVE })
            .where(projects: { status: Project::STATUS_ACTIVE })  # Only include active projects
            .where("(end_date IS NULL OR end_date >= ?)", date)
            .where("allocation_percentage > 0")
            .where(projects: { bench_project: false })
            .sum(:allocation_percentage) || 0
        end

        # Returns the total allocation percentage for a user across all active bench projects
        def bench_allocation_for_user(user_id, date=Date.today)
          joins(:principal, :project)
            .where(user_id: user_id)
            .where(users: { status: Principal::STATUS_ACTIVE })
            .where(projects: { status: Project::STATUS_ACTIVE })  # Only include active projects
            .where("(end_date IS NULL OR end_date >= ?)", date)
            .where("allocation_percentage > 0")
            .where(projects: { bench_project: true })
            .sum(:allocation_percentage) || 0
        end

        # Returns the available allocation percentage for a user
        def available_allocation_for_user(user_id, date=Date.today)
          regular_allocation = regular_allocation_for_user(user_id, date)
          [100 - regular_allocation, 0].max
        end

        # Deactivate expired memberships
        def deactivate_expired
          where("end_date < ?", Date.today).find_each do |member|
            # We don't actually delete the membership, just mark it as inactive
            # by setting allocation_percentage to 0
            member.update_column(:allocation_percentage, 0)
          end
        end

        # Expire all member allocations for a project when it's closed, archived, or scheduled for deletion
        def expire_allocations_for_project(project_id, expiration_date)
          # Find all active memberships for this project that haven't already expired
          memberships = joins(:project)
                        .where(project_id: project_id)
                        .where("(end_date IS NULL OR end_date > ?)", expiration_date)
                        .where("allocation_percentage > 0")

          memberships.find_each do |membership|
            # Set the end_date to the expiration date and set allocation_percentage to 0
            membership.update_columns(
              end_date: expiration_date,
              allocation_percentage: 0
            )
          end
        end
      end

      # Returns true if the member is active on the given date
      def active_on?(date=Date.today)
        return false unless principal.active?

        (start_date.nil? || start_date <= date) && (end_date.nil? || end_date >= date)
      end

      # Returns true if the member is currently active
      def active?
        active_on?(Date.today)
      end

      # Returns true if the member has expired (end_date is in the past)
      def expired?
        end_date.present? && end_date < Date.today
      end


      protected

      def validate_dates
        if start_date.present? && end_date.present? && end_date < start_date
          errors.add(:end_date, :must_be_after_start_date)
        end
      end

      def validate_allocation_percentage
        return if allocation_percentage.nil?

        # Basic range validation
        if any_inherited_role?
          # allow 0% allocation for inherited members
          if allocation_percentage < 0 || allocation_percentage > 100
            errors.add(:allocation_percentage, :invalid_range, message: "must be between 0 and 100")
            return
          end
        elsif allocation_percentage <= 0 || allocation_percentage > 100
          errors.add(:allocation_percentage, :invalid_range, message: "must be between 0 and 100")
          return
        end

        # Skip validation if user_id is not set yet (happens during initial form submission)
        return if user_id.nil?

        total = other_active_allocations.sum(:allocation_percentage) + allocation_percentage
        excess = total - 100
        # Bench memberships always fit: other bench memberships absorb what they can.
        return if excess <= 0 || project.bench_project

        # Bench memberships are reduced after save (see reduce_bench_allocations);
        # reject only what they cannot absorb.
        if excess > other_bench_allocations.sum(:allocation_percentage)
          errors.add(:allocation_percentage, :exceeds_total,
                     message: "would exceed 100% total allocation for this user (total would be #{total}%)")
        end
      end

      # Runs after a successful save, inside its transaction, so a rejected
      # save or a plain valid? call never changes other memberships.
      def reduce_bench_allocations
        return if allocation_percentage.nil? || user_id.nil?

        remaining = other_active_allocations.sum(:allocation_percentage) + allocation_percentage - 100
        other_bench_allocations.order(:allocation_percentage).each do |bench|
          break if remaining <= 0

          cut = [bench.allocation_percentage, remaining].min
          bench.update_column(:allocation_percentage, bench.allocation_percentage - cut)
          remaining -= cut
        end
      end

      # Today's direct (non-inherited) memberships of this user in active
      # projects, excluding this one. Uses a subquery, not a join, so members
      # with several roles are counted once and equal percentages are all summed.
      def other_active_allocations
        date = Date.today
        scope = self.class.joins(:project)
                    .where(user_id: user_id)
                    .where(id: MemberRole.where(inherited_from: nil).select(:member_id))
                    .where("(start_date IS NULL OR start_date <= ?)", date)
                    .where("(end_date IS NULL OR end_date >= ?)", date)
                    .where(projects: { status: Project::STATUS_ACTIVE })
        id ? scope.where.not(id: id) : scope
      end

      def other_bench_allocations
        other_active_allocations.where(projects: { bench_project: true })
      end

      def set_default_dates
        if start_date.nil?
          self.start_date = Date.today
        end

        if end_date.nil?
          self.end_date = 3.months.from_now.to_date
        end
      end
    end
  end
end
