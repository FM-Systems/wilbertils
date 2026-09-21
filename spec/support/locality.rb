# Real AR model backed by spec/support/schema.rb. nulldb stores no data, so it
# can't replace the stubs - but stubbing on a real class means
# verify_partial_doubles actually checks the methods exist.
class Locality < ActiveRecord::Base
end
