require 'spec_helper_lite'
require 'wilbertils'

describe Wilbertils::MessageReceiverNew do

  let(:message_processor) { double('message_processor').as_null_object }
  let(:message_translator) { double('message_translator').as_null_object }
  let(:config) { double('config').as_null_object }

  let(:message) { double('message', :message_id => '123') }
  let(:logger) { double.as_null_object }
  let(:sqs_client) { FakeClient.new(message) }

  class FakeMessages
    def initialize message
      @message = message
    end
    def messages
      [@message]
    end
  end

  class FakeClient

    def initialize message
      @message = message
    end

    def receive_message(hash)
      FakeMessages.new(@message)
    end

  end

  subject { Wilbertils::MessageReceiverNew.new('queue_name', message_processor, message_translator, config, logger, TestShutdown.new(1)) }

  before do
    expect(Wilbertils::SQS).to receive(:client).and_return(sqs_client)
  end

  describe 'when a message is received' do
    let(:message) { double('message', :message_id => '123', :body => 'somebody', :receipt_handle => 'xyz') }

    it 'translates the message using the specified message translator' do
      expect(message_translator).to receive(:new).with(message).and_return instance=double
      expect(instance).to receive(:translate)
      expect(sqs_client).to receive(:delete_message).with(queue_url: 'queue_name', receipt_handle: 'xyz')
      subject.poll
    end

    it 'processes the message using the specified message processor' do
      allow(message_translator).to receive(:translate).and_return params=double
      expect(message_processor). to receive(:new).with(params).and_return(instance=double('instance'))
      expect(instance).to receive(:execute).and_return(true)
      expect(sqs_client).to receive(:delete_message).with(queue_url: 'queue_name', receipt_handle: 'xyz')
      subject.poll
    end
    
    it 'does not delete the message if message processor returns false' do
      allow(message_translator).to receive(:translate).and_return params=double
      expect(message_processor). to receive(:new).with(params).and_return(instance=double('instance'))
      expect(instance).to receive(:execute).and_return(false)
      expect(sqs_client).not_to receive(:delete_message)
      subject.poll
    end

    describe 'when a message without an id is encountered' do
      let(:message) { double('message', :message_id => '', :receipt_handle => 'xyz') }
      it 'logs an error but not raise an exception' do
        expect(logger).to receive(:error).with /empty id/
        expect(message_translator).to_not receive(:new) # execution should short-circuit
        expect(sqs_client).to receive(:delete_message).with(queue_url: 'queue_name', receipt_handle: 'xyz')
        expect{ subject.poll }.to_not raise_error
      end
    end

    describe 'when a message without a nil id is encountered' do
      let(:message) { double('message', :message_id => nil, :receipt_handle => 'xyz') } # not sure this can actually happen
      it 'logs an error but not raise an exception' do
        expect(logger).to receive(:error).with /nil id/
        expect(message_translator).to_not receive(:new) # execution should short-circuit
        expect(sqs_client).to receive(:delete_message).with(queue_url: 'queue_name', receipt_handle: 'xyz')
        expect{ subject.poll }.to_not raise_error
      end
    end

    describe 'when a message with an empty body is encountered' do
      let(:message) { double('message', :message_id => '123', :body => '', :receipt_handle => 'xyz') }
      it 'logs an error but not raise an exception' do
        expect(logger).to receive(:error).with /empty body/
        expect(message_translator).to_not receive(:new) # execution should short-circuit
        expect(sqs_client).to receive(:delete_message).with(queue_url: 'queue_name', receipt_handle: 'xyz')
        expect{ subject.poll }.to_not raise_error
      end
    end

    describe 'when a message with a nil body is encountered' do
      let(:message) { double('message', :message_id => '123', :body => nil, :receipt_handle => 'xyz') } # not sure this can actually happen
      it 'logs an error but not raise an exception' do
        expect(logger).to receive(:error).with /nil body/
        expect(message_translator).to_not receive(:new) # execution should short-circuit
        expect(sqs_client).to receive(:delete_message).with(queue_url: 'queue_name', receipt_handle: 'xyz')
        expect{ subject.poll }.to_not raise_error
      end
    end

    describe 'when the extract process fails' do
      before do
        allow(message_processor).to receive(:execute).and_raise()
      end

      subject { Wilbertils::MessageReceiverNew.new('queue_name', message_processor, message_translator, config, logger, TestShutdown.new(2) ) }

      it 'continues to poll' do
        expect(message_processor).to receive(:new).twice()
        expect(sqs_client).to receive(:delete_message).with(queue_url: 'queue_name', receipt_handle: 'xyz').twice()
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
