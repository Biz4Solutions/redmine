module B4sAllocation
  module Patches
    # Default My page layouts used by the (dormant) time entry approval blocks.
    # Patched onto Redmine::MyPage's singleton class.
    module MyPagePatch
      def default_layout
        super.merge('top' => ['my_pending_time_entries'])
      end

      # Returns the default layout for My Page for users with approve_time_entries permission
      def default_layout_for_approvers
        layout = default_layout
        layout['top'] = ['pending_timesheets']
        layout
      end
    end
  end
end
