require 'csv'
require 'active_support/core_ext/enumerable'

module Wilbertils; module Localities

  # Collects every change an import run makes (or, in dry-run mode, would
  # make). The summary_counts hash is small enough to store in Sidekiq::Status;
  # the full drill-down goes to S3 as a CSV via #to_csv.
  #
  # Subclasses must declare their own SECTIONS (an ordered Hash of
  # section_key => label) and ESTIMATED_IN_DRY_RUN (an array of section keys
  # whose dry-run counts are estimates) constants - this base class has no
  # sensible defaults since the set of sections is app-specific.
  class Report

    attr_reader :dry_run, :country, :filenames
    attr_accessor :csv_row_count, :db_row_count, :guardrail_violations,
                  :reseed_performed, :reindex_performed

    def initialize(dry_run:, country:, filenames:)
      @dry_run = dry_run
      @country = country
      @filenames = filenames
      @sections = sections.keys.index_with { [] }
      @csv_row_count = 0
      @db_row_count = 0
      @guardrail_violations = []
      @reseed_performed = false
      @reindex_performed = false
    end

    def add(section, detail:, postcode: nil, sublocality: nil, locality: nil, region: nil)
      @sections.fetch(section) << {
        postcode:    postcode,
        sublocality: sublocality,
        locality:    locality,
        region:      region,
        detail:      detail
      }
    end

    def [](section)
      @sections.fetch(section)
    end

    def summary_counts
      {
        country:              country,
        dry_run:              dry_run,
        filenames:            filenames,
        csv_row_count:        csv_row_count,
        db_row_count:         db_row_count,
        guardrail_violations: guardrail_violations,
        reseed_performed:     reseed_performed,
        reindex_performed:    reindex_performed,
        sections: sections.map do |key, label|
          {
            key:       key,
            label:     label,
            count:     @sections[key].size,
            estimated: dry_run && estimated_in_dry_run.include?(key)
          }
        end
      }
    end

    def to_csv
      CSV.generate(force_quotes: true) do |csv|
        csv << %w(Section Postcode Sublocality Locality Region Detail)
        sections.each do |key, label|
          @sections[key].each do |entry|
            csv << [label, entry[:postcode], entry[:sublocality], entry[:locality], entry[:region], entry[:detail]]
          end
        end
      end
    end

    private

    def sections
      self.class::SECTIONS
    rescue NameError
      raise NotImplementedError, "#{self.class} must define a SECTIONS constant (an ordered Hash of section_key => label)"
    end

    def estimated_in_dry_run
      self.class::ESTIMATED_IN_DRY_RUN
    rescue NameError
      raise NotImplementedError, "#{self.class} must define an ESTIMATED_IN_DRY_RUN constant (an array of section keys)"
    end

  end

end; end
