module Wilbertils
  class EncryptDecrypt

    KEY = 'AF0G8o*EBZb0%Ue4#2lDK3SIipx7f1F48L12^yrZGYF#%biU82W!I#jW&!*m0@80M6HXg4pxVq5014FPT@6&x^h02074LG4hW7Qy'

    class << self

      def encrypt plain_value
        cipher = OpenSSL::Cipher.new('DES-EDE3-CBC').encrypt
        cipher.key = Digest::SHA1.hexdigest KEY
        s = cipher.update(plain_value) + cipher.final

        s.unpack('H*')[0].upcase
      end

      def decrypt encoded_value
        cipher = OpenSSL::Cipher.new('DES-EDE3-CBC').decrypt
        cipher.key = Digest::SHA1.hexdigest KEY
        s = [encoded_value].pack("H*").unpack("C*").pack("c*")

        cipher.update(s) + cipher.final
      end

    end

  end
end


