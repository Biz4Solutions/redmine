module Redmine
  class PerformanceLogger
    class << self
      def log_time_entry_query(action, user, &block)
        return yield unless Rails.env.development? || log_performance?
        
        start_time = Time.current
        query_count_before = count_queries
        
        result = yield
        
        end_time = Time.current
        query_count_after = count_queries
        
        duration = ((end_time - start_time) * 1000).round(2)
        query_count = query_count_after - query_count_before
        
        log_entry = {
          action: action,
          user_type: user.admin? ? 'admin' : 'regular',
          user_projects_count: user.admin? ? 'unlimited' : user.memberships.count,
          duration_ms: duration,
          query_count: query_count,
          timestamp: Time.current.iso8601
        }
        
        Rails.logger.info("[REDMINE_PERFORMANCE] #{log_entry.to_json}")
        
        # Also log to separate performance log if configured
        if performance_logger
          performance_logger.info(log_entry.to_json)
        end
        
        result
      end
      
      private
      
      def log_performance?
        Setting.respond_to?(:log_performance?) && Setting.log_performance?
      end
      
      def count_queries
        ActiveRecord::Base.connection.query_cache.size if ActiveRecord::Base.connection.query_cache_enabled
      rescue
        0
      end
      
      def performance_logger
        @performance_logger ||= begin
          if Rails.root.join('log', 'performance.log').exist? || Rails.env.development?
            Logger.new(Rails.root.join('log', 'performance.log'), 'daily')
          end
        rescue
          nil
        end
      end
    end
  end
end 