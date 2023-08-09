require 'redis-queue'

module Wilbertils::Redis
  class ProcessingQueues
    
    attr_reader :redis

    include Wilbertils::Redis::Redis

    def initialize config
      @redis = client config
    end
    
    def monitor queue_name
      # can use scan to get the list of queues if we start using redis like crazy and have keys in the range of hundreds of thousands
      redis.keys("#{queue_name}_processing").each do |processing_queue|
        next if (redis.llen processing_queue) == 0
        redis.lrange(processing_queue, 0, -1).each { |message| move_message_if_old message, processing_queue }
      end
      
    end
    
    private
    
    def move_message_if_old message, processing_queue
      json_message = JSON.parse(message, symbolize_names: true)
      json_message[:message_retried_at] = json_message[:message_first_received_time] unless json_message[:message_retried_at]
      if is_stale?(json_message)
        json_message[:message_retried_at] = Time.now
        redis.lpush(json_message[:queue_name], json_message.to_json) if redis.lrem(processing_queue, 0, message) > 0
      end
    end

    def is_stale? json_message
      Time.now - Time.parse(json_message[:message_retried_at]) > 5.minutes
    end

  end
end