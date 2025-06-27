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

module MyHelper
  # Renders the blocks
  def render_blocks(blocks, user, options={})
    s = ''.html_safe

    if blocks.present?
      blocks.each do |block|
        s << render_block(block, user).to_s
      end
    end
    s
  end

  # Renders a single block
  def render_block(block, user)
    content = render_block_content(block, user)
    if content.present?
      handle = content_tag('span', sprite_icon('reorder', ''), :class => 'icon-only icon-sort-handle sort-handle', :title => l(:button_move))
      close = link_to(sprite_icon('close', l(:button_delete)),
                      {:action => "remove_block", :block => block},
                      :remote => true, :method => 'post',
                      :class => "icon-only icon-close", :title => l(:button_delete))
      content = content_tag('div', handle + close, :class => 'contextual') + content

      content_tag('div', content, :class => "mypage-box", :id => "block-#{block}")
    end
  end

  # Renders a single block content
  def render_block_content(block, user)
    unless block_definition = Redmine::MyPage.find_block(block)
      Rails.logger.warn("Unknown block \"#{block}\" found in #{user.login} (id=#{user.id}) preferences")
      return
    end

    settings = user.pref.my_page_settings(block)
    if partial = block_definition[:partial]
      begin
        render(:partial => partial, :locals => {:user => user, :settings => settings, :block => block})
      rescue ActionView::MissingTemplate
        Rails.logger.warn("Partial \"#{partial}\" missing for block \"#{block}\" found in #{user.login} (id=#{user.id}) preferences")
        return nil
      end
    else
      send :"render_#{block_definition[:name]}_block", block, settings
    end
  end

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

  def render_calendar_block(block, settings)
    calendar = Redmine::Helpers::Calendar.new(User.current.today, current_language, :week)
    calendar.events = Issue.visible.
      where(:project => User.current.projects).
      where("(start_date>=? and start_date<=?) or (due_date>=? and due_date<=?)", calendar.startdt, calendar.enddt, calendar.startdt, calendar.enddt).
      includes(:project, :tracker, :priority, :assigned_to).
      references(:project, :tracker, :priority, :assigned_to).
      to_a

    render :partial => 'my/blocks/calendar', :locals => {:calendar => calendar, :block => block}
  end

  def render_documents_block(block, settings)
    documents = Document.visible.order("#{Document.table_name}.created_on DESC").limit(10).to_a

    render :partial => 'my/blocks/documents', :locals => {:block => block, :documents => documents}
  end

  def render_issuesassignedtome_block(block, settings)
    query = IssueQuery.new(:name => l(:label_assigned_to_me_issues), :user => User.current)
    query.add_filter 'assigned_to_id', '=', ['me']
    query.add_filter 'project.status', '=', ["#{Project::STATUS_ACTIVE}"]
    query.column_names = settings[:columns].presence || ['project', 'tracker', 'status', 'subject']
    query.sort_criteria = settings[:sort].presence || [['priority', 'desc'], ['updated_on', 'desc']]
    issues = query.issues(:limit => 10)

    render :partial => 'my/blocks/issues', :locals => {:query => query, :issues => issues, :block => block}
  end

  def render_issuesreportedbyme_block(block, settings)
    query = IssueQuery.new(:name => l(:label_reported_issues), :user => User.current)
    query.add_filter 'author_id', '=', ['me']
    query.add_filter 'project.status', '=', ["#{Project::STATUS_ACTIVE}"]
    query.column_names = settings[:columns].presence || ['project', 'tracker', 'status', 'subject']
    query.sort_criteria = settings[:sort].presence || [['updated_on', 'desc']]
    issues = query.issues(:limit => 10)

    render :partial => 'my/blocks/issues', :locals => {:query => query, :issues => issues, :block => block}
  end

  def render_issuesupdatedbyme_block(block, settings)
    query = IssueQuery.new(:name => l(:label_updated_issues), :user => User.current)
    query.add_filter 'updated_by', '=', ['me']
    query.add_filter 'project.status', '=', ["#{Project::STATUS_ACTIVE}"]
    query.column_names = settings[:columns].presence || ['project', 'tracker', 'status', 'subject']
    query.sort_criteria = settings[:sort].presence || [['updated_on', 'desc']]
    issues = query.issues(:limit => 10)

    render :partial => 'my/blocks/issues', :locals => {:query => query, :issues => issues, :block => block}
  end

  def render_issueswatched_block(block, settings)
    query = IssueQuery.new(:name => l(:label_watched_issues), :user => User.current)
    query.add_filter 'watcher_id', '=', ['me']
    query.add_filter 'project.status', '=', ["#{Project::STATUS_ACTIVE}"]
    query.column_names = settings[:columns].presence || ['project', 'tracker', 'status', 'subject']
    query.sort_criteria = settings[:sort].presence || [['updated_on', 'desc']]
    issues = query.issues(:limit => 10)

    render :partial => 'my/blocks/issues', :locals => {:query => query, :issues => issues, :block => block}
  end

  def render_issuequery_block(block, settings)
    query = IssueQuery.visible.find_by_id(settings[:query_id])

    if query
      query.column_names = settings[:columns] if settings[:columns].present?
      query.sort_criteria = settings[:sort] if settings[:sort].present?
      issues = query.issues(:limit => 10)
      render :partial => 'my/blocks/issues', :locals => {:query => query, :issues => issues, :block => block, :settings => settings}
    else
      queries = IssueQuery.visible.sorted
      render :partial => 'my/blocks/issue_query_selection', :locals => {:queries => queries, :block => block, :settings => settings}
    end
  end

  def render_news_block(block, settings)
    news = News.visible.
      where(:project => User.current.projects).
      limit(10).
      includes(:project, :author).
      references(:project, :author).
      order("#{News.table_name}.created_on DESC").
      to_a

    render :partial => 'my/blocks/news', :locals => {:block => block, :news => news}
  end

  def render_timelog_block(block, settings)
    days = settings[:days].to_i
    days = 7 if days < 1 || days > 365

    entries = TimeEntry.
      where("#{TimeEntry.table_name}.user_id = ? AND #{TimeEntry.table_name}.spent_on BETWEEN ? AND ?", User.current.id, User.current.today - (days - 1), User.current.today).
      joins(:activity, :project).
      references(:issue => [:tracker, :status]).
      includes(:issue => [:tracker, :status]).
      order("#{TimeEntry.table_name}.spent_on DESC, #{Project.table_name}.name ASC, #{Tracker.table_name}.position ASC, #{Issue.table_name}.id ASC").
      to_a
    entries_by_day = entries.group_by(&:spent_on)

    render :partial => 'my/blocks/timelog', :locals => {:block => block, :entries => entries, :entries_by_day => entries_by_day, :days => days}
  end

  def render_activity_block(block, settings)
    events_by_day = Redmine::Activity::Fetcher.new(User.current, :author => User.current).events(nil, nil, :limit => 10).group_by {|event| User.current.time_to_date(event.event_datetime)}

    render :partial => 'my/blocks/activity', :locals => {:events_by_day => events_by_day}
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

    render :partial => 'my/blocks/pending_timesheets', :locals => {:entries => entries, :block => block}
  end

  def render_my_pending_timesheets_block(block, settings)
    # Find the user's timesheets that are in draft or pending status
    timesheets = Timesheet.where(user_id: User.current.id)
                         .where(status: [Timesheet::STATUS_DRAFT, Timesheet::STATUS_PENDING])
                         .order(start_date: :desc)
                         .limit(10)

    content = content_tag('h3',
      link_to(l(:label_my_pending_timesheets, :scope => :timesheet), timesheets_path(:user_id => 'me', :status => [Timesheet::STATUS_DRAFT, Timesheet::STATUS_PENDING])) +
      " (#{timesheets.count})"
    )

    if timesheets.any?
      table = content_tag('table', :class => 'list timesheets') do
        header = content_tag('thead',
          content_tag('tr') do
            content_tag('th', l(:field_week, :scope => :timesheet)) +
            content_tag('th', l(:field_start_date, :scope => :timesheet)) +
            content_tag('th', l(:field_end_date, :scope => :timesheet)) +
            content_tag('th', l(:field_total_hours, :scope => :timesheet)) +
            content_tag('th', l(:field_status, :scope => :timesheet))
          end
        )

        rows = content_tag('tbody') do
          timesheets.map do |timesheet|
            content_tag('tr', {:class => timesheet.status, :data => {:id => timesheet.id}}) do
              content_tag('td', timesheet.week_number, :class => 'week') +
              content_tag('td', format_date(timesheet.start_date), :class => 'start-date') +
              content_tag('td', format_date(timesheet.end_date), :class => 'end-date') +
              content_tag('td', number_with_precision(timesheet.total_hours, precision: 2), :class => 'hours') +
              content_tag('td',
                content_tag('span',
                  l(:"label_status_#{timesheet.status}", :scope => :timesheet),
                  :class => "badge badge-#{timesheet.status == Timesheet::STATUS_DRAFT ? 'info' : 'warning'}"
                ),
                :class => 'status'
              )
            end
          end.join.html_safe
        end

        header + rows
      end
      content += table

      # Add JavaScript to make rows clickable
      content += javascript_tag(<<-EOF
        $(document).ready(function() {
          $('.list.timesheets tbody tr').css('cursor', 'pointer').click(function() {
            var id = $(this).data('id');
            window.location = '#{timesheets_path}/' + id;
          });
        });
      EOF
                               )
    else
      content += content_tag('p', l(:label_no_data, :scope => :timesheet), :class => 'nodata')
    end

    content
  end

  def render_timesheets_pending_my_approval_block(block, settings)
    # Find timesheets that need approval and the user has permission to approve
    timesheets = Timesheet.joins(:time_entries => {:project => :members})
                         .where("#{Member.table_name}.user_id = ?", User.current.id)
                         .joins("INNER JOIN #{MemberRole.table_name} ON #{MemberRole.table_name}.member_id = #{Member.table_name}.id")
                         .joins("INNER JOIN #{Role.table_name} ON #{Role.table_name}.id = #{MemberRole.table_name}.role_id")
                         .where("#{Role.table_name}.permissions LIKE '%:approve_time_entries%'")
                         .where("#{TimeEntry.table_name}.user_id <> ?", User.current.id)
                         .where("#{TimeEntry.table_name}.status = ?", TimeEntry::STATUS_PENDING)
                         .distinct
                         .order("#{Timesheet.table_name}.start_date DESC")
                         .limit(10)

    content = content_tag('h3',
      link_to(l(:label_timesheets_pending_my_approval, :scope => :timesheet), pending_approval_timesheets_path) +
      " (#{timesheets.count})"
    )

    if timesheets.any?
      table = content_tag('table', :class => 'list time-entries') do
        header = content_tag('thead',
          content_tag('tr') do
            content_tag('th', l(:field_user, :scope => :timesheet)) +
            content_tag('th', l(:field_start_date, :scope => :timesheet)) +
            content_tag('th', l(:field_end_date, :scope => :timesheet)) +
            content_tag('th', l(:field_total_hours, :scope => :timesheet)) +
            content_tag('th', '')
          end
        )

        rows = content_tag('tbody') do
          timesheets.map do |timesheet|
            content_tag('tr') do
              content_tag('td', link_to_user(timesheet.user), :class => 'user') +
              content_tag('td', format_date(timesheet.start_date), :class => 'start-date') +
              content_tag('td', format_date(timesheet.end_date), :class => 'end-date') +
              content_tag('td', number_with_precision(timesheet.total_hours, precision: 2), :class => 'hours') +
              content_tag('td', link_to(l(:button_view), timesheet_path(timesheet), :class => 'icon icon-magnifier'), :class => 'buttons')
            end
          end.join.html_safe
        end

        header + rows
      end
      content += table
    else
      content += content_tag('p', l(:label_no_data, :scope => :timesheet), :class => 'nodata')
    end

    content
  end
end
