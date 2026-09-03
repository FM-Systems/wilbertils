require 'spec_helper_lite'
require 'wilbertils/table_swap'

describe Wilbertils::TableSwap do

  # There is no database in this spec suite (see spec_helper_lite), so a
  # fake connection stands in for ActiveRecord::Base.connection - it just
  # records every statement it is given, in order, and quotes identifiers
  # the same way the MySQL adapter does.
  class FakeConnection
    attr_reader :log
    attr_accessor :open_transactions

    def initialize(row_count: 0)
      @log = []
      @open_transactions = 0
      @row_count = row_count
    end

    def execute(sql)
      @log << sql
    end

    def select_value(sql)
      @log << sql
      @row_count
    end

    def quote_table_name(identifier)
      "`#{identifier}`"
    end
    alias quote_column_name quote_table_name
  end

  let(:connection) { FakeConnection.new }

  it 'emits create, then yields, then renames, then drops the backup - in that order' do
    described_class.rebuild('widgets', connection: connection, epoch: 1) do |staging_table|
      expect(staging_table).to eq('widgets_swap_1')
      connection.execute("-- populate #{staging_table}")
    end

    expect(connection.log).to eq([
      'CREATE TABLE `widgets_swap_1` LIKE `widgets`',
      '-- populate widgets_swap_1',
      'RENAME TABLE `widgets` TO `widgets_swapold_1`, `widgets_swap_1` TO `widgets`',
      'DROP TABLE `widgets_swapold_1`',
      'SELECT COUNT(*) FROM `widgets`',
      'DROP TABLE IF EXISTS `widgets_swap_1`'
    ])
  end

  it 'in a dry run creates, yields, and drops the staging table - with no rename' do
    connection = FakeConnection.new(row_count: 3)

    count = described_class.rebuild('widgets', connection: connection, dry_run: true, epoch: 2) do |staging_table|
      connection.execute("-- populate #{staging_table}")
    end

    expect(connection.log).to eq([
      'CREATE TABLE `widgets_swap_2` LIKE `widgets`',
      '-- populate widgets_swap_2',
      'SELECT COUNT(*) FROM `widgets_swap_2`',
      'DROP TABLE IF EXISTS `widgets_swap_2`'
    ])
    expect(count).to eq(3)
  end

  it 'drops the staging table and re-raises the original error when the block raises' do
    expect do
      described_class.rebuild('widgets', connection: connection, epoch: 3) do |staging_table|
        connection.execute("-- populate #{staging_table}")
        raise ArgumentError, 'deliberate failure from the spec'
      end
    end.to raise_error(ArgumentError, 'deliberate failure from the spec')

    expect(connection.log).to eq([
      'CREATE TABLE `widgets_swap_3` LIKE `widgets`',
      '-- populate widgets_swap_3',
      'DROP TABLE IF EXISTS `widgets_swap_3`'
    ])
  end

  describe 'foreign_keys:' do
    let(:foreign_key) do
      {name: 'fk_rails_4bb88e9095', column: 'locality_id', to_table: 'localities',
       primary_key: 'id', on_delete: 'RESTRICT', on_update: 'RESTRICT'}
    end

    it 'adds the foreign key only after the rename and the backup drop' do
      described_class.rebuild('widgets', connection: connection, epoch: 4, foreign_keys: [foreign_key]) do |staging_table|
        connection.execute("-- populate #{staging_table}")
      end

      rename_index      = connection.log.index { |sql| sql.start_with?('RENAME TABLE') }
      drop_backup_index = connection.log.index('DROP TABLE `widgets_swapold_4`')
      alter_index        = connection.log.index { |sql| sql.start_with?('ALTER TABLE') }

      expect(rename_index).not_to be_nil
      expect(drop_backup_index).not_to be_nil
      expect(alter_index).not_to be_nil
      expect(alter_index).to be > rename_index
      expect(alter_index).to be > drop_backup_index

      expect(connection.log[alter_index]).to eq(
        'ALTER TABLE `widgets` ADD CONSTRAINT `fk_rails_4bb88e9095` FOREIGN KEY (`locality_id`) ' \
        'REFERENCES `localities` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT'
      )
    end

    it 'omits the ON DELETE/ON UPDATE clauses when they are not supplied' do
      minimal_fk = {name: 'fk_x', column: 'locality_id', to_table: 'localities', primary_key: 'id'}

      described_class.rebuild('widgets', connection: connection, epoch: 5, foreign_keys: [minimal_fk]) do |staging_table|
        connection.execute("-- populate #{staging_table}")
      end

      alter_statement = connection.log.find { |sql| sql.start_with?('ALTER TABLE') }
      expect(alter_statement).to eq(
        'ALTER TABLE `widgets` ADD CONSTRAINT `fk_x` FOREIGN KEY (`locality_id`) REFERENCES `localities` (`id`)'
      )
    end

    it 'is not emitted at all in a dry run' do
      described_class.rebuild('widgets', connection: connection, dry_run: true, epoch: 6, foreign_keys: [foreign_key]) do |staging_table|
        connection.execute("-- populate #{staging_table}")
      end

      expect(connection.log.any? { |sql| sql.start_with?('ALTER TABLE') }).to be false
    end
  end

  it 'raises before doing anything when the connection reports an open transaction' do
    connection.open_transactions = 1

    expect do
      described_class.rebuild('widgets', connection: connection) { |_staging_table| raise 'should never run' }
    end.to raise_error(/must not be called inside a transaction/)

    expect(connection.log).to be_empty
  end

  it 'raises ArgumentError when the derived staging/backup name would exceed 64 characters' do
    long_table_name = 'a' * 60 # + "_swap_1" / "_swapold_1" pushes both derived names over 64

    expect do
      described_class.rebuild(long_table_name, connection: connection, epoch: 1) { |_staging_table| }
    end.to raise_error(ArgumentError, /exceeds MySQL's 64 character identifier limit/)

    expect(connection.log).to be_empty
  end

  it 'raises a clear error when no connection is given and ActiveRecord is not loaded' do
    expect(defined?(ActiveRecord)).to be_falsey

    expect do
      described_class.rebuild('widgets') { |_staging_table| }
    end.to raise_error(/ActiveRecord is not loaded.*pass connection: explicitly/)
  end

end
