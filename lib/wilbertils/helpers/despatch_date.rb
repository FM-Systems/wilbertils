class DespatchDate

  class << self

    def next_valid_despatching_day(country, region, date=nil)
      @country = ISO3166::Country.find_country_by_any_name(country).alpha2.downcase.to_sym
      @region  = "#{@country}_#{region}".downcase.to_sym
      @date    = date || Date.today

      @date += 1.day until date_valid?
      @date
    end

    def upcoming_valid_despatching_day(country, region, despatch_date, upcoming_days_count=1)
      @country = ISO3166::Country.find_country_by_any_name(country).alpha2.downcase.to_sym
      @region  = "#{@country}_#{region}".downcase.to_sym
      @date    = despatch_date || Date.today

      upcoming_days_count = 1 if upcoming_days_count < 1
      upcoming_days_count.times do
        @date += 1.day
        @date += 1.day until date_valid?
      end
      @date
    end

    private

    def date_valid?
      !in_past? && !@date.saturday? && !@date.sunday? && !holiday?
    end

    def in_past?
      if @date.respond_to?(:time_zone)
        @date.to_date < Time.use_zone(@date.time_zone.name) { Date.current }
      else
        @date < Date.today
      end
    end

    def holiday?
      @date.is_a?(Time) ? check_date(@date.to_date) : check_date(@date)
    end

    def check_date(date)
      date.holiday?([@country, @region], :observed)
    end

  end
end
