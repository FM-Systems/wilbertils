require 'openssl'

module Wilbertils
  
  class EncryptDecrypt

    class << self

      def encrypt plain_value, key
        cipher = OpenSSL::Cipher.new('DES-EDE3-CBC').encrypt
        cipher.key = (Digest::SHA1.hexdigest key)[0..23]
        s = cipher.update(plain_value) + cipher.final

        s.unpack('H*')[0].upcase
      end

      def decrypt encoded_value, key
        cipher = OpenSSL::Cipher.new('DES-EDE3-CBC').decrypt
        cipher.key = (Digest::SHA1.hexdigest key)[0..23]
        s = [encoded_value].pack("H*").unpack("C*").pack("c*")

        cipher.update(s) + cipher.final
      end

    end

  end
end