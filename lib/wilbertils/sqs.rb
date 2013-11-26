module Wilbertils; module SQS
  extend self

  def queues config
    client.queues(config)
  end

  def client config
    @sqs ||= AWS::SQS.new(
      :access_key_id => config.aws_access_key_id,
      :secret_access_key => config.aws_secret_access_key,
      :sqs_endpoint => 'sqs.ap-southeast-2.amazonaws.com'
    )
  end

end; end
