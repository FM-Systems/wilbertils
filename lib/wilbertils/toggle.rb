module Wilbertils
  class Toggle

    def self.on?
      !Rails.env.production?
    end

  end
end


