module Wilbertils; module Localities

  class ValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join('; '))
    end
  end

end; end
