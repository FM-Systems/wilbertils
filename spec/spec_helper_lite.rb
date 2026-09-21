#only need to require this when working with rspec fire

require 'active_record'
require 'nulldb_rspec'

SCHEMA_PATH = File.expand_path('support/schema.rb', __dir__)

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.before do
    ActiveRecord::Base.establish_connection(adapter: :nulldb, schema: SCHEMA_PATH)
    NullDB.nullify(schema: SCHEMA_PATH)
  end

  config.after do
    NullDB.restore
  end
end
