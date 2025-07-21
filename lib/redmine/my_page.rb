# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

module Redmine
  module MyPage
    include Redmine::I18n

    CORE_GROUPS = ['top', 'left', 'right']

    CORE_BLOCKS = {
      'issuesassignedtome' => {:label => :label_assigned_to_me_issues},
      'issuesreportedbyme' => {:label => :label_reported_issues},
      'issuesupdatedbyme' => {:label => :label_updated_issues},
      'issueswatched' => {:label => :label_watched_issues},
      'issuequery' => {:label => :label_issue_plural, :max_occurs => 3},
      'news' => {:label => :label_news_latest},
      'calendar' => {:label => :label_calendar},
      'documents' => {:label => :label_document_plural},
      'timelog' => {:label => :label_spent_time},
      'activity' => {:label => :label_activity},
      'my_pending_timesheets' => {:label => :'timesheet.label_my_pending_timesheets'}
    }

    def self.groups
      CORE_GROUPS.dup.freeze
    end

    # Returns the available blocks
    def self.blocks
      blocks = CORE_BLOCKS.dup

      # Only add the timesheets_pending_my_approval block for users with approve_time_entries permission
      unless blocks.key?('timesheets_pending_my_approval') || !User.current.allowed_to?(:approve_time_entries, nil, :global => true)
        blocks['timesheets_pending_my_approval'] = {:label => :'timesheet.label_timesheets_pending_my_approval'}
      end

      blocks.merge(additional_blocks).freeze
    end

    def self.block_options(blocks_in_use=[])
      options = []
      blocks.each do |block, block_options|
        indexes = blocks_in_use.filter_map do |n|
          if n =~ /\A#{block}(__(\d+))?\z/
            $2.to_i
          end
        end

        occurs = indexes.size
        block_id = indexes.any? ? "#{block}__#{indexes.max + 1}" : block
        disabled = (occurs >= (Redmine::MyPage.blocks[block][:max_occurs] || 1))
        block_id = nil if disabled

        label = block_options[:label]
        options << [l("my.blocks.#{label}", :default => [label, label.to_s.humanize]), block_id]
      end
      options
    end

    def self.valid_block?(block, blocks_in_use=[])
      block.present? && block_options(blocks_in_use).map(&:last).include?(block)
    end

    def self.find_block(block)
      block.to_s =~  /\A(.*?)(__\d+)?\z/
      name = $1
      blocks.has_key?(name) ? blocks[name].merge(:name => name) : nil
    end

    # Returns the additional blocks that are defined by plugin partials
    def self.additional_blocks
      @@additional_blocks ||=
        Dir.glob(
          "#{Redmine::Plugin.directory}/*/app/views/my/blocks/_*.{rhtml,erb}"
        ).inject({}) do |h, file|
          name = File.basename(file).split('.').first.delete_prefix('_')
          h[name] = {:label => name.to_sym, :partial => "my/blocks/#{name}"}
          h
        end
    end

    # Returns the default layout for My Page
    def self.default_layout
      {
        'left' => ['my_pending_timesheets'],
        'right' => ['issuesreportedbyme'],
        'top' => ['timesheets_pending_my_approval', 'my_pending_timesheets']
      }
    end

    # Returns the default layout for My Page for users with approve_time_entries permission
    def self.default_layout_for_approvers
      layout = default_layout
      layout['top'] = ['timesheets_pending_my_approval', 'my_pending_timesheets']
      layout
    end
  end
end
