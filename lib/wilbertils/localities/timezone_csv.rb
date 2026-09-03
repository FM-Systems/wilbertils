require 'csv'
require 'active_support/core_ext/object/blank'

module Wilbertils; module Localities

  # The timezone handoff between wilberforce and rainman.
  #
  # Wilberforce is the only service that can resolve a timezone from
  # coordinates (it has the Timezone gem and a Google API key), so it owns the
  # values: its locality import fills them, then #generate dumps one country's
  # resolved timezones and rainman's import applies them with #parse. Both
  # sides live here so the column order and the matching rules cannot drift.
  #
  # The format is the same one db/refdata/localities/XX_timezones.csv has always
  # used, so a dump is still readable by rainman's seed-time
  # Rainman::Refdata::TimezoneImporter.
  class TimezoneCsv

    HEADERS = %w(Postcode Sublocality Locality Region Timezone).freeze

    # row_count is what was written; unresolved_count is how many localities
    # were skipped because wilberforce itself has no timezone for them yet
    # (callers surface this - it usually means the wilberforce import has not
    # been applied yet).
    Result = Struct.new(:csv, :row_count, :unresolved_count, keyword_init: true)

    class << self

      def generate(country:, locality_scope: Locality)
        row_count = 0
        unresolved_count = 0

        csv = CSV.generate do |out|
          out << HEADERS
          locality_scope.where(country: country)
                        # :id is required - find_each batches by primary key and
                        # raises ArgumentError if it is not selected.
                        .select(:id, :postcode, :sublocality, :locality, :region, :timezone)
                        .find_each do |locality|
            if locality.timezone.blank?
              unresolved_count += 1
              next
            end

            out << [locality.postcode, locality.sublocality, locality.locality, locality.region, locality.timezone]
            row_count += 1
          end
        end

        Result.new(csv: csv, row_count: row_count, unresolved_count: unresolved_count)
      end

      # => { identity_key => timezone name }, keyed the same way
      # ChangeSet identifies a locality so the two agree on what "the same
      # locality" means.
      def parse(io, filename: nil)
        table = CSV.parse(io.read.force_encoding('UTF-8').scrub, headers: true)
        check_headers(table, filename)

        table.each_with_object({}) do |row, lookup|
          timezone = row['Timezone']&.strip.presence
          next unless timezone

          lookup[key_for(postcode: row['Postcode'], sublocality: row['Sublocality'],
                         locality: row['Locality'], region: row['Region'])] = timezone
        end
      rescue CSV::MalformedCSVError => e
        raise ValidationError.new(["#{filename || 'timezone file'}: malformed CSV - #{e.message}"])
      end

      def key_for(postcode:, sublocality:, locality:, region:)
        [postcode&.strip.presence,
         sublocality&.strip.presence&.upcase,
         locality&.strip.presence&.upcase,
         region&.strip.presence&.upcase]
      end

      private

      def check_headers(table, filename)
        missing = HEADERS - (table.headers || []).compact
        return if missing.empty?

        raise ValidationError.new(["#{filename || 'timezone file'}: missing required headers: #{missing.join(', ')}"])
      end

    end
  end

end; end
