require 'redis-queue'

module Wilbertils::Redis
  module Queue
    extend self
    include Wilbertils::Redis::Redis
    
    @queues = {}

    def queue config, queue_name
      client config # establish connection to redis server
      get_queue queue_name
    end
    
    def send_message config, queue_name, msg
      client config # establish connection to redis server
      get_queue(queue_name).push({ body: msg, meta_data: { received_time: Time.now, queue_name: queue_name } }.to_json)
    end
    
    private
    
    def get_queue queue_name
      @queues[queue_name] = @queues[queue_name].nil? ? Redis::Queue.new(queue_name, "#{queue_name}_processing",  :redis => @redis) : @queues[queue_name]
    end

  end
end