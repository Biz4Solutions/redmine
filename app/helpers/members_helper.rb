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

module MembersHelper
  def render_principals_for_new_members(project, limit=100)
    scope = Principal.active.visible.sorted.not_member_of(project).like(params[:q])
    principal_count = scope.count
    principal_pages = Redmine::Pagination::Paginator.new principal_count, limit, params['page']
    principals = scope.offset(principal_pages.offset).limit(principal_pages.per_page).to_a
    s =
      content_tag(
        'div',
        content_tag(
          'div',
          principals_radio_tags('membership[user_id]', principals),
          :id => 'principals'
        ),
        :class => 'objects-selection'
      )
    links =
      pagination_links_full(principal_pages,
                            principal_count,
                            :per_page_links => false) do |text, parameters, options|
        link_to(
          text,
          autocomplete_project_memberships_path(
            project,
            parameters.merge(:q => params[:q], :format => 'js')
          ),
          :remote => true)
      end
    s + content_tag('span', links, :class => 'pagination')
  end

  def principals_radio_tags(name, principals)
    principals.collect do |principal|
      if principal.is_a?(User)
        total_allocation = Member.total_allocation_for_user(principal.id)
        bench_allocation = Member.bench_allocation_for_user(principal.id)
        regular_allocation = total_allocation - bench_allocation
        available_allocation = [100 - regular_allocation, 0].max
        content_tag(
          'label',
          radio_button_tag(name, principal.id, false,
            :onchange => "updateMaxAvailability(#{principal.id})") +
          content_tag('span', "#{principal.name} (#{available_allocation}%)",
            :style => 'white-space: nowrap;'),
          :class => 'inline-flex'
        )
      else
        content_tag(
          'label',
          radio_button_tag(name, principal.id, false) +
          principal.name,
          :class => 'inline-flex'
        )
      end
    end.join("\n").html_safe
  end

  # Returns inheritance information for an inherited member role
  def render_inherited_roles(member)
    s = ""
    member.member_roles.each do |member_role|
      next unless member_role.inherited_from

      s << "<div class='inherited-role'>"
      s << l(:label_inherited_from)
      s << " "
      s << link_to_project(member_role.inherited_from.project)
      s << "</div>"
    end
    s.html_safe
  end

  # Returns inheritance information for a specific role
  def render_role_inheritance(member, role)
    content = member.role_inheritance(role).filter_map do |h|
      if h.is_a?(Project)
        l(:label_inherited_from_parent_project)
      elsif h.is_a?(Group)
        l(:label_inherited_from_group, :name => h.name.to_s)
      end
    end.uniq

    if content.present?
      content_tag('em', content.join(", "), :class => "info")
    end
  end
end
