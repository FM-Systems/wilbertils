module Wilbertils

  # Generic atomic table rebuild: populate a fresh copy of a table's structure
  # off to the side, then swap it in with a single RENAME TABLE so readers
  # never see a half-populated table and never see the table disappear.
  #
  # Modelled on the swap done by Rainman::Sapphire::ManageDataTransitionTask
  # (hardcoded to the `rates` table), but generalised to any table name and,
  # critically, re-raising rather than swallowing a failure - callers must be
  # able to see and handle a failed rebuild themselves.
  #
  #   Wilbertils::TableSwap.rebuild('remote_localities') do |staging_table|
  #     # populate staging_table here - raising aborts the rebuild and
  #     # leaves the live table completely untouched
  #   end
  #
  # wilbertils has no activerecord runtime dependency and its own spec suite
  # runs with no database at all, so the connection is a collaborator that
  # gets injected rather than reached for via ActiveRecord::Base directly -
  # same style as Localities::ChangeSet's `locality_scope: Locality` default
  # parameter. A caller that does have ActiveRecord loaded (rainman,
  # wilberforce) can just omit connection: and get it for free - see
  # #default_connection.
  #
  # IMPORTANT - DDL and transactions: every statement here (CREATE TABLE,
  # RENAME TABLE, DROP TABLE, ALTER TABLE) is DDL, and MySQL implicitly
  # commits the current transaction before running any DDL statement.
  # Calling #rebuild inside a transaction would therefore silently commit
  # whatever that transaction was protecting partway through, defeating the
  # point of wrapping it in one - so this is enforced, not just documented:
  # #rebuild raises immediately if it detects an open transaction, checked
  # via the injected connection's own #open_transactions.
  #
  # IMPORTANT - foreign keys: `CREATE TABLE ... LIKE` copies columns and
  # indexes but does NOT copy foreign keys. That is harmless for a table
  # nothing references, but if the table being swapped carries an outgoing
  # FK (i.e. it references another table), pass it via foreign_keys: so it
  # gets (re)created once the swap is done - see #add_foreign_keys for why
  # that has to happen afterwards rather than on the staging table up front.
  #
  # IMPORTANT - this only handles the *referencing* side safely. Swapping a
  # table that OTHER tables point AT is not safe to do with this helper:
  # MySQL repoints any FK defined against the live table at the renamed-away
  # backup table during the RENAME, not at the new table that takes its
  # place. Only use this for tables with no incoming foreign keys.
  class TableSwap
    class << self

      # Builds `table_name` fresh via the block, then atomically swaps it
      # in. Returns the row count of the table left live (or, in a dry run,
      # the row count the staging table ended up with - i.e. what a real
      # run would have produced).
      #
      # foreign_keys: an array of hashes describing FKs to (re)create on the
      # swapped-in table, e.g.
      #
      #   foreign_keys: [{name: 'fk_rails_4bb88e9095', column: 'locality_id', to_table: 'localities',
      #                   primary_key: 'id', on_delete: 'RESTRICT', on_update: 'RESTRICT'}]
      #
      # on_delete/on_update are optional - the corresponding clause is
      # omitted when not supplied. Ignored entirely on a dry run, since
      # nothing was swapped in for them to apply to.
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

          # http://dev.mysql.com/doc/refman/5.7/en/rename-table.html
          # "The rename operation is done atomically ... " - this single
          # statement is what makes the swap safe: the live table is never
          # missing and never half-populated from a reader's point of view.
          connection.execute("RENAME TABLE #{quote_table(connection, table_name)} TO #{quote_table(connection, backup_table)}, " \
                       "#{quote_table(connection, staging_table)} TO #{quote_table(connection, table_name)}")
          connection.execute("DROP TABLE #{quote_table(connection, backup_table)}")

          add_foreign_keys(connection, table_name, foreign_keys)

          connection.select_value("SELECT COUNT(*) FROM #{quote_table(connection, table_name)}").to_i
        ensure
          # Whether the block raised or the SQL above raised, the staging
          # table must never be left behind - and once the rename above has
          # succeeded, `staging_table` no longer exists under that name, so
          # this is a no-op at that point.
          connection.execute("DROP TABLE IF EXISTS #{quote_table(connection, staging_table)}")
        end
      end

      private

      # Mirrors Localities::ChangeSet's `locality_scope: Locality`
      # dependency-injection style: wilbertils carries no activerecord
      # runtime dependency (see wilbertils.gemspec), so this only reaches
      # for ActiveRecord::Base when it happens to already be loaded by the
      # host app (rainman, wilberforce), and raises a clear error instead of
      # a bare NameError when it isn't - telling the caller what to do about
      # it.
      def default_connection
        unless defined?(ActiveRecord)
          raise "Wilbertils::TableSwap.rebuild has no default connection available " \
                "(ActiveRecord is not loaded) - pass connection: explicitly"
        end

        ActiveRecord::Base.connection
      end

      # Foreign keys can only be (re)created here - AFTER the RENAME TABLE
      # above AND after the backup table has been dropped - never on the
      # staging table up front. Verified empirically against MySQL 8.0.36:
      #
      # - `CREATE TABLE ... LIKE` copies columns and indexes but NOT foreign
      #   keys (confirmed: 0 FKs exist on the staging table at this point).
      # - The FK cannot be added to the staging table before the rename
      #   either: InnoDB requires FK constraint names to be unique per
      #   database, and the live table still holds the name at that point -
      #   MySQL fails with ERROR 1826 Duplicate foreign key constraint name.
      # - RENAME TABLE moves the live table's name onto the backup table,
      #   but the name isn't actually free again until that backup table is
      #   DROPped - so the ALTER TABLE below has to come after both.
      #
      # Net effect (verified working, data intact, original constraint name
      # restored): there is a brief window, between the rename completing
      # and this ALTER TABLE completing, where the swapped-in table has no
      # FK enforcement at all.
      def add_foreign_keys(connection, table_name, foreign_keys)
        foreign_keys.each do |fk|
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

      # MySQL identifiers are capped at 64 characters - raise a clear error
      # up front rather than let CREATE/RENAME TABLE fail deep inside the
      # block with a cryptic "Identifier name is too long".
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
