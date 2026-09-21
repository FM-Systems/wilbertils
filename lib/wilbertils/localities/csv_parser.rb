require 'csv'
require 'bigdecimal'
require 'active_support/core_ext/object/blank'

module Wilbertils; module Localities

  # Parses an uploaded locality CSV into normalized rows. Filename needs the
  # 2-letter ISO country prefix (AU_auspost.csv); blank coordinates become 0.0.
  class CsvParser

    # has_locality_type: had a Category column, so a nil locality_type means
    # untyped - see ChangeSet#diff_matched_pair.
    Row = Struct.new(:postcode, :sublocality, :locality, :region, :country, :longitude, :latitude, :locality_type,
                     :has_locality_type)
    Result = Struct.new(:country, :country_code, :rows, :warnings, keyword_init: true)

    REQUIRED_HEADERS = %w(Postcode Locality Longitude Latitude).freeze
    QUICK_VALIDATE_ROW_LIMIT = 100

    # Excel strips leading zeros when these files are re-saved. Keyed by
    # country code; countries not listed are left alone.
    REQUIRED_POSTCODE_WIDTH = { 'AU' => 4, 'NZ' => 4 }.freeze

    class << self

      def parse(io, filename:)
        country_code, country = country_from_filename(filename)
        csv = read_csv(io, filename)
        check_headers(csv, filename)

        errors = []
        warnings = []
        rows_by_key = {}
        has_locality_type = has_locality_type?(csv)

        csv.each_with_index do |csv_row, index|
          row = build_row(csv_row, index, country, country_code, filename, errors, has_locality_type)
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

        Result.new(country: country, country_code: country_code, rows: rows_by_key.values, warnings: warnings)
      end

      # Cheap synchronous check before the import job is enqueued.
      def quick_validate(io, filename:)
        country_code, = country_from_filename(filename)
        csv = read_csv(io, filename)
        check_headers(csv, filename)

        errors = []
        has_locality_type = has_locality_type?(csv)
        csv.first(QUICK_VALIDATE_ROW_LIMIT).each_with_index do |csv_row, index|
          build_row(csv_row, index, nil, country_code, filename, errors, has_locality_type)
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

      # AU auspost's 'Category' column; other countries' files have none.
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

      def has_locality_type?(csv)
        (csv.headers || []).include?('Category')
      end

      def check_headers(csv, filename)
        missing = REQUIRED_HEADERS - (csv.headers || []).compact
        raise ValidationError.new(["#{filename}: missing required headers: #{missing.join(', ')}"]) if missing.any?
      end

      def build_row(csv_row, index, country, country_code, filename, errors, has_locality_type)
        row_errors = []
        postcode = pad_postcode(csv_row['Postcode']&.strip.presence, country_code)
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
          locality_type(csv_row['Category']),
          has_locality_type
        )
      end

      # Silent - a stripped leading zero is an Excel artefact, not bad data.
      def pad_postcode(postcode, country_code)
        return postcode unless postcode

        width = REQUIRED_POSTCODE_WIDTH[country_code]
        return postcode unless width && postcode =~ /\A\d+\z/ && postcode.length < width

        postcode.rjust(width, '0')
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
