require 'redis-queue'

module Wilbertils; module Redis
  module Queue
    extend self
    
    @queues = {}

    def queue queue_name
      get_queue queue_name
    end
    
    def send_message queue_name, msg
      get_queue(queue_name).push(msg)
    end
    
    private
    
    def get_queue queue_name
      @queues[queue_name] = @queues[queue_name].nil? ? ::Redis::Queue.new(queue_name, "#{queue_name}_processing") : @queues[queue_name]
    end

  end
end; end