require 'active_support/concern'
require 'active_support/rescuable'

module Wilbertils
  module ExceptionHandler
    extend ActiveSupport::Concern
    include ActiveSupport::Rescuable

    included do
      rescue_from Exception, :with => :rescue_exception
    end

    def rescue_exception(exception)
      return if ENV['ENVIRONMENT_NAME'] == 'ci'

      logger.error "ExceptionHandler : #{exception.class }#{exception.inspect}"
      logger.error "#{exception.backtrace.join("\n")}"

      return if !ENV['ENVIRONMENT_NAME']

      Airbrake.notify(
        exception,
        :cgi_data => ENV.to_hash
      )
    end

  end
end

