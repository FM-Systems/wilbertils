require 'logger'

module Wilbertils
  def logger
    if @logger.nil?
      $stdout.sync = true
      @logger = Logger.new($stdout)
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime} #{severity} #{msg}\n"
      end
    end
    @logger
  end
end

Object.send :include, Wilbertils
