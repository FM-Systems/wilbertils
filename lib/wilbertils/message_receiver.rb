require 'wilbertils/sqs'
require 'wilbertils/exception_handler'

module Wilbertils
  class MessageReceiver

    include Wilbertils::ExceptionHandler

    attr_reader :logger

    def initialize queue_name, message_processor_class, message_translator_class, config, logger, shutdown = Shutdown.new
      @message_translator_class = message_translator_class
      @message_processor_class = message_processor_class
      @queue = Wilbertils::SQS.queues(config)[queue_name]
      @shutdown = shutdown
      @logger = logger
      raise unless @queue.exists?
    end

    def shutdown
      logger.info "Shutting down message receiver..."
      @shutdown_now = true
    end

    def poll
      until do_i_shutdown? do
        @queue.poll(:poll_interval => 60, :idle_timeout => 120) do |msg|
          logger.info "received a message with id: #{msg.id}"
          METRICS.increment "message-received-#{@message_processor_class}" if defined?(METRICS)
          begin
            params = @message_translator_class.new(msg).translate
            @message_processor_class.new(params).execute
          rescue => e
            logger.error "Error: Failed to process message using #{@message_processor_class}. Reason given: #{e.message}"
            rescue_with_handler e
            METRICS.increment "message-error-#{@message_processor_class}" if defined?(METRICS)
          end
        end
      end
      logger.info "Shut down message receiver"
    end

    def do_i_shutdown?
      @shutdown.now? { @shutdown_now }
    end

    class Shutdown
      def now?
        yield
      end
    end

  end


end
