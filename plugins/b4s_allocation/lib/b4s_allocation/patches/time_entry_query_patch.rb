module B4sAllocation
  module Patches
    # Approval workflow columns and filters on the spent time list.
    module TimeEntryQueryPatch
      extend ActiveSupport::Concern

      prepended do
        hours_index = available_columns.index {|c| c.name == :hours}
        self.available_columns = available_columns.dup.insert(
          hours_index + 1,
          QueryColumn.new(:status, :sortable => "#{TimeEntry.table_name}.status", :groupable => true),
          QueryColumn.new(:approved_by, :sortable => lambda {User.fields_for_order_statement("approved_by")}, :groupable => true),
          TimestampQueryColumn.new(:approved_on, :sortable => "#{TimeEntry.table_name}.approved_on", :default_order => 'desc'),
          QueryColumn.new(:rejection_reason)
        )
      end

      def initialize_available_filters
        super
        # Keep "status" right after "spent_on", where core code had it.
        status = [
          "status",
          {:type => :list,
           :values => [
             [l(:label_pending_approval), TimeEntry::STATUS_PENDING],
             [l(:label_approved), TimeEntry::STATUS_APPROVED],
             [l(:label_rejected), TimeEntry::STATUS_REJECTED]
           ]}
        ]
        filters = @available_filters.to_a
        @available_filters = {}
        filters.each do |name, filter|
          @available_filters[name] = filter
          add_available_filter(*status) if name == "spent_on"
        end

        # Approval workflow filters
        add_available_filter(
          "approved_by_id",
          :type => :list_optional,
          :values => lambda {author_values}
        )
        add_available_filter "approved_on", :type => :date_past
        add_available_filter "rejection_reason", :type => :text
      end
    end
  end
end
