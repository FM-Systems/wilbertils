require 'spec_helper_lite'
require 'wilbertils'

describe Wilbertils::EncryptDecrypt do

  describe 'encrypt' do
    it 'should encrypt plain string' do
      expect(described_class.encrypt('CPBUBHZ0041906', 'AF0G8o*EBZb0%Ue4!2lDK3SIipx7f1F48L12^yrZGYF-%biU82W!I_jW&!*m0@80M6HXg4pxVq5014FPT@6&x^h02074LG4hW7Qy')).to eq('74DE7A0659985C03C5947AE904A5970E')
    end
  end

  describe 'decrypt' do
    it 'should decrypt encrypted string' do
      expect(described_class.decrypt('74DE7A0659985C03C5947AE904A5970E','AF0G8o*EBZb0%Ue4!2lDK3SIipx7f1F48L12^yrZGYF-%biU82W!I_jW&!*m0@80M6HXg4pxVq5014FPT@6&x^h02074LG4hW7Qy')).to eq('CPBUBHZ0041906')
    end
  end

end
