require 'spec_helper_lite'
require 'wilbertils'
require 'date'
require 'time'

describe Wilbertils::Redis::ProcessingQueues do

  let(:message_processor) { double('message_processor').as_null_object }
  let(:message_translator) { double('message_translator').as_null_object }
  let(:config) { double('config').as_null_object }
  let(:processing_queues) { ['despatch_processing'] }
  let(:stale_msgs) { [{message_first_received_time: Date.today.prev_day}.to_json] }
  let(:recent_msgs) { [{message_first_received_time: Time.now}.to_json] }

  let(:message) { double('message', :message_id => '123') }
  let(:logger) { double.as_null_object }
  let(:redis_client) {  double('redis') }

  subject { described_class.new(config) }

  before do
    allow_any_instance_of(described_class).to receive(:client).with(config).and_return(redis_client)
  end
  
  describe 'stale msgs' do
    it 'will be moved to regular queue from processing queue if they can be deleted' do
      allow(redis_client).to receive(:keys).and_return(processing_queues)
      allow(redis_client).to receive(:llen).with('despatch_processing').and_return(1)
      allow(redis_client).to receive(:lrange).with('despatch_processing', 0, -1).and_return(stale_msgs)
      allow(subject).to receive(:is_stale?).and_return(true)
      allow(redis_client).to receive(:lrem).and_return(1)
      expect(redis_client).to receive(:lpush)

      subject.monitor 'despatch_processing'
    end

    it 'will not move to regular queue from processing queue if they can\'t be deleted' do
      allow(redis_client).to receive(:keys).and_return(processing_queues)
      allow(redis_client).to receive(:llen).with('despatch_processing').and_return(1)
      allow(redis_client).to receive(:lrange).with('despatch_processing', 0, -1).and_return(stale_msgs)
      allow(subject).to receive(:is_stale?).and_return(true)
      allow(redis_client).to receive(:lrem).and_return(0)
      expect(redis_client).not_to receive(:lpush)

      subject.monitor 'despatch_processing'
    end
  end

  describe 'recent msgs' do
    it 'will be moved to regular queue from processing queue' do
      allow(redis_client).to receive(:keys).and_return(processing_queues)
      allow(redis_client).to receive(:llen).with('despatch_processing').and_return(1)
      allow(redis_client).to receive(:lrange).with('despatch_processing', 0, -1).and_return(recent_msgs)
      allow(subject).to receive(:is_stale?).and_return(false)
      expect(redis_client).not_to receive(:lrem)
      expect(redis_client).not_to receive(:lpush)

      subject.monitor 'despatch_processing'
    end

  end
end
