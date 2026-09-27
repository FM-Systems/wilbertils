require 'spec_helper_lite'
require 'wilbertils/localities/validation_error'
require 'wilbertils/localities/guardrails'

describe Wilbertils::Localities::Guardrails do
  subject { described_class }

  # Guardrails only reads db_count and deletions.size off the ChangeSet result.
  def change_set(db_count:, deletions:)
    Struct.new(:db_count, :deletions).new(db_count, Array.new(deletions))
  end

  describe '.violations' do
    it 'is empty for an import within both limits' do
      expect(subject.violations(change_set: change_set(db_count: 100, deletions: 20), csv_row_count: 50, country: 'AUSTRALIA'))
        .to eq([])
    end

    it 'flags deleting more than 20% of the country' do
      violations = subject.violations(change_set: change_set(db_count: 100, deletions: 21), csv_row_count: 100, country: 'AUSTRALIA')

      expect(violations).to eq(['Import would delete 21 of 100 existing AUSTRALIA localities (over the 20% safety limit)'])
    end

    it "flags an upload with under half the country's localities" do
      violations = subject.violations(change_set: change_set(db_count: 100, deletions: 0), csv_row_count: 49, country: 'AUSTRALIA')

      expect(violations.size).to eq(1)
      expect(violations.first).to start_with('Uploaded file(s) contain 49 localities but AUSTRALIA currently has 100 - upload ALL')
    end

    it 'rounds the coverage limit up, so an odd count needs a strict majority' do
      expect(subject.violations(change_set: change_set(db_count: 5, deletions: 0), csv_row_count: 2, country: 'AUSTRALIA').size).to eq(1)
      expect(subject.violations(change_set: change_set(db_count: 5, deletions: 0), csv_row_count: 3, country: 'AUSTRALIA')).to eq([])
    end

    it 'reports both limits together' do
      violations = subject.violations(change_set: change_set(db_count: 100, deletions: 60), csv_row_count: 40, country: 'AUSTRALIA')

      expect(violations.size).to eq(2)
    end

    it 'never flags a country with no localities yet' do
      expect(subject.violations(change_set: change_set(db_count: 0, deletions: 0), csv_row_count: 0, country: 'AUSTRALIA'))
        .to eq([])
    end
  end

  describe '.enforce!' do
    it 'raises every violation, prefixed Aborted, on an apply' do
      expect { subject.enforce!(['too many deletions', 'too few rows'], dry_run: false) }
        .to raise_error(Wilbertils::Localities::ValidationError) { |error|
          expect(error.errors).to eq(['Aborted: too many deletions', 'Aborted: too few rows'])
        }
    end

    it 'only reports on a dry run' do
      expect { subject.enforce!(['too many deletions'], dry_run: true) }.not_to raise_error
    end

    it 'passes an apply with no violations' do
      expect { subject.enforce!([], dry_run: false) }.not_to raise_error
    end
  end
end
