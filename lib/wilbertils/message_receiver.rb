require 'wilbertils/sqs'

module Wilbertils
  class MessageReceiver

    @shutdown = false

    def initialize queue_name, message_processor_class, message_translator_class, config
      @message_translator_class= message_translator_class
      @message_processor_class= message_processor_class
      @queue= Wilbertils::SQS.queues(config)[queue_name]
      raise unless @queue.exists?
    end

    def shutdown
      logger.info "Shutting down message receiver..."
      @shutdown = true
    end

    def poll
      @queue.poll(:poll_interval => 60) do |msg|
        logger.info "received a message with id: #{msg.id}"
        METRICS.increment "message-received-#{@message_processor_class}" if defined?(METRICS)
        begin
          params = @message_translator_class.new(msg).translate
          @message_processor_class.new(params).execute
          break if @shutdown
        rescue => e
          logger.error "Error: Failed to process message using #{@message_processor_class}. Reason given: #{e.message}"
          logger.error e.backtrace
          METRICS.increment "message-error-#{@message_processor_class}" if defined?(METRICS)
        end
      end
    end

  end

end
