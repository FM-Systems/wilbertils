require 'wilbertils/exception_handler'
require 'jwt'

module Wilbertils::Authorization
  class JwtAuth

    def initialize access_key, algorithm, headers, token_name, expiry=300, developer_id, key_id, config
      @access_key = Base64.decode64 access_key
      @algorithm = algorithm
      @headers = headers
      @token_name = token_name
      @expiry = expiry
      @developer_id = developer_id
      @key_id = key_id
      @config = config
    end

    def access_token
      fetch_jwt_token
    end

    private
    
    attr :access_key, :algorithm, :headers, :token_name, :expiry, :developer_id, :key_id, :config

    def fetch_jwt_token
      begin
        JWT.encode(data, access_key, algorithm, headers)
      rescue => e
        logger.error e.message
        logger.error e.backtrace
      end
    end

    def data
      {
        aud: token_name,
        iss: developer_id,
        kid: key_id,
        exp: ((DateTime.now.to_i) + expiry).floor,
        iat: (DateTime.now.to_i).floor,
      }
    end

    def logger
      Wilbertils::Logging.logger config
    end
    

  end
end
