module Wilbertils; module SQS
  extend self

  def client(config)
    @sqs ||= Aws::SQS::Client.new(region: config.aws_region)
  end
  
  def queue_poller(queue_url)
    @poller ||= Aws::SQS::QueuePoller.new(queue_url)
  end

end; end
