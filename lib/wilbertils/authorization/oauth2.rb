require 'wilbertils/exception_handler'

module Wilbertils::Authorization
  class Oauth2
    class << self

      def access_token params
        @@params = params.deep_symbolize_keys
        fetch_access_token
      end

      private

      def fetch_access_token
        begin
          token = retreive_access_token_from_redis
          token = refresh_token(token) if expired?(token)
          return token[token_name] if token
          request_access_token
        rescue => e
          logger.error e.message
          logger.error e.backtrace
        end
      end

      def request_access_token
        begin
          response = JSON.parse(RestClient.post(token_url, token_request_body, token_request_headers), symbolize_names: true)
          store_token(response)
          response[token_name]
        rescue => e
          logger.error "Failed to get access token for #{@@params[:token_for]}; #{e.message}"
          logger.error e.backtrace
          raise
        end
      end

      def token_request_body        
        @@params[:token_request_body] || { :grant_type => grant_type }.merge(body)
      end

      def token_request_headers
        case @@params[:grant_type].to_sym
        when :client_credentials
          { Authorization: "Basic #{Base64.strict_encode64("#{@@params[:body][:client_id]}:#{@@params[:body][:client_secret]}")}" }
        else 
          {}
        end.merge(@@params[:headers] || {})
      end

      def grant_type
        @@params[:grant_type].to_sym == :client_credentials_body ? :client_credentials : @@params[:grant_type]
      end

      def body
        case @@params[:grant_type].to_sym
        when :password, :client_credentials_body
          @@params[:body]
        else
          {}
        end
      end

      def token_name
        @@params[:token_name]&.to_sym || :access_token
      end

      # need to send '' as token_path for nz couriers because the auth url and data url are different so can't send the url and add /token at end
      def token_url
        @@params[:url] + (@@params[:token_path] || '/token')
      end

      def refresh_token token
        return unless token[:refresh_token]
        begin
          response = JSON.parse(RestClient.post(token_url, 
            {
              :grant_type => :refresh_token,
              :refresh_token => token[:refresh_token]
            }.merge(body)
           ), symbolize_names: true)
          store_token(response)
          response
        rescue => e
          logger.info "requesting new access token"
          logger.info e.backtrace
          request_access_token
        end
      end

      def token_key
        "token:#{@@params[:token_for]}:#{@@params[:body][:client_id]}"
      end

      def store_token response
        redis.set(token_key, response.merge(created_at: Time.now).to_json)
      end

      def retreive_access_token_from_redis
        token = redis.get(token_key)
        JSON.parse(token, symbolize_names: true) if token
      end

      def expired? token
        # default of 1 hr set, sometimes medipt send back nil and need to handle it
        !!token && ( ( Time.now.to_i - Time.parse(token[:created_at]).to_i ) > ( token[:expires_in] || 3600 ) )
      end

      def redis
        Wilbertils::Redis::Redis.client(@@params[:config])
      end

      def logger
        @@params[:logger]
      end

    end
  end
end
