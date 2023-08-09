require 'spec_helper_lite'
require 'wilbertils'

describe Wilbertils::Redis::MessageReceiver do

  let(:message_processor) { double('message_processor').as_null_object }
  let(:message_translator) { double('message_translator').as_null_object }
  let(:config) { double('config').as_null_object }

  let(:message) { double('message') }
  let(:logger) { double.as_null_object }
  let(:redis_client) {  double('redis') }
  let(:processing_queue_object) { double('processing_queue') }
  let(:queue_object) { FakeClient.new(message) }

  # the real class (Wilbertils::Redis::Queue) uses redis but I've stubbed it to use a fake client since we don't need to test redis commands, just need to test the work once it receives a msg
  class FakeClient

    def initialize message
      @message = message
    end

    def process(blocking, wait_timeout)
      yield @message if block_given?
    end

  end

  subject { described_class.new('queue_name', message_processor, message_translator, config, logger, TestShutdown.new(1)) }

  before do
    allow(Wilbertils::Redis::Queue).to receive(:queue).and_return(queue_object)
    allow_any_instance_of(described_class).to receive(:client).with(config).and_return(redis_client)
    allow(Wilbertils::Redis::ProcessingQueues).to receive(:new).and_return(processing_queue_object)
  end

  describe 'when a message is received' do
    let(:message) { double('message', nil?: false, empty?: false) }

    it 'translates the message using the specified message translator' do
      expect(message_translator).to receive(:new).with(message).and_return instance=double
      expect(instance).to receive(:translate)
      expect(processing_queue_object).to receive(:monitor).with('queue_name')
      subject.poll
    end

    it 'processes the message using the specified message processor' do
      allow(message_translator).to receive(:translate).and_return params=double
      expect(message_processor). to receive(:new).with(params).and_return(instance=double('instance'))
      expect(instance).to receive(:execute)
      expect(processing_queue_object).to receive(:monitor).with('queue_name')
      subject.poll
    end

    fdescribe 'when a message with an empty body is encountered' do
      let(:message) { double('message', nil?: false, empty?: true) }
      it 'logs an error but not raise an exception' do
        expect(logger).to receive(:info).with('message is empty!')
        expect(message_translator).to_not receive(:new) # execution should short-circuit
        expect(processing_queue_object).to receive(:monitor).with('queue_name')
        expect{ subject.poll }.to_not raise_error
      end
    end

    describe 'when a message with a nil body is encountered' do
      let(:message) { double('message', nil?: true, empty?: false) }
      it 'logs an error but not raise an exception' do
        expect(logger).to receive(:info).with('message is nil!')
        expect(message_translator).to_not receive(:new) # execution should short-circuit
        expect(processing_queue_object).to receive(:monitor).with('queue_name')
        expect{ subject.poll }.to_not raise_error
      end
    end

    describe 'when the extract process fails' do
      before do
        allow(message_processor).to receive(:execute).and_raise()
      end

      subject { described_class.new('queue_name', message_processor, message_translator, config, logger, TestShutdown.new(2) ) }

      it 'continues to poll' do
        expect(message_processor).to receive(:new).twice()
        expect(processing_queue_object).to receive(:monitor).with('queue_name').twice()
        subject.poll
      end
    end

    class TestShutdown

      def initialize times
        @times = times
        @runs = 0
      end

      def now?
        @runs += 1
        @runs > @times
      end

    end

  end
end
