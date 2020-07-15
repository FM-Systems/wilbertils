require 'redis-queue'

module Wilbertils; module Redis
  module Queue
    extend self
    extend Wilbertils::Redis::Redis
    
    @queues = {}

    def queue config, queue_name
      client config # establish connection to redis server
      get_queue queue_name
    end
    
    def send_message config, queue_name, message
      client config # establish connection to redis server
      get_queue(queue_name).push(message_body(message, queue_name))
    end
    
    private
    
    def message_body message, queue_name
      json_message = JSON.parse(message, symbolize_names: true)
      json_message.merge!(queue_name: queue_name).to_json
    end
    
    def get_queue queue_name
      @queues[queue_name] = @queues[queue_name].nil? ? ::Redis::Queue.new(queue_name, "#{queue_name}_processing") : @queues[queue_name]
    end

  end
end; end