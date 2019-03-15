require 'redis-queue'

module Wilbertils::Redis
  class ProcessingQueues
    include Wilbertils::Redis::Redis
    
    def initialize config, prefix
      @redis = client config
      @prefix = prefix
    end
    
    def monitor
      # can use scan to get the list of queues if we start using readis like crazy and have keys in the range of hundreds of thousands
      @redis.keys("#{@prefix}_*_processing").each do |processing_queue|
        next if (@redis.llen processing_queue) == 0        
        @redis.lrange(processing_queue, 0, -1).each { |message| move_message_if_old message, processing_queue }        
      end
      
    end
    
    private
    
    def move_message_if_old message, processing_queue
      json_message = JSON.parse(message, symbolize_names: true)
      if Time.now - Time.parse(json_message[:meta_data][:received_time]) > 5.minutes
        @redis.lpush(json_message[:meta_data][:queue_name], message)
        @redis.lrem(processing_queue, 0, message)
      end
    end

  end
end