require 'spec_helper_lite'
require 'bigdecimal'
require 'wilbertils/localities/csv_parser'
require 'wilbertils/localities/change_set'
require_relative '../../support/locality'

describe Wilbertils::Localities::ChangeSet do
  # has_locality_type defaults to true - these rows stand in for AU auspost,
  # the one file with a Category column.
  def row(postcode:, sublocality: nil, locality:, region: 'VIC', longitude: '144.970699', latitude: '-37.787551',
          locality_type: nil, has_locality_type: true)
    Wilbertils::Localities::CsvParser::Row.new(
      postcode, sublocality, locality, region, 'AUSTRALIA', BigDecimal(longitude), BigDecimal(latitude),
      locality_type, has_locality_type
    )
  end

  # Stands in for the Locality model: .where(country:).pluck(...). Stubbed on the
  # real class so verify_partial_doubles checks .where and .pluck exist.
  def locality_scope_with(rows)
    plucked = rows.map { |r| [r.id, r.postcode, r.sublocality, r.locality, r.region, r.longitude, r.latitude, r.locality_type] }
    where_scope = instance_double(ActiveRecord::Relation)
    allow(where_scope).to receive(:pluck)
      .with(:id, :postcode, :sublocality, :locality, :region, :longitude, :latitude, :locality_type)
      .and_return(plucked)
    allow(Locality).to receive(:where).with(country: 'AUSTRALIA').and_return(where_scope)
    Locality
  end

  # Mixed-case on purpose: carlton_row upcases it, so a clean match proves
  # identity_key is case-insensitive.
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
      new_postcode: '3055'
    }])
    expect(result.additions).to be_empty
    expect(result.deletions).to be_empty
  end

  it 'still records a coordinate update when the postcode changed too' do
    locality_scope = locality_scope_with([carlton])

    result = described_class.build(
      new_rows: [row(postcode: '3055', locality: carlton.locality.upcase,
                     longitude: '111.111111', latitude: '-22.222222')],
      country: 'AUSTRALIA', locality_scope: locality_scope
    )

    expect(result.postcode_changes.map { |change| change[:new_postcode] }).to eq(['3055'])
    expect(result.coordinate_updates).to eq([{
      id:            carlton.id,
      postcode:      '3054',
      sublocality:   nil,
      locality:      'Carlton North',
      region:        'VIC',
      old_longitude: carlton.longitude,
      old_latitude:  carlton.latitude,
      longitude:     BigDecimal('111.111111'),
      latitude:      BigDecimal('-22.222222')
    }])
    expect(result.additions).to be_empty
    expect(result.deletions).to be_empty
  end

  it 'records a postcode change, a coordinate update and a type change for one locality at once' do
    locality_scope = locality_scope_with([carlton])

    result = described_class.build(
      new_rows: [row(postcode: '3055', locality: carlton.locality.upcase,
                     longitude: '111.111111', latitude: '-22.222222',
                     locality_type: 'lvr')],
      country: 'AUSTRALIA', locality_scope: locality_scope
    )

    expect(result.postcode_changes.map { |change| change[:new_postcode] }).to eq(['3055'])
    expect(result.coordinate_updates.map { |update| update[:longitude] }).to eq([BigDecimal('111.111111')])
    expect(result.locality_type_changes.map { |change| change[:to] }).to eq(['lvr'])
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
    # The double returns only AUSTRALIA rows, as Locality.where(country:) would.
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

    # Reclassified out of Post Office Boxes / LVR: keeping the old type would
    # leave the locality rejecting street addresses forever.
    it 'clears the type when the file has a Category column and the row is no longer typed' do
      pob_carlton = Wilbertils::Localities::ChangeSet::DbRow.new(
        1, '3054', nil, 'Carlton North', 'VIC', BigDecimal('144.970699'), BigDecimal('-37.787551'), 'post_office_box'
      )
      locality_scope = locality_scope_with([pob_carlton])
      new_row = row(postcode: pob_carlton.postcode, locality: pob_carlton.locality.upcase,
                    longitude: pob_carlton.longitude.to_s, latitude: pob_carlton.latitude.to_s,
                    locality_type: nil, has_locality_type: true)

      result = described_class.build(new_rows: [new_row], country: 'AUSTRALIA', locality_scope: locality_scope)

      expect(result.locality_type_changes).to eq([{
        id:          pob_carlton.id,
        postcode:    '3054',
        sublocality: nil,
        locality:    'Carlton North',
        region:      'VIC',
        from:        'post_office_box',
        to:          nil
      }])
    end

    it 'leaves an existing type alone when the file has no Category column' do
      pob_carlton = Wilbertils::Localities::ChangeSet::DbRow.new(
        1, '3054', nil, 'Carlton North', 'VIC', BigDecimal('144.970699'), BigDecimal('-37.787551'), 'post_office_box'
      )
      locality_scope = locality_scope_with([pob_carlton])
      new_row = row(postcode: pob_carlton.postcode, locality: pob_carlton.locality.upcase,
                    longitude: pob_carlton.longitude.to_s, latitude: pob_carlton.latitude.to_s,
                    locality_type: nil, has_locality_type: false)

      result = described_class.build(new_rows: [new_row], country: 'AUSTRALIA', locality_scope: locality_scope)

      expect(result.locality_type_changes).to be_empty
    end

    # Matched by name, not identity_key - this path used to skip the field diff.
    it 'still records a locality_type change when the postcode changed too' do
      locality_scope = locality_scope_with([carlton])

      result = described_class.build(
        new_rows: [row(postcode: '3055', locality: carlton.locality.upcase,
                       longitude: carlton.longitude.to_s, latitude: carlton.latitude.to_s,
                       locality_type: 'post_office_box')],
        country: 'AUSTRALIA', locality_scope: locality_scope
      )

      expect(result.postcode_changes.map { |change| change[:new_postcode] }).to eq(['3055'])
      expect(result.locality_type_changes).to eq([{
        id:          carlton.id,
        postcode:    '3054',
        sublocality: nil,
        locality:    'Carlton North',
        region:      'VIC',
        from:        nil,
        to:          'post_office_box'
      }])
      expect(result.additions).to be_empty
      expect(result.deletions).to be_empty
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
