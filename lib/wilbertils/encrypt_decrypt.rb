require 'dotenv/load'
module Wilbertils
  class EncryptDecrypt

    KEY = ENV['URL_ENCRYPT_DECYRPT_KEY']

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


