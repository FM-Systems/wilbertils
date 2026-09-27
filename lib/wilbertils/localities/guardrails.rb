module Wilbertils; module Localities

  # Safety limits both apps check before applying an import. Wilberforce
  # applies first and Rainman second, so the limits must be the same in
  # both - an import one accepts and the other rejects leaves the two
  # databases with different localities.
  module Guardrails

    MAX_DELETION_RATIO = 0.2
    MIN_COVERAGE_RATIO = 0.5

    class << self

      # Messages for each limit the import breaks; empty when it is safe. A
      # country with no localities yet has nothing to protect.
      def violations(change_set:, csv_row_count:, country:)
        db_count = change_set.db_count
        return [] unless db_count.positive?

        violations = []
        deletion_count = change_set.deletions.size
        if deletion_count > (db_count * MAX_DELETION_RATIO).floor
          violations << "Import would delete #{deletion_count} of #{db_count} existing #{country} localities " \
                        "(over the #{(MAX_DELETION_RATIO * 100).to_i}% safety limit)"
        end
        if csv_row_count < (db_count * MIN_COVERAGE_RATIO).ceil
          violations << "Uploaded file(s) contain #{csv_row_count} localities but #{country} currently has #{db_count} - " \
                        "upload ALL of the country's files together (e.g. AU needs AU_auspost.csv and AU_fms.csv in one run)"
        end
        violations
      end

      # Aborts an apply that breaks a limit. A dry run only reports them.
      def enforce!(violations, dry_run:)
        return if dry_run || violations.empty?

        raise ValidationError.new(violations.map { |violation| "Aborted: #{violation}" })
      end

    end
  end

end; end
