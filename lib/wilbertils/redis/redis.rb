module Wilbertils::Redis
  module Redis
    extend self
    
    def client config
      @redis ||= ::Redis.new(:url => "redis://#{config.redis_url}")
    end
    
  end
end