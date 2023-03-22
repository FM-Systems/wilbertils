module Wilbertils
  class Logging
    class << self
      def logger(config)
        @logger ||= if config.environment == 'development'
          l = ActiveSupport::Logger.new("log/#{config.environment}.log")
          l.formatter = proc { |sev, date, _, msg| "#{date.strftime('%Y-%m-%d %H:%M:%S')} #{sev}: #{msg}\n" }
          l
        else
          # This logger is just a wrapper around Logger that sets a NewRelic JSON decorator
          NewRelic::Agent::Logging::DecoratingLogger.new("log/#{config.environment}.log")
        end
      end
    end
  end
end