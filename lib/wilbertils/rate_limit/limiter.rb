module Wilbertils::RateLimit
  module Limiter

    def limiter
      RedisTokenBucket.limiter($redis)
    end

    # bucket_name -> which carrier or the customer the rate limit bucket is for
    def token_available? bucket
      limiter.read_level(bucket) > 0
    end

    def get_token bucket, count: 1
      limiter.charge(bucket, count)
    end

  end
end
