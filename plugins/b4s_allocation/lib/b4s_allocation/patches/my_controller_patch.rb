module B4sAllocation
  module Patches
    # Pending timesheets block on My page.
    module MyControllerPatch
      # Copy of core MyController#page that adds/removes the pending timesheets
      # block depending on the approve_time_entries permission.

      # Show user's page
      def page
        @user = User.current
        @groups = @user.pref.my_page_groups
        @blocks = @user.pref.my_page_layout

        # Add pending_timesheets block for users with approve_time_entries permission
        if @user.allowed_to?(:approve_time_entries, nil, :global => true) && 
           @user.pref.my_page_layout.values.flatten.exclude?('pending_timesheets')
          # Use the approver layout if the user hasn't customized their page yet
          if @user.pref.my_page_layout == Redmine::MyPage.default_layout
            @blocks = Redmine::MyPage.default_layout_for_approvers
            @user.pref.my_page_layout = @blocks
            @user.pref.save
          end
        end

        # Remove pending_timesheets block for users without approve_time_entries permission
        unless @user.allowed_to?(:approve_time_entries, nil, :global => true)
          @blocks.each do |group, blocks|
            if blocks.include?('pending_timesheets')
              @blocks[group].delete('pending_timesheets')
              @user.pref.my_page_layout = @blocks
              @user.pref.save
            end
          end
        end
      end
    end
  end
end
