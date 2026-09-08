require 'spec_helper_lite'
require 'bigdecimal'
require 'wilbertils/localities/csv_parser'
require 'wilbertils/localities/change_set'

describe Wilbertils::Localities::ChangeSet do
  def row(postcode:, sublocality: nil, locality:, region: 'VIC', longitude: '144.970699', latitude: '-37.787551', locality_type: nil)
    Wilbertils::Localities::CsvParser::Row.new(
      postcode, sublocality, locality, region, 'AUSTRALIA', BigDecimal(longitude), BigDecimal(latitude), locality_type
    )
  end

  # A locality_scope double whose `.where(country:).pluck(...)` returns the
  # given DbRow tuples - stands in for the ActiveRecord Locality model.
  def locality_scope_with(rows)
    plucked = rows.map { |r| [r.id, r.postcode, r.sublocality, r.locality, r.region, r.longitude, r.latitude, r.locality_type] }
    scope = double('locality_scope')
    where_scope = double('where_scope')
    allow(scope).to receive(:where).with(country: 'AUSTRALIA').and_return(where_scope)
    allow(where_scope).to receive(:pluck)
      .with(:id, :postcode, :sublocality, :locality, :region, :longitude, :latitude, :locality_type)
      .and_return(plucked)
    scope
  end

  let(:carlton) do
    Wilbertils::Localities::ChangeSet::DbRow.new(
      1, '3054', nil, 'Carlton North', 'VIC', BigDecimal('144.970699'), BigDecimal('-37.787551'), nil
    )
  end
  let(:carlton_row) do
    row(postcode: carlton.postcode, locality: carlton.locality.upcase,
        longitude: carlton.longitude.to_s, latitude: carlton.latitude.to_s)
  end

  it 'reports no changes when the CSV matches the database' do
    locality_scope = locality_scope_with([carlton])
    result = described_class.build(new_rows: [carlton_row], country: 'AUSTRALIA', locality_scope: locality_scope)

    expect(result.coordinate_updates).to be_empty
    expect(result.postcode_changes).to be_empty
    expect(result.additions).to be_empty
    expect(result.deletions).to be_empty
    expect(result.locality_type_changes).to be_empty
    expect(result.db_count).to eq(1)
  end

  it 'flags mixed-case DB locality names as case fixes without add/delete churn' do
    locality_scope = locality_scope_with([carlton])
    result = described_class.build(new_rows: [carlton_row], country: 'AUSTRALIA', locality_scope: locality_scope)

    expect(result.case_fixes).to eq([{ id: carlton.id, from: 'Carlton North', to: 'CARLTON NORTH' }])
    expect(result.additions).to be_empty
    expect(result.deletions).to be_empty
  end

  it 'classifies matched localities with different coordinates as coordinate updates' do
    changed = carlton_row.dup
    changed.longitude = BigDecimal('145.5')

    locality_scope = locality_scope_with([carlton])
    result = described_class.build(new_rows: [changed], country: 'AUSTRALIA', locality_scope: locality_scope)

    expect(result.coordinate_updates.size).to eq(1)
    update = result.coordinate_updates.first
    expect(update[:id]).to eq(carlton.id)
    expect(update[:longitude]).to eq(BigDecimal('145.5'))
    expect(update[:old_longitude]).to eq(carlton.longitude)
    expect(result.additions).to be_empty
    expect(result.deletions).to be_empty
  end

  it 'classifies new and missing localities as additions and deletions' do
    locality_scope = locality_scope_with([carlton])
    result = described_class.build(
      new_rows: [carlton_row, row(postcode: '3134', locality: 'RINGWOOD'), row(postcode: '3134', locality: 'RINGWOOD EAST')],
      country: 'AUSTRALIA', locality_scope: locality_scope
    )

    expect(result.additions.map(&:locality)).to contain_exactly('RINGWOOD', 'RINGWOOD EAST')
    expect(result.deletions).to be_empty

    locality_scope = locality_scope_with([carlton])
    result = described_class.build(new_rows: [], country: 'AUSTRALIA', locality_scope: locality_scope)
    expect(result.deletions.map(&:id)).to eq([carlton.id])
  end

  it 'promotes a 1:1 name match with a different postcode to a postcode change' do
    locality_scope = locality_scope_with([carlton])
    result = described_class.build(
      new_rows: [row(postcode: '3055', locality: carlton.locality.upcase,
                     longitude: carlton.longitude.to_s, latitude: carlton.latitude.to_s)],
      country: 'AUSTRALIA', locality_scope: locality_scope
    )

    expect(result.postcode_changes).to eq([{
      id:           carlton.id,
      sublocality:  nil,
      locality:     'CARLTON NORTH',
      region:       'VIC',
      old_postcode: '3054',
      new_postcode: '3055',
      longitude:    carlton.longitude,
      latitude:     carlton.latitude
    }])
    expect(result.additions).to be_empty
    expect(result.deletions).to be_empty
  end

  it 'does not promote to a postcode change when the name is not unique on both sides' do
    second_carlton = Wilbertils::Localities::ChangeSet::DbRow.new(
      2, '3055', nil, 'Carlton North', 'VIC', BigDecimal('144.970699'), BigDecimal('-37.787551'), nil
    )
    locality_scope = locality_scope_with([carlton, second_carlton])

    result = described_class.build(
      new_rows: [row(postcode: '3056', locality: carlton.locality.upcase)],
      country: 'AUSTRALIA', locality_scope: locality_scope
    )

    expect(result.postcode_changes).to be_empty
    expect(result.additions.map(&:postcode)).to eq(['3056'])
    expect(result.deletions.map(&:postcode)).to contain_exactly('3054', '3055')
  end

  it 'never considers localities of other countries for deletion (host scopes locality_scope by country)' do
    # locality_scope.where(country:) is the injection point that keeps this
    # scoped - the double here only ever returns AUSTRALIA rows, mirroring how
    # Locality.where(country: 'AUSTRALIA') would exclude NZ rows.
    locality_scope = locality_scope_with([carlton])
    result = described_class.build(new_rows: [], country: 'AUSTRALIA', locality_scope: locality_scope)

    expect(result.deletions.map(&:id)).to eq([carlton.id])
    expect(result.db_count).to eq(1)
  end

  describe 'locality_type_changes' do
    it 'records a change when the new locality_type is present and differs from the DB value' do
      locality_scope = locality_scope_with([carlton])
      new_row = row(postcode: carlton.postcode, locality: carlton.locality.upcase,
                    longitude: carlton.longitude.to_s, latitude: carlton.latitude.to_s,
                    locality_type: 'post_office_box')

      result = described_class.build(new_rows: [new_row], country: 'AUSTRALIA', locality_scope: locality_scope)

      expect(result.locality_type_changes).to eq([{
        id:          carlton.id,
        postcode:    carlton.postcode,
        sublocality: nil,
        locality:    carlton.locality,
        region:      'VIC',
        from:        nil,
        to:          'post_office_box'
      }])
    end

    it 'does not record a change when the new locality_type is nil, even though the DB row has one' do
      pob_carlton = Wilbertils::Localities::ChangeSet::DbRow.new(
        1, '3054', nil, 'Carlton North', 'VIC', BigDecimal('144.970699'), BigDecimal('-37.787551'), 'post_office_box'
      )
      locality_scope = locality_scope_with([pob_carlton])
      new_row = row(postcode: pob_carlton.postcode, locality: pob_carlton.locality.upcase,
                    longitude: pob_carlton.longitude.to_s, latitude: pob_carlton.latitude.to_s,
                    locality_type: nil)

      result = described_class.build(new_rows: [new_row], country: 'AUSTRALIA', locality_scope: locality_scope)

      expect(result.locality_type_changes).to be_empty
    end

    it 'does not record a change when the new locality_type matches the DB value' do
      pob_carlton = Wilbertils::Localities::ChangeSet::DbRow.new(
        1, '3054', nil, 'Carlton North', 'VIC', BigDecimal('144.970699'), BigDecimal('-37.787551'), 'post_office_box'
      )
      locality_scope = locality_scope_with([pob_carlton])
      new_row = row(postcode: pob_carlton.postcode, locality: pob_carlton.locality.upcase,
                    longitude: pob_carlton.longitude.to_s, latitude: pob_carlton.latitude.to_s,
                    locality_type: 'post_office_box')

      result = described_class.build(new_rows: [new_row], country: 'AUSTRALIA', locality_scope: locality_scope)

      expect(result.locality_type_changes).to be_empty
    end
  end
end
