module B4sAllocation
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_layouts_base_html_head, :partial => 'b4s_allocation/hooks/html_head'
    render_on :view_projects_form, :partial => 'b4s_allocation/hooks/project_form_bench'
    render_on :view_time_entries_context_menu_end, :partial => 'b4s_allocation/hooks/bulk_reject_dialog'
  end
end
