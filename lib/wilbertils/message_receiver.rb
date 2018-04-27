require 'wilbertils/sqs'
require 'wilbertils/exception_handler'

module Wilbertils
  class MessageReceiver

    include Wilbertils::ExceptionHandler

    attr_reader :logger

    def initialize queue_name, message_processor_class, message_translator_class, config, logger, shutdown = Shutdown.new
      @message_translator_class = message_translator_class
      @message_processor_class = message_processor_class
      @client = Wilbertils::SQS.client(config)
      @queue_url = queue_name
      @shutdown = shutdown
      @logger = logger
      raise unless @client
    end

    def shutdown
      logger.info "Shutting down message receiver..."
      @shutdown_now = true
    end

    def poll
      until do_i_shutdown? do
        @client.receive_message(queue_url: @queue_url, wait_time_seconds: 20, visibility_timeout: 60).messages.each do |msg|
          if bad_message? msg
            @client.delete_message(queue_url: @queue_url, receipt_handle: msg.receipt_handle)
            next
          end
          logger.info "received a message with id: #{msg.message_id}"
          METRICS.increment "message-received-#{@message_processor_class}" if defined?(METRICS)
          begin
            params = @message_translator_class.new(msg).translate
            @message_processor_class.new(params).execute
            @client.delete_message(queue_url: @queue_url, receipt_handle: msg.receipt_handle)
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
      (logger.error "message has nil id!";     return true) unless msg.message_id
      (logger.error "message has empty id!";   return true) if msg.message_id.empty?
      (logger.error "message has nil body!";   return true) unless msg.body
      (logger.error "message has empty body!"; return true) if msg.body.empty?
      false
    end

  end


end
