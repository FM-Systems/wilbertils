require 'spec_helper_lite'
require 'wilbertils'

describe Wilbertils::MessageReceiver do

  let(:queues) { double('queues') }
  let(:message_queue) { double('message_queue').as_null_object }
  let(:message_processor) { double('message_processor').as_null_object }
  let(:message_translator) { double('message_translator').as_null_object }
  let(:config) { double('config').as_null_object }

  let(:message) { double('message', :id => '123') }
  let(:logger) { mock.as_null_object }

  class FakeQueue

    attr_reader :message

    def initialize message
      @message = message
    end

    def poll(hash)
      yield message
    end

    def exists?
      true
    end

  end

  subject { Wilbertils::MessageReceiver.new('queue_name', message_processor, message_translator, config, logger, TestShutdown.new(1)) }

  before do
    Wilbertils::SQS.should_receive(:queues).and_return(queues)
    queue = FakeQueue.new(message)
    queues.stub(:[]).and_return(queue)
  end

  describe 'when a message is received' do
    let(:message) { double('message', :id => '123') }

    before do
      message_queue.stub(:poll).and_yield(message)
    end

    it 'should translate the message using the specified message translator' do
      message_translator.should_receive(:new).with(message).and_return instance=double
      instance.should_receive(:translate)
      subject.poll
    end

    it 'should process the message using the specified message processor' do
      message_translator.stub(:translate).and_return params=double
      message_processor.should_receive(:new).with(params).and_return(instance=double('instance'))
      instance.should_receive(:execute)
      subject.poll
    end

    describe 'when the extract process fails' do
      before do
        message_processor.stub(:execute).and_raise()
      end

      subject { Wilbertils::MessageReceiver.new('queue_name', message_processor, message_translator, config, logger, TestShutdown.new(2) ) }

      it 'should continue to poll' do
        message_processor.should_receive(:new).twice()
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
