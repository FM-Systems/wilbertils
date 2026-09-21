module Wilbertils

  # Atomic table rebuild: populate a copy off to the side, then swap it in with
  # one RENAME TABLE so readers never see it half-populated. Raising from the
  # block aborts and leaves the live table alone.
  #
  # Connection is injected - wilbertils has no activerecord runtime dependency.
  #
  # IMPORTANT - the swap is DDL, which implicitly commits in MySQL, so #rebuild
  # refuses to run inside a transaction. `CREATE TABLE ... LIKE` also copies no
  # foreign keys: pass outgoing ones via foreign_keys:, and never use this on a
  # table something references - RENAME repoints incoming FKs at the backup.
  class TableSwap
    class << self

      # Builds `table_name` fresh via the block, then swaps it in. Returns the
      # live table's row count, or the staging table's on a dry run.
      #
      # foreign_keys: [{name:, column:, to_table:, primary_key:, on_delete:, on_update:}]
      # - recreated on the swapped-in table, ignored on a dry run.
      def rebuild(table_name, connection: default_connection, dry_run: false, epoch: Time.now.to_i, foreign_keys: [])
        if connection.open_transactions > 0
          raise "Wilbertils::TableSwap.rebuild must not be called inside a transaction " \
                "(DDL causes an implicit commit in MySQL) - table: #{table_name}"
        end

        staging_table = staging_table_name(table_name, epoch)
        backup_table  = backup_table_name(table_name, epoch)
        check_identifier_lengths!(table_name, staging_table, backup_table)

        connection.execute("CREATE TABLE #{quote_table(connection, staging_table)} LIKE #{quote_table(connection, table_name)}")

        begin
          yield staging_table

          if dry_run
            return connection.select_value("SELECT COUNT(*) FROM #{quote_table(connection, staging_table)}").to_i
          end

          # RENAME TABLE is atomic - this one statement makes the swap safe.
          connection.execute("RENAME TABLE #{quote_table(connection, table_name)} TO #{quote_table(connection, backup_table)}, " \
                       "#{quote_table(connection, staging_table)} TO #{quote_table(connection, table_name)}")
          connection.execute("DROP TABLE #{quote_table(connection, backup_table)}")

          add_foreign_keys(connection, table_name, foreign_keys)

          connection.select_value("SELECT COUNT(*) FROM #{quote_table(connection, table_name)}").to_i
        ensure
          # Never leave the staging table behind; a no-op after a successful rename.
          connection.execute("DROP TABLE IF EXISTS #{quote_table(connection, staging_table)}")
        end
      end

      private

      # Clear error rather than a bare NameError when AR is not loaded.
      def default_connection
        unless defined?(ActiveRecord)
          raise "Wilbertils::TableSwap.rebuild has no default connection available " \
                "(ActiveRecord is not loaded) - pass connection: explicitly"
        end

        ActiveRecord::Base.connection
      end

      # Only addable after the rename and backup drop - until then the old table
      # still holds the name (MySQL 8.0.36 ERROR 1826). Brief window with no FKs.
      def add_foreign_keys(connection, table_name, foreign_keys)
        foreign_keys.each do |fk|
          # Keywords, not identifiers, so these go in unquoted - callers pass literals.
          clauses = +''
          clauses << " ON DELETE #{fk[:on_delete]}" if fk[:on_delete]
          clauses << " ON UPDATE #{fk[:on_update]}" if fk[:on_update]

          connection.execute(
            "ALTER TABLE #{quote_table(connection, table_name)} " \
            "ADD CONSTRAINT #{quote_column(connection, fk[:name])} " \
            "FOREIGN KEY (#{quote_column(connection, fk[:column])}) " \
            "REFERENCES #{quote_table(connection, fk[:to_table])} (#{quote_column(connection, fk[:primary_key])})" \
            "#{clauses}"
          )
        end
      end

      def quote_table(connection, identifier)
        connection.quote_table_name(identifier)
      end

      def quote_column(connection, identifier)
        connection.quote_column_name(identifier)
      end

      def staging_table_name(table_name, epoch)
        "#{table_name}_swap_#{epoch}"
      end

      def backup_table_name(table_name, epoch)
        "#{table_name}_swapold_#{epoch}"
      end

      # MySQL caps identifiers at 64 characters - fail up front.
      def check_identifier_lengths!(table_name, staging_table, backup_table)
        [staging_table, backup_table].each do |identifier|
          if identifier.length > 64
            raise ArgumentError, "derived table name #{identifier.inspect} (from #{table_name.inspect}) " \
                                  "exceeds MySQL's 64 character identifier limit"
          end
        end
      end

    end
  end

end
