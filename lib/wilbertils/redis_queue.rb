require 'redis-queue'

module Wilbertils; module RedisQueue
  extend self

  @queues = {}

  def queue(config, queue_name)
    @redis ||= Redis.new(:url => "redis://#{config.redis_url}")
    res = get_queue queue_name
    puts "RQ: got #{res}"
    res
  end

 def get_queue queue_name

   puts "RQ: queue #{@queues}"
   puts "RQ: existing queue name <#{@queues[queue_name]}>"
   @queues[queue_name] = @queues[queue_name].nil? ? Redis::Queue.new(queue_name,"#{queue_name}_processing",  :redis => @redis) : @queues[queue_name]
 end

end; end
