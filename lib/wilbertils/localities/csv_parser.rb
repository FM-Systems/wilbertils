require 'csv'
require 'bigdecimal'
require 'active_support/core_ext/object/blank'

module Wilbertils; module Localities

  # Parses an uploaded locality CSV into normalized rows.
  #
  # Filenames must follow the refdata convention: a 2-letter ISO country code
  # prefix (e.g. AU_auspost.csv). Sublocality and State columns are optional -
  # NZ files have no State, AU/US files have no Sublocality - and blank
  # coordinates become 0.0, matching how db/refdata/localities files are shaped.
  class CsvParser

    Row = Struct.new(:postcode, :sublocality, :locality, :region, :country, :longitude, :latitude, :locality_type)
    Result = Struct.new(:country, :country_code, :rows, :warnings, :has_locality_type, keyword_init: true)

    REQUIRED_HEADERS = %w(Postcode Locality Longitude Latitude).freeze
    QUICK_VALIDATE_ROW_LIMIT = 100

    class << self

      def parse(io, filename:)
        country_code, country = country_from_filename(filename)
        csv = read_csv(io, filename)
        check_headers(csv, filename)

        errors = []
        warnings = []
        rows_by_key = {}
        has_locality_type = (csv.headers || []).include?('Category')

        csv.each_with_index do |csv_row, index|
          row = build_row(csv_row, index, country, filename, errors)
          next if row.nil?

          key = [row.postcode, row.sublocality, row.locality, row.region]
          existing = rows_by_key[key]
          if existing.nil?
            rows_by_key[key] = row
          elsif existing.longitude != row.longitude || existing.latitude != row.latitude
            warnings << "#{filename} row #{index + 2}: duplicate locality (#{key.compact.join(', ')}) with different coordinates - keeping the first occurrence"
          end
        end

        raise ValidationError.new(errors) if errors.any?

        Result.new(country: country, country_code: country_code, rows: rows_by_key.values, warnings: warnings, has_locality_type: has_locality_type)
      end

      # Cheap synchronous check used by the controller before enqueueing the
      # import job: filename convention, headers and a sample of rows.
      def quick_validate(io, filename:)
        country_from_filename(filename)
        csv = read_csv(io, filename)
        check_headers(csv, filename)

        errors = []
        csv.first(QUICK_VALIDATE_ROW_LIMIT).each_with_index do |csv_row, index|
          build_row(csv_row, index, nil, filename, errors)
        end
        raise ValidationError.new(errors) if errors.any?

        true
      end

      def country_from_filename(filename)
        match = File.basename(filename.to_s).match(/\A([A-Za-z]{2})_/)
        unless match
          raise ValidationError.new(["#{filename}: filename must start with a 2-letter country code followed by an underscore (e.g. AU_auspost.csv)"])
        end

        country_code = match[1].upcase
        iso_country = ISO3166::Country.find_country_by_alpha2(country_code)
        raise ValidationError.new(["#{filename}: unknown country code '#{country_code}'"]) unless iso_country

        [country_code, iso_country.iso_short_name.upcase]
      end

      # Maps the AU auspost 'Category' column to a locality_type value; other
      # countries' files have no Category column and get nil here.
      def locality_type(category)
        case category
        when 'Post Office Boxes'
          'post_office_box'
        when 'LVR'
          'lvr'
        else
          nil
        end
      end

      private

      def read_csv(io, filename)
        CSV.parse(io.read.force_encoding('UTF-8').scrub, headers: true)
      rescue CSV::MalformedCSVError => e
        raise ValidationError.new(["#{filename}: malformed CSV - #{e.message}"])
      end

      def check_headers(csv, filename)
        missing = REQUIRED_HEADERS - (csv.headers || []).compact
        raise ValidationError.new(["#{filename}: missing required headers: #{missing.join(', ')}"]) if missing.any?
      end

      def build_row(csv_row, index, country, filename, errors)
        row_errors = []
        postcode = csv_row['Postcode']&.strip.presence
        locality = csv_row['Locality']&.strip.presence
        row_errors << "#{filename} row #{index + 2}: Postcode is blank" unless postcode
        row_errors << "#{filename} row #{index + 2}: Locality is blank" unless locality
        longitude = parse_coordinate(csv_row['Longitude'], 'Longitude', index, filename, row_errors)
        latitude = parse_coordinate(csv_row['Latitude'], 'Latitude', index, filename, row_errors)

        if row_errors.any?
          errors.concat(row_errors)
          return nil
        end

        Row.new(
          postcode,
          csv_row['Sublocality']&.strip.presence&.upcase,
          locality.upcase,
          csv_row['State']&.strip.presence&.upcase,
          country,
          longitude,
          latitude,
          locality_type(csv_row['Category'])
        )
      end

      def parse_coordinate(value, name, index, filename, row_errors)
        stripped = value&.strip.presence
        return BigDecimal('0.0') if stripped.nil?

        Float(stripped)
        BigDecimal(stripped.to_f.round(6).to_s)
      rescue ArgumentError
        row_errors << "#{filename} row #{index + 2}: #{name} '#{value}' is not a number"
        nil
      end

    end
  end

end; end
