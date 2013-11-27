require 'wilbertils/metrics'

describe Wilbertils::Metrics do

  subject { Wilbertils::Metrics }

  describe 'the factory' do

    let(:config) { double('config') }
    let(:metrics_enabled) { 'true' }
    let(:metrics_server) { 'metrics_server' }

    before do
      config.should_receive(:metrics_enabled).and_return(metrics_enabled)
    end

    context 'when metrics are disabled' do
      let(:metrics_enabled) { 'false' }
      it 'should return a NullMetrics class' do
        subject.factory('test', config).should be_kind_of Wilbertils::Metrics::NullMetrics
      end
    end

    context 'when metrics are enabled' do

      before do
        Resolv.stub(:getaddress).and_return('1.1.1.1')
        config.should_receive(:metrics_server).and_return(metrics_server)
      end

      it 'should resolve the statsd hostname as an ip address' do
        Resolv.should_receive(:getaddress).with(metrics_server).and_return('1.1.1.1')

        subject.factory('test', config)
      end

      it 'should configure statsd with the correct host and port' do
        Statsd.should_receive(:new).with('1.1.1.1', 8125).and_return(double('statsd').as_null_object)

        subject.factory('test', config)
      end

      it 'should configure statsd with the given namespace' do
        Statsd.stub(:new).and_return(statsd= double('statsd'))
        statsd.should_receive(:namespace=).with('test-namespace')

        subject.factory('test-namespace', config)
      end
    end

    context 'failed server address resolution' do
      before do
        Resolv.stub(:getaddress).and_raise
        config.should_receive(:metrics_server).twice().and_return(metrics_server)
      end
      it 'should return a NullMetrics class' do
        subject.factory('test', config).should be_kind_of Wilbertils::Metrics::NullMetrics
      end
    end

  end
end

