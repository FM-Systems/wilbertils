module Wilbertils
  class Logging
    class << self
      def logger(config = nil)
        @logger ||= if ENV["ENVIRONMENT_NAME"] == 'development'
          l = ActiveSupport::Logger.new("log/#{ENV["ENVIRONMENT_NAME"]}.log")
          l.formatter = proc { |sev, date, _, msg| "#{date.strftime('%Y-%m-%d %H:%M:%S')} #{sev}: #{msg}\n" }
          l
        else
          # This logger is just a wrapper around Logger that sets a NewRelic JSON decorator
          NewRelic::Agent::Logging::DecoratingLogger.new("log/#{ENV["ENVIRONMENT_NAME"]}.log")
        end
      end
    end
  end
end