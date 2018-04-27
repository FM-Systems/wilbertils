require 'wilbertils/metrics'

describe Wilbertils::Metrics do

  subject { Wilbertils::Metrics }

  describe 'the factory' do

    let(:config) { double('config') }
    let(:metrics_enabled) { 'true' }
    let(:metrics_server) { 'metrics_server' }

    before do
      allow(config).to receive(:metrics_enabled) { metrics_enabled }
    end

    context 'when metrics are disabled' do
      let(:metrics_enabled) { 'false' }
      it 'returns a NullMetrics class' do
        expect(subject.factory('test', config)).to be_kind_of Wilbertils::Metrics::NullMetrics
      end
    end

    context 'when metrics are enabled' do

      before do
        allow(Resolv).to receive(:getaddress).and_return('1.1.1.1')
        expect(config).to receive(:metrics_server).and_return(metrics_server)
      end

      it 'resolves the statsd hostname as an ip address' do
        expect(Resolv).to receive(:getaddress).with(metrics_server).and_return('1.1.1.1')

        subject.factory('test', config)
      end

      it 'configures statsd with the correct host and port' do
        expect(Statsd).to receive(:new).with('1.1.1.1', 8125).and_return(double('statsd').as_null_object)

        subject.factory('test', config)
      end

      it 'configures statsd with the given namespace' do
        allow(Statsd).to receive(:new).and_return(statsd= double('statsd'))
        expect(statsd).to receive(:namespace=).with('test-namespace')

        subject.factory('test-namespace', config)
      end
    end

    context 'failed server address resolution' do
      before do
        allow(Resolv).to receive(:getaddress).and_raise
        expect(config).to receive(:metrics_server).twice().and_return(metrics_server)
      end
      it 'returns a NullMetrics class' do
        expect(subject.factory('test', config)).to be_kind_of Wilbertils::Metrics::NullMetrics
      end
    end

  end
end

