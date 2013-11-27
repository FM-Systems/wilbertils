require 'spec_helper_lite'
require 'wilbertils'

describe Wilbertils::MessageReceiver do

  let(:queues) { double('queues') }
  let(:message_queue) { double('message_queue').as_null_object }
  let(:message_processor) { double('message_processor').as_null_object }
  let(:message_translator) { double('message_translator').as_null_object }
  let(:config) { double('config').as_null_object }

  subject { Wilbertils::MessageReceiver.new('queue_name', message_processor, message_translator, config) }

  before do
    Wilbertils::SQS.should_receive(:queues).and_return(queues)
    queues.stub(:[]).and_return(message_queue)
    Logger.should_receive(:new).any_number_of_times.and_return double(Logger).as_null_object
  end

  it 'should connect to the specified queue' do
    queues.should_receive(:[]).with('test_queue').and_return(message_queue)

    Wilbertils::MessageReceiver.new('test_queue', nil, nil, config)
  end

  it 'should fail when the queue does not exist' do
    message_queue.should_receive(:exists?).and_return(false)

    expect {subject}.to raise_error
  end

  it 'should poll indefinitely for a message' do
    message_queue.should_receive(:poll)

    subject.poll
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
        message_queue.should_receive(:poll).and_yield(message).and_yield(message)
        message_processor.stub(:execute).and_raise()
      end
      it 'should continue to poll' do
        message_processor.should_receive(:new).twice()
        subject.poll
      end
    end

  end
end
