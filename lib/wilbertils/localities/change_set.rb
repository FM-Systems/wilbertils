module Wilbertils; module Localities

  # Diffs uploaded CSV rows against one country's localities. No writes -
  # the caller applies the result.
  #
  # Identity is (postcode, sublocality, locality, region), case-insensitive.
  class ChangeSet

    DbRow = Struct.new(:id, :postcode, :sublocality, :locality, :region, :longitude, :latitude, :locality_type)
    Result = Struct.new(:coordinate_updates, :postcode_changes, :additions, :deletions, :db_count, :locality_type_changes, keyword_init: true)

    class << self

      def build(new_rows:, country:, locality_scope: Locality)
        db_rows = locality_scope.where(country: country)
                          .pluck(:id, :postcode, :sublocality, :locality, :region, :longitude, :latitude, :locality_type)
                          .map { |values| DbRow.new(*values) }

        old_by_key = {}
        duplicate_old_rows = []
        db_rows.each do |row|
          key = identity_key(row)
          if old_by_key.key?(key)
            duplicate_old_rows << row
          else
            old_by_key[key] = row
          end
        end

        new_by_key = {}
        new_rows.each { |row| new_by_key[identity_key(row)] ||= row }

        coordinate_updates = []
        locality_type_changes = []
        unmatched_old = duplicate_old_rows
        old_by_key.each do |key, old_row|
          new_row = new_by_key[key]
          if new_row.nil?
            unmatched_old << old_row
          else
            diff_matched_pair(old_row, new_row, coordinate_updates, locality_type_changes)
          end
        end
        unmatched_new = new_by_key.reject { |key, _| old_by_key.key?(key) }.values

        postcode_changes = detect_postcode_changes(unmatched_old, unmatched_new,
                                                   coordinate_updates, locality_type_changes)

        Result.new(
          coordinate_updates:     coordinate_updates,
          postcode_changes:       postcode_changes,
          additions:              unmatched_new,
          deletions:              unmatched_old,
          db_count:               db_rows.size,
          locality_type_changes:  locality_type_changes
        )
      end

      private

      def identity_key(row)
        [row.postcode, row.sublocality&.upcase, row.locality&.upcase, row.region&.upcase]
      end

      def name_key(row)
        [row.sublocality&.upcase, row.locality&.upcase, row.region&.upcase]
      end

      # Per-field diff for a matched pair, shared by both match paths so they
      # cannot disagree.
      def diff_matched_pair(old_row, new_row, coordinate_updates, locality_type_changes)
        if old_row.longitude != new_row.longitude || old_row.latitude != new_row.latitude
          coordinate_updates << {
            id:            old_row.id,
            postcode:      old_row.postcode,
            sublocality:   old_row.sublocality,
            locality:      old_row.locality,
            region:        old_row.region,
            old_longitude: old_row.longitude,
            old_latitude:  old_row.latitude,
            longitude:     new_row.longitude,
            latitude:      new_row.latitude
          }
        end

        # No Category column means the file says nothing about types; one that
        # has it is authoritative, so an untyped row clears the old type.
        return unless new_row.has_locality_type
        return if new_row.locality_type == old_row.locality_type

        locality_type_changes << {
          id:          old_row.id,
          postcode:    old_row.postcode,
          sublocality: old_row.sublocality,
          locality:    old_row.locality,
          region:      old_row.region,
          from:        old_row.locality_type,
          to:          new_row.locality_type
        }
      end

      # A name unique on both sides with a different postcode is a postcode
      # change, not delete (losing carrier depots) + add. Mutates both arrays.
      def detect_postcode_changes(unmatched_old, unmatched_new, coordinate_updates, locality_type_changes)
        old_singles = unmatched_old.group_by { |row| name_key(row) }.select { |_, rows| rows.one? }
        new_singles = unmatched_new.group_by { |row| name_key(row) }.select { |_, rows| rows.one? }

        old_singles.filter_map do |key, (old_row)|
          new_row = new_singles[key]&.first
          next unless new_row

          unmatched_old.delete(old_row)
          unmatched_new.delete(new_row)
          diff_matched_pair(old_row, new_row, coordinate_updates, locality_type_changes)

          # Coordinates travel as their own coordinate_updates entry above.
          {
            id:           old_row.id,
            sublocality:  new_row.sublocality,
            locality:     new_row.locality,
            region:       new_row.region,
            old_postcode: old_row.postcode,
            new_postcode: new_row.postcode
          }
        end
      end

    end
  end

end; end
