require 'redis-queue'

module Wilbertils; module Redis
  module Queue
    extend self
    
    @queues = {}

    def queue queue_name
      get_queue queue_name
    end
    
    def send_message queue_name, message
      get_queue(queue_name).push(message_body(message, queue_name))
    end
    
    private
    
    def message_body message, queue_name
      json_message = JSON.parse(message, symbolize_names: true)
      json_message.merge!(queue_name: queue_name, message_first_received_time: Time.now).to_json
    end
    
    def get_queue queue_name
      @queues[queue_name] = @queues[queue_name].nil? ? ::Redis::Queue.new(queue_name, "#{queue_name}_processing", :redis => $redis) : @queues[queue_name]
    end

  end
end; end