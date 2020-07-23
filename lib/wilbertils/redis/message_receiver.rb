require 'wilbertils/exception_handler'

module Wilbertils::Redis
  class MessageReceiver

    include Wilbertils::ExceptionHandler

    attr_reader :logger

    def initialize queue_name, message_processor_class, message_translator_class, config, logger, shutdown = Shutdown.new
      @message_translator_class = message_translator_class
      @message_processor_class = message_processor_class
      @queue = Wilbertils::Redis::Queue.queue(queue_name)
      @queue_name = queue_name
      @shutdown = shutdown
      @logger = logger
      @processing_queue = ProcessingQueues.new
    end

    def shutdown
      logger.info "Shutting down message receiver..."
      @shutdown_now = true
    end

    def poll
      until do_i_shutdown? do
        @processing_queue.monitor
        @queue.process(false, 20) do |msg|
          next if bad_message? msg
          begin
            message_body = @message_translator_class.new(msg).translate
            @message_processor_class.new(message_body).execute
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

    private

    def bad_message? msg
      (logger.error "message is nil!";   return true) if msg.nil?
      (logger.error "message is empty!"; return true) if msg.empty?
      false
    end

  end


end
