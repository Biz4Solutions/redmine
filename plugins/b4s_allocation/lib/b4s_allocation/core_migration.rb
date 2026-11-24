module B4sAllocation
  # These migrations used to live in core db/migrate under the same version
  # numbers. Databases that already ran them there (prod) only need the
  # plugin version recorded; fresh databases run them normally.
  module CoreMigration
    def applied_in_core?
      connection.select_value(
        "SELECT 1 FROM schema_migrations WHERE version = #{connection.quote(version.to_s)}"
      ).present?
    end
  end
end
