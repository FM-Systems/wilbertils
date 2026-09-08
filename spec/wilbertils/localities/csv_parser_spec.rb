require 'spec_helper_lite'
require 'countries'
require 'wilbertils/localities/validation_error'
require 'wilbertils/localities/csv_parser'

describe Wilbertils::Localities::CsvParser do
  subject { described_class }

  let(:filename) { 'AU_auspost.csv' }

  def io_for(content)
    StringIO.new(content)
  end

  describe '.country_from_filename' do
    it 'resolves the country from the 2-letter prefix' do
      expect(subject.country_from_filename('AU_auspost.csv')).to eq(['AU', 'AUSTRALIA'])
      expect(subject.country_from_filename('NZ_nzpost.csv')).to eq(['NZ', 'NEW ZEALAND'])
    end

    it 'rejects filenames without a country prefix' do
      expect { subject.country_from_filename('localities.csv') }
        .to raise_error(Wilbertils::Localities::ValidationError, /2-letter country code/)
    end

    it 'rejects unknown country codes' do
      expect { subject.country_from_filename('XX_localities.csv') }
        .to raise_error(Wilbertils::Localities::ValidationError, /unknown country code 'XX'/)
    end
  end

  describe '.locality_type' do
    it "maps 'Post Office Boxes' to post_office_box" do
      expect(subject.locality_type('Post Office Boxes')).to eq('post_office_box')
    end

    it "maps 'LVR' to lvr" do
      expect(subject.locality_type('LVR')).to eq('lvr')
    end

    it 'maps anything else to nil' do
      expect(subject.locality_type('Something Else')).to be_nil
      expect(subject.locality_type(nil)).to be_nil
      expect(subject.locality_type('')).to be_nil
    end
  end

  describe '.parse' do
    it 'normalizes names to uppercase and coordinates to 6dp BigDecimal' do
      result = subject.parse(io_for(<<~CSV), filename: filename)
        Postcode,Sublocality,Locality,State,Longitude,Latitude
        3054,,Carlton North,vic,144.9706991234,-37.7875512345
      CSV

      expect(result.country).to eq('AUSTRALIA')
      expect(result.country_code).to eq('AU')
      row = result.rows.first
      expect(row.postcode).to eq('3054')
      expect(row.sublocality).to be_nil
      expect(row.locality).to eq('CARLTON NORTH')
      expect(row.region).to eq('VIC')
      expect(row.longitude).to eq(BigDecimal('144.970699'))
      expect(row.latitude).to eq(BigDecimal('-37.787551'))
      expect(row.locality_type).to be_nil
    end

    it 'treats missing Sublocality/State columns and blank coordinates as nil/zero' do
      result = subject.parse(io_for(<<~CSV), filename: filename)
        Postcode,Locality,State,Comments,Category,Longitude,Latitude
        0801,DARWIN,NT,"GPO BOXES","Post Office Boxes",,
      CSV

      row = result.rows.first
      expect(row.sublocality).to be_nil
      expect(row.region).to eq('NT')
      expect(row.longitude).to eq(BigDecimal('0.0'))
      expect(row.latitude).to eq(BigDecimal('0.0'))
      expect(row.locality_type).to eq('post_office_box')
    end

    it 'sets locality_type from the Category column' do
      result = subject.parse(io_for(<<~CSV), filename: filename)
        Postcode,Locality,State,Category,Longitude,Latitude
        4000,BRISBANE,QLD,LVR,153.0,-27.0
      CSV

      expect(result.rows.first.locality_type).to eq('lvr')
    end

    it 'dedupes rows sharing postcode/sublocality/locality/region and warns on coordinate conflicts' do
      result = subject.parse(io_for(<<~CSV), filename: filename)
        Postcode,Sublocality,Locality,State,Longitude,Latitude
        3054,,CARLTON NORTH,VIC,144.9707,-37.7876
        3054,,CARLTON NORTH,VIC,144.9707,-37.7876
        3054,,CARLTON NORTH,VIC,150.0,-30.0
      CSV

      expect(result.rows.size).to eq(1)
      expect(result.rows.first.longitude).to eq(BigDecimal('144.9707'))
      expect(result.warnings.size).to eq(1)
      expect(result.warnings.first).to match(/different coordinates/)
    end

    it 'collects row errors for blank postcode/locality and non-numeric coordinates' do
      expect do
        subject.parse(io_for(<<~CSV), filename: filename)
          Postcode,Sublocality,Locality,State,Longitude,Latitude
          ,,CARLTON NORTH,VIC,144.9707,-37.7876
          3054,,,VIC,144.9707,-37.7876
          3054,,CARLTON NORTH,VIC,not-a-number,-37.7876
        CSV
      end.to raise_error(Wilbertils::Localities::ValidationError) do |error|
        expect(error.errors.size).to eq(3)
        expect(error.errors[0]).to match(/row 2: Postcode is blank/)
        expect(error.errors[1]).to match(/row 3: Locality is blank/)
        expect(error.errors[2]).to match(/row 4: Longitude 'not-a-number' is not a number/)
      end
    end

    it 'rejects files missing required headers' do
      expect { subject.parse(io_for("Postcode,Locality\n3054,CARLTON NORTH\n"), filename: filename) }
        .to raise_error(Wilbertils::Localities::ValidationError, /missing required headers: Longitude, Latitude/)
    end

    it 'reports has_locality_type true when a Category header is present' do
      result = subject.parse(io_for(<<~CSV), filename: filename)
        Postcode,Locality,State,Category,Longitude,Latitude
        4000,BRISBANE,QLD,LVR,153.0,-27.0
      CSV

      expect(result.has_locality_type).to be(true)
    end

    it 'reports has_locality_type false when there is no Category header' do
      result = subject.parse(io_for(<<~CSV), filename: filename)
        Postcode,Locality,State,Longitude,Latitude
        4000,BRISBANE,QLD,153.0,-27.0
      CSV

      expect(result.has_locality_type).to be(false)
    end
  end

  describe '.quick_validate' do
    it 'passes a well-formed file' do
      expect(subject.quick_validate(io_for("Postcode,Locality,Longitude,Latitude\n3054,CARLTON NORTH,144.9,-37.7\n"), filename: filename)).to be(true)
    end

    it 'fails on malformed rows within the sample' do
      expect { subject.quick_validate(io_for("Postcode,Locality,Longitude,Latitude\n,CARLTON NORTH,144.9,-37.7\n"), filename: filename) }
        .to raise_error(Wilbertils::Localities::ValidationError, /Postcode is blank/)
    end
  end
end
