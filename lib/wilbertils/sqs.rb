module Wilbertils; module SQS
  extend self

  def client(config)
    @sqs ||= Aws::SQS::Client.new(region: config.aws_region)
  end

end; end
