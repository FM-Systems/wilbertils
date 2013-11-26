module Wilbertils
  class MessageReceiverStack
    include Singleton

    def self.add receiver
      self.instance.add receiver
    end

    def self.shutdown
      self.instance.shutdown
    end

    def initialize
      @message_receivers = []
    end

    def add receiver
      @message_receivers << receiver
    end

    def shutdown
      @message_receivers.each { |mr| mr.shutdown }
    end
  end
end


