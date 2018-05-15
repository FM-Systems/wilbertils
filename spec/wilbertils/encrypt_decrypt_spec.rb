require 'spec_helper_lite'
require 'wilbertils'

describe Wilbertils::EncryptDecrypt do

  describe 'encrypt' do
    it 'should encrypt plain string' do
      expect(described_class.encrypt('CPBUBHZ0041906')).to eq('A906765C7DE5CB15339A5E22666B2B41')
    end
  end

  describe 'decrypt' do
    it 'should decrypt encrypted string' do
      expect(described_class.decrypt('A906765C7DE5CB15339A5E22666B2B41')).to eq('CPBUBHZ0041906')
    end
  end

end
