require 'csv'
require 'active_support/core_ext/object/blank'

module Wilbertils; module Localities

  # Timezone handoff: wilberforce owns the values and dumps them (#generate),
  # rainman applies them (#parse). Both sides live here so the format can't drift.
  class TimezoneCsv

    HEADERS = %w(Postcode Sublocality Locality Region Timezone).freeze

    # unresolved_count: localities wilberforce has no timezone for yet.
    Result = Struct.new(:csv, :row_count, :unresolved_count, keyword_init: true)

    class << self

      def generate(country:, locality_scope: Locality)
        row_count = 0
        unresolved_count = 0

        csv = CSV.generate do |out|
          out << HEADERS
          locality_scope.where(country: country)
                        # :id is required - find_each batches by primary key.
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

      # => { identity_key => timezone name }, keyed as ChangeSet keys a locality.
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
