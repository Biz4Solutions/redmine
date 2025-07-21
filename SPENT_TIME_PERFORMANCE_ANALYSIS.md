# Spent Time Performance Analysis & Optimization

## Root Cause Analysis

The "Spent Time" functionality was experiencing severe performance issues, especially for admin users and users with access to many projects. The main bottlenecks identified were:

### 1. Complex Permission Queries
- **TimeEntry.visible_condition**: Generated complex SQL with multiple subqueries for every permission check
- **Project.allowed_to_condition**: Created expensive OR conditions that couldn't use database indexes efficiently
- **No admin optimization**: Admin users were subjected to the same complex permission checks as regular users

### 2. Inefficient Database Queries
- **Missing composite indexes**: Critical combinations like (user_id, project_id) and (project_id, user_id, spent_on) were not indexed
- **N+1 queries**: Multiple database queries for related data that could be loaded in a single query
- **Suboptimal joins**: Complex joins in counting queries caused performance degradation

### 3. Lack of Caching
- **Repeated permission checks**: Same user-project permission combinations were checked multiple times
- **No query result caching**: Database queries were repeated for similar requests

## Implemented Optimizations

### 1. Database Index Optimizations
**File**: `db/migrate/20241201000001_optimize_time_entries_performance.rb`

Added critical composite indexes:
- `(user_id, project_id)` - For permission-based filtering
- `(project_id, user_id, spent_on)` - For date range queries with user permissions
- `(spent_on, project_id)` - For date-based filtering
- `(status, user_id)` - For approval workflow queries
- `spent_on` - For date range queries

### 2. Query Optimizations
**File**: `app/models/time_entry.rb`

#### Admin User Optimization
- Admin users now bypass complex permission checks entirely
- Simple project-based filtering for admin users when project scope is specified
- Reduces query complexity from O(n²) to O(1) for admin users

#### Improved Visible Scope
- Optimized TimeEntry.visible scope to use simpler queries for admin users
- Better handling of project-specific queries

### 3. TimeEntryQuery Optimizations
**File**: `app/models/time_entry_query.rb`

#### Selective Includes
- Only include Activity associations when needed for display or sorting
- Reduces unnecessary data loading and joins

#### Optimized Base Scope
- More efficient join strategies
- Conditional association loading based on query requirements

### 4. Controller Optimizations
**File**: `app/controllers/timelog_controller.rb`

#### Efficient Counting
- Separate count queries to avoid complex joins in count operations
- Optimized preloading strategies using `includes` instead of `preload`

#### Better Association Loading
- Comprehensive preloading of related associations
- Reduced N+1 queries through strategic `includes`

### 5. Permission Caching
**File**: `app/models/time_entry_permission_cache.rb`

#### Smart Caching System
- 5-minute cache for permission results
- User and project-specific cache keys
- Automatic cache cleanup and expiry
- Bypasses cache for admin users (always allowed)

### 6. Performance Monitoring
**File**: `lib/redmine/performance_logger.rb`

#### Comprehensive Logging
- Query execution time tracking
- Query count monitoring
- User type and project count correlation
- Separate performance log file for analysis

## Expected Performance Improvements

### For Admin Users
- **Before**: Complex permission queries with multiple subqueries
- **After**: Simple project-based filtering or direct access
- **Expected improvement**: 80-95% reduction in query time

### For Users with Many Projects
- **Before**: O(n) permission checks for each project
- **After**: Cached permission results + optimized indexes
- **Expected improvement**: 60-80% reduction in query time

### For Regular Users
- **Before**: Complex joins and subqueries
- **After**: Optimized indexes and efficient joins
- **Expected improvement**: 40-60% reduction in query time

## Testing Recommendations

### 1. Database Migration
```bash
# Run the migration to add performance indexes
rails db:migrate
```

### 2. Performance Testing

#### Create Test Data
```ruby
# In Rails console - create test data for performance testing
User.find_each do |user|
  (1..50).each do |i|
    project = Project.create!(
      name: "Test Project #{user.id}-#{i}",
      identifier: "test-project-#{user.id}-#{i}"
    )
    
    # Add user as member
    Member.create!(
      project: project,
      user: user,
      roles: [Role.first]
    )
    
    # Create time entries
    (1..20).each do |j|
      TimeEntry.create!(
        project: project,
        user: user,
        author: user,
        activity: TimeEntryActivity.first,
        hours: rand(1.0..8.0).round(2),
        spent_on: Date.current - rand(30).days,
        comments: "Test entry #{j}"
      )
    end
  end
end
```

#### Performance Measurement
```ruby
# Test performance for different user types
admin_user = User.where(admin: true).first
regular_user = User.where(admin: false).first

# Measure admin user performance
time_start = Time.current
TimeEntry.visible(admin_user).count
admin_time = Time.current - time_start

# Measure regular user performance  
time_start = Time.current
TimeEntry.visible(regular_user).count
regular_time = Time.current - time_start

puts "Admin user query time: #{admin_time}s"
puts "Regular user query time: #{regular_time}s"
```

### 3. Load Testing

#### Simulate Multiple Users
```ruby
# Test with concurrent users
threads = []
users = User.limit(10)

users.each do |user|
  threads << Thread.new do
    10.times do
      TimeEntry.visible(user).includes(:project, :user).limit(25).to_a
    end
  end
end

threads.each(&:join)
```

### 4. Monitor Performance Logs

#### Enable Performance Logging
```ruby
# Check performance logs
tail -f log/performance.log
```

### 5. Database Query Analysis

#### Check Query Plans
```sql
-- Analyze query performance in database console
EXPLAIN ANALYZE 
SELECT time_entries.* 
FROM time_entries 
INNER JOIN projects ON projects.id = time_entries.project_id 
WHERE [complex permission conditions]
ORDER BY time_entries.spent_on DESC;
```

## Monitoring & Maintenance

### 1. Regular Performance Checks
- Monitor `log/performance.log` for query times
- Set up alerts for queries taking longer than acceptable thresholds
- Regular analysis of query patterns

### 2. Cache Management
```ruby
# Clear permission cache when needed
TimeEntryPermissionCache.instance.clear_cache

# Clear cache for specific user after permission changes
TimeEntryPermissionCache.instance.clear_user_cache(user.id)
```

### 3. Index Maintenance
- Monitor index usage with database analysis tools
- Consider additional indexes based on actual usage patterns
- Regular database maintenance and statistics updates

## Rollback Plan

If any issues arise, the optimizations can be rolled back:

### 1. Database Rollback
```bash
# Rollback migration if needed
rails db:migrate:down VERSION=20241201000001
```

### 2. Code Rollback
- Revert changes to `app/models/time_entry.rb`
- Revert changes to `app/models/time_entry_query.rb`
- Revert changes to `app/controllers/timelog_controller.rb`
- Remove performance monitoring files if needed

## Additional Recommendations

### 1. Future Enhancements
- Consider Redis-based caching for high-traffic instances
- Implement background job processing for large exports
- Add database connection pooling optimization

### 2. Monitoring Tools
- Set up APM (Application Performance Monitoring) tools
- Implement database query monitoring
- Add custom metrics for Spent Time functionality

### 3. Regular Maintenance
- Weekly performance log analysis
- Monthly database optimization
- Quarterly index analysis and optimization

This comprehensive optimization should significantly improve the "Spent Time" functionality performance, especially for admin users and users with access to many projects. 