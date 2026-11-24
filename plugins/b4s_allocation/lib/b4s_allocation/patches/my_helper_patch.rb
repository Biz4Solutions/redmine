module B4sAllocation
  module Patches
    # My page block helpers for time entry approval.
    module MyHelperPatch
      # Copy of the core helper that hides the pending timesheets block from
      # users without approve_time_entries.

      # Returns the select tag used to add a block to My page
      def block_select_tag(user)
        blocks_in_use = user.pref.my_page_layout.values.flatten
        options = content_tag('option')

        block_options = Redmine::MyPage.block_options(blocks_in_use)

        # Filter out the pending_timesheets block for users without approve_time_entries permission
        unless user.allowed_to?(:approve_time_entries, nil, :global => true)
          block_options.reject! { |label, block| block == 'pending_timesheets' }
        end

        block_options.each do |label, block|
          options << content_tag('option', label, :value => block, :disabled => block.blank?)
        end

        select_tag('block', options, :id => "block-select", :onchange => "$('#block-form').submit();")
      end

      def render_pending_timesheets_block(block, settings)
        # Find time entries that need approval and the user has permission to approve
        entries = TimeEntry.pending_approval.joins(:project => :members).
          where("#{Member.table_name}.user_id = ?", User.current.id).
          joins("INNER JOIN #{MemberRole.table_name} ON #{MemberRole.table_name}.member_id = #{Member.table_name}.id").
          joins("INNER JOIN #{Role.table_name} ON #{Role.table_name}.id = #{MemberRole.table_name}.role_id").
          where("#{Role.table_name}.permissions LIKE '%:approve_time_entries%'").
          where("#{TimeEntry.table_name}.user_id <> ?", User.current.id).
          order("#{TimeEntry.table_name}.spent_on DESC").
          limit(10)

        render :partial => 'b4s_allocation/my_blocks/pending_timesheets', :locals => {:entries => entries, :block => block}
      end

      def render_my_pending_time_entries_block(block, settings)
        # Find the user's time entries that are pending approval
        entries = TimeEntry.pending_approval.
          where(:user_id => User.current.id).
          order("#{TimeEntry.table_name}.spent_on DESC").
          limit(10)

        render :partial => 'b4s_allocation/my_blocks/my_pending_time_entries', :locals => {:entries => entries, :block => block}
      end
    end
  end
end
