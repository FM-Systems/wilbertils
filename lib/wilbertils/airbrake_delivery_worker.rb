require 'sucker_punch'

module Wilbertils
  class AirbrakeDeliveryWorker
    include SuckerPunch::Job

    def perform(notice)
      Airbrake.sender.send_to_airbrake notice
    end
  end
end



