module B4sAllocation
  module Patches
    # Member picker showing remaining availability.
    module MembersHelperPatch
      # Copy of the core helper with a radio list (one user at a time, showing
      # remaining availability) instead of checkboxes.

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
    end
  end
end
