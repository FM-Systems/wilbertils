require 'spec_helper_lite'
require 'wilbertils/table_swap'

# nulldb (see spec_helper_lite) quotes identifiers with single quotes; production
# is MySQL and uses backticks. Every SQL string below reflects nulldb's quoting.
describe Wilbertils::TableSwap do

  let(:connection) { ActiveRecord::Base.connection }

  def log
    connection.execution_log_since_checkpoint.map(&:content)
  end

  before do
    NullDB.checkpoint
  end

  it 'emits create, then yields, then renames, then drops the backup - in that order' do
    described_class.rebuild('widgets', connection: connection, epoch: 1) do |staging_table|
      expect(staging_table).to eq('widgets_swap_1')
      connection.execute("-- populate #{staging_table}")
    end

    expect(log).to eq([
      "CREATE TABLE 'widgets_swap_1' LIKE 'widgets'",
      '-- populate widgets_swap_1',
      "RENAME TABLE 'widgets' TO 'widgets_swapold_1', 'widgets_swap_1' TO 'widgets'",
      "DROP TABLE 'widgets_swapold_1'",
      "SELECT COUNT(*) FROM 'widgets'",
      "DROP TABLE IF EXISTS 'widgets_swap_1'"
    ])
  end

  it 'in a dry run creates, yields, and drops the staging table - with no rename' do
    # nulldb's select_value returns nil. Constrained to the staging table: a
    # stubbed call is never logged, so the log can't show which table was counted.
    allow(connection).to receive(:select_value)
      .with("SELECT COUNT(*) FROM 'widgets_swap_2'").and_return(3)

    count = described_class.rebuild('widgets', connection: connection, dry_run: true, epoch: 2) do |staging_table|
      connection.execute("-- populate #{staging_table}")
    end

    expect(log).to eq([
      "CREATE TABLE 'widgets_swap_2' LIKE 'widgets'",
      '-- populate widgets_swap_2',
      "DROP TABLE IF EXISTS 'widgets_swap_2'"
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

    expect(log).to eq([
      "CREATE TABLE 'widgets_swap_3' LIKE 'widgets'",
      '-- populate widgets_swap_3',
      "DROP TABLE IF EXISTS 'widgets_swap_3'"
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

      statements = log
      rename_index      = statements.index { |sql| sql.start_with?('RENAME TABLE') }
      drop_backup_index = statements.index("DROP TABLE 'widgets_swapold_4'")
      alter_index        = statements.index { |sql| sql.start_with?('ALTER TABLE') }

      expect(rename_index).not_to be_nil
      expect(drop_backup_index).not_to be_nil
      expect(alter_index).not_to be_nil
      expect(alter_index).to be > rename_index
      expect(alter_index).to be > drop_backup_index

      expect(statements[alter_index]).to eq(
        "ALTER TABLE 'widgets' ADD CONSTRAINT 'fk_rails_4bb88e9095' FOREIGN KEY ('locality_id') " \
        "REFERENCES 'localities' ('id') ON DELETE RESTRICT ON UPDATE RESTRICT"
      )
    end

    it 'omits the ON DELETE/ON UPDATE clauses when they are not supplied' do
      minimal_fk = {name: 'fk_x', column: 'locality_id', to_table: 'localities', primary_key: 'id'}

      described_class.rebuild('widgets', connection: connection, epoch: 5, foreign_keys: [minimal_fk]) do |staging_table|
        connection.execute("-- populate #{staging_table}")
      end

      alter_statement = log.find { |sql| sql.start_with?('ALTER TABLE') }
      expect(alter_statement).to eq(
        "ALTER TABLE 'widgets' ADD CONSTRAINT 'fk_x' FOREIGN KEY ('locality_id') REFERENCES 'localities' ('id')"
      )
    end

    it 'is not emitted at all in a dry run' do
      described_class.rebuild('widgets', connection: connection, dry_run: true, epoch: 6, foreign_keys: [foreign_key]) do |staging_table|
        connection.execute("-- populate #{staging_table}")
      end

      expect(log.any? { |sql| sql.start_with?('ALTER TABLE') }).to be false
    end
  end

  it 'raises before doing anything when the connection reports an open transaction' do
    # nulldb has no writer for open_transactions, so stub the reader.
    allow(connection).to receive(:open_transactions).and_return(1)

    expect do
      described_class.rebuild('widgets', connection: connection) { |_staging_table| raise 'should never run' }
    end.to raise_error(/must not be called inside a transaction/)

    expect(log).to be_empty
  end

  it 'raises ArgumentError when the derived staging/backup name would exceed 64 characters' do
    long_table_name = 'a' * 60 # "_swap_1" / "_swapold_1" push both over 64

    expect do
      described_class.rebuild(long_table_name, connection: connection, epoch: 1) { |_staging_table| }
    end.to raise_error(ArgumentError, /exceeds MySQL's 64 character identifier limit/)

    expect(log).to be_empty
  end

  it 'raises a clear error when no connection is given and ActiveRecord is not loaded' do
    hide_const('ActiveRecord')
    expect(defined?(ActiveRecord)).to be_falsey

    expect do
      described_class.rebuild('widgets') { |_staging_table| }
    end.to raise_error(/ActiveRecord is not loaded.*pass connection: explicitly/)
  end

end
