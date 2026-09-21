require 'spec_helper_lite'
require 'wilbertils/localities/report'

describe Wilbertils::Localities::Report do
  class TestReport < Wilbertils::Localities::Report
    SECTIONS = {
      additions: 'New localities',
      deletions: 'Deleted localities'
    }.freeze

    ESTIMATED_IN_DRY_RUN = %i(deletions).freeze
  end

  describe 'a subclass without SECTIONS/ESTIMATED_IN_DRY_RUN declared' do
    class BareReport < Wilbertils::Localities::Report; end

    it 'raises a clear NotImplementedError when sections are used' do
      expect { BareReport.new(dry_run: false, country: 'AUSTRALIA', filenames: []) }
        .to raise_error(NotImplementedError, /SECTIONS/)
    end
  end

  describe '#add and #[]' do
    it 'stores entries under the given section' do
      report = TestReport.new(dry_run: false, country: 'AUSTRALIA', filenames: %w(AU_auspost.csv))
      report.add(:additions, detail: 'New locality', postcode: '3054', sublocality: nil, locality: 'CARLTON NORTH', region: 'VIC')

      expect(report[:additions]).to eq([{
        postcode:    '3054',
        sublocality: nil,
        locality:    'CARLTON NORTH',
        region:      'VIC',
        detail:      'New locality'
      }])
      expect(report[:deletions]).to be_empty
    end

    it 'raises on an unknown section' do
      report = TestReport.new(dry_run: false, country: 'AUSTRALIA', filenames: [])
      expect { report[:not_a_section] }.to raise_error(KeyError)
    end
  end

  describe '#summary_counts' do
    it 'includes counts per section and marks estimated sections only in dry-run' do
      report = TestReport.new(dry_run: true, country: 'AUSTRALIA', filenames: %w(AU_auspost.csv))
      report.add(:additions, detail: 'a')
      report.add(:deletions, detail: 'b')
      report.csv_row_count = 10
      report.db_row_count = 9

      counts = report.summary_counts
      expect(counts[:country]).to eq('AUSTRALIA')
      expect(counts[:dry_run]).to eq(true)
      expect(counts[:filenames]).to eq(%w(AU_auspost.csv))
      expect(counts[:csv_row_count]).to eq(10)
      expect(counts[:db_row_count]).to eq(9)

      additions_section = counts[:sections].detect { |s| s[:key] == :additions }
      deletions_section = counts[:sections].detect { |s| s[:key] == :deletions }
      expect(additions_section).to include(label: 'New localities', count: 1, estimated: false)
      expect(deletions_section).to include(label: 'Deleted localities', count: 1, estimated: true)
    end

    it 'never marks a section estimated outside dry-run' do
      report = TestReport.new(dry_run: false, country: 'AUSTRALIA', filenames: [])
      report.add(:deletions, detail: 'b')

      deletions_section = report.summary_counts[:sections].detect { |s| s[:key] == :deletions }
      expect(deletions_section[:estimated]).to eq(false)
    end
  end

  describe '#to_csv' do
    it 'writes a header row plus one row per entry, grouped by section' do
      report = TestReport.new(dry_run: false, country: 'AUSTRALIA', filenames: [])
      report.add(:additions, detail: 'New locality', postcode: '3054', sublocality: nil, locality: 'CARLTON NORTH', region: 'VIC')
      report.add(:deletions, detail: 'Deleted', postcode: '3055', sublocality: nil, locality: 'FOO', region: 'VIC')

      rows = CSV.parse(report.to_csv)
      expect(rows[0]).to eq(%w(Section Postcode Sublocality Locality Region Detail))
      expect(rows[1]).to eq(['New localities', '3054', '', 'CARLTON NORTH', 'VIC', 'New locality'])
      expect(rows[2]).to eq(['Deleted localities', '3055', '', 'FOO', 'VIC', 'Deleted'])
    end
  end
end
