resources :time_entries, :controller => 'timelog', :only => [] do
  member do
    post 'approve', :to => 'timelog#approve'
    post 'reject', :to => 'timelog#reject'
    post 'submit', :to => 'timelog#submit'
  end
  collection do
    post 'bulk_approve', :to => 'timelog#bulk_approve'
    post 'bulk_reject', :to => 'timelog#bulk_reject'
    post 'bulk_submit', :to => 'timelog#bulk_submit'
  end
end

resources :timesheets do
  member do
    post 'submit'
  end

  collection do
    post 'bulk_submit'
    post 'bulk_approve'
    post 'bulk_reject'
    get 'pending_approval'
  end
end

resources :members, :only => [] do
  collection do
    get 'max_availability/:user_id', to: 'members#max_availability'
  end
end
