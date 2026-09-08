require 'spec_helper_lite'
require 'stringio'
require 'wilbertils/localities/validation_error'
require 'wilbertils/localities/timezone_csv'

describe Wilbertils::Localities::TimezoneCsv do

  Loc = Struct.new(:postcode, :sublocality, :locality, :region, :timezone, keyword_init: true) unless defined?(Loc)

  # Stands in for the ActiveRecord Locality model: .where(country:).select(...).find_each
  def locality_scope_with(localities)
    scope = double('locality_scope')
    where_scope = double('where_scope')
    select_scope = double('select_scope')
    allow(scope).to receive(:where).with(country: 'AUSTRALIA').and_return(where_scope)
    allow(where_scope).to receive(:select)
      .with(:id, :postcode, :sublocality, :locality, :region, :timezone)
      .and_return(select_scope)
    allow(select_scope).to receive(:find_each) { |&block| localities.each(&block) }
    scope
  end

  describe '.generate' do
    it 'writes the header in HEADERS order and one row per locality with a timezone' do
      scope = locality_scope_with([
        Loc.new(postcode: '3054', sublocality: nil, locality: 'CARLTON NORTH', region: 'VIC', timezone: 'Australia/Melbourne'),
        Loc.new(postcode: '0110', sublocality: 'PARAHAKI', locality: 'WHANGAREI', region: nil, timezone: 'Pacific/Auckland')
      ])

      result = described_class.generate(country: 'AUSTRALIA', locality_scope: scope)

      lines = result.csv.strip.split("\n")
      expect(lines.first).to eq('Postcode,Sublocality,Locality,Region,Timezone')
      expect(lines[1]).to eq('3054,,CARLTON NORTH,VIC,Australia/Melbourne')
      expect(lines[2]).to eq('0110,PARAHAKI,WHANGAREI,,Pacific/Auckland')
      expect(result.row_count).to eq(2)
      expect(result.unresolved_count).to eq(0)
    end

    it 'skips localities with a blank timezone and counts them as unresolved' do
      scope = locality_scope_with([
        Loc.new(postcode: '3054', sublocality: nil, locality: 'CARLTON NORTH', region: 'VIC', timezone: 'Australia/Melbourne'),
        Loc.new(postcode: '3181', sublocality: nil, locality: 'PRAHRAN', region: 'VIC', timezone: nil),
        Loc.new(postcode: '3182', sublocality: nil, locality: 'ST KILDA', region: 'VIC', timezone: '')
      ])

      result = described_class.generate(country: 'AUSTRALIA', locality_scope: scope)

      expect(result.csv).not_to include('PRAHRAN')
      expect(result.csv).not_to include('ST KILDA')
      expect(result.row_count).to eq(1)
      expect(result.unresolved_count).to eq(2)
    end

    it 'emits a header-only file when the country has no localities' do
      result = described_class.generate(country: 'AUSTRALIA', locality_scope: locality_scope_with([]))

      expect(result.csv.strip).to eq('Postcode,Sublocality,Locality,Region,Timezone')
      expect(result.row_count).to eq(0)
    end
  end

  describe '.parse' do
    let(:csv) do
      "Postcode,Sublocality,Locality,Region,Timezone\n" \
      "3054,,carlton north,vic,Australia/Melbourne\n" \
      "0110,parahaki,whangarei,,Pacific/Auckland\n"
    end

    it 'keys rows the way key_for does, so lookups match ChangeSet identity' do
      lookup = described_class.parse(StringIO.new(csv))

      expect(lookup[described_class.key_for(postcode: '3054', sublocality: nil, locality: 'CARLTON NORTH', region: 'VIC')])
        .to eq('Australia/Melbourne')
      expect(lookup[described_class.key_for(postcode: '0110', sublocality: 'PARAHAKI', locality: 'WHANGAREI', region: nil)])
        .to eq('Pacific/Auckland')
    end

    it 'round-trips what generate produced' do
      scope = locality_scope_with([
        Loc.new(postcode: '3054', sublocality: nil, locality: 'CARLTON NORTH', region: 'VIC', timezone: 'Australia/Melbourne')
      ])
      generated = described_class.generate(country: 'AUSTRALIA', locality_scope: scope)

      lookup = described_class.parse(StringIO.new(generated.csv))

      expect(lookup.values).to eq(['Australia/Melbourne'])
    end

    it 'omits rows with a blank timezone' do
      lookup = described_class.parse(StringIO.new("Postcode,Sublocality,Locality,Region,Timezone\n3181,,PRAHRAN,VIC,\n"))

      expect(lookup).to be_empty
    end

    it 'raises ValidationError naming the missing headers' do
      expect { described_class.parse(StringIO.new("Postcode,Locality\n3054,CARLTON\n"), filename: 'AU_timezones.csv') }
        .to raise_error(Wilbertils::Localities::ValidationError, /AU_timezones\.csv: missing required headers: Sublocality, Region, Timezone/)
    end
  end

  describe '.key_for' do
    it 'upcases the name parts, leaves the postcode alone and blanks become nil' do
      expect(described_class.key_for(postcode: ' 3054 ', sublocality: '', locality: ' carlton north ', region: 'vic'))
        .to eq(['3054', nil, 'CARLTON NORTH', 'VIC'])
    end
  end

end
