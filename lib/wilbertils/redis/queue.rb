require 'redis-queue'

module Wilbertils; module Redis
  module Queue
    extend self
    extend Wilbertils::Redis::Redis
    
    @queues = {}

    def queue config, queue_name
      redis = client config # establish connection to redis server
      get_queue(queue_name, redis)
    end
    
    def send_message config, queue_name, message
      redis = client config # establish connection to redis server
      get_queue(queue_name, redis).push(message_body(message, queue_name))
    end
    
    private
    
    def message_body message, queue_name
      json_message = JSON.parse(message, symbolize_names: true)
      json_message.merge!(queue_name: queue_name, message_first_received_time: Time.now).to_json
    end
    
    def get_queue queue_name, redis
      @queues[queue_name] = @queues[queue_name].nil? ? ::Redis::Queue.new(queue_name, "#{queue_name}_processing", :redis => redis) : @queues[queue_name]
    end

  end
end; end