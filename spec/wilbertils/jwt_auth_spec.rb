require 'spec_helper_lite'
require 'wilbertils'

describe Wilbertils::Authorization::JwtAuth do
  let(:secret) { 'signing-secret' }
  let(:access_key) { Base64.encode64(secret) }
  let(:headers) { { 'dd-ver' => 'DD-JWT-V1' } }
  let(:logger) { double('logger', error: nil) }

  subject(:jwt_auth) { described_class.new(access_key, 'HS256', headers, 'doordash', 300, 'developer-id', 'key-id', {}) }

  before { allow(Wilbertils::Logging).to receive(:logger).and_return(logger) }

  describe '#access_token' do
    it 'signs an HS256 token carrying the claims and headers' do
      allow(DateTime).to receive(:now).and_return(DateTime.new(2026,1,1))

      payload, header = JWT.decode(jwt_auth.access_token, secret, true, algorithm: 'HS256', verify_expiration: false)

      expect(payload).to include('aud' => 'doordash', 'iss' => 'developer-id', 'kid' => 'key-id')
      expect(payload['exp'] - payload['iat']).to eq(300)
      expect(header).to include('alg' => 'HS256', 'dd-ver' => 'DD-JWT-V1')
    end

    context 'with an empty access key' do
      let(:access_key) { '' }

      it 'does not sign a token' do
        expect(jwt_auth.access_token).not_to be_a(String)
        expect(logger).to have_received(:error).with('HMAC key cannot be empty')
      end
    end
  end
end
