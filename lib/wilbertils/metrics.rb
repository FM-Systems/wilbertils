require 'resolv'
require 'statsd'
require 'rainman/config'

module Wilbertils; module Metrics
  extend self

  def self.factory (namespace, config)
    if config.metrics_enabled == 'true'
    begin
      statsd_host= Resolv.getaddress(config.metrics_server)
      Statsd.new(statsd_host, 8125).tap do |s|
        s.namespace= namespace
      end
    rescue => e
      puts "Error: Failed to connect to metrics server #{config.metrics_server}. Reason given: #{e.message}"
      NullMetrics.new
    end
    else
      NullMetrics.new
    end
  end

  class NullMetrics
    def method_missing(*args, &block)
      self
    end
  end
end; end
