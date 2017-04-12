module Wilbertils; module Search
  module LocalitySearch

    module ClassMethods
      def match(params)
        case params[:country]
          when 'Australia'
            search_locality_postcode_region(params)
          when 'New Zealand'
            search_sublocality_locality_postcode(params)
          else
            search_locality_postcode_region(params)
        end
      end

      def search_locality_postcode_region(params, threshold=2, locality_search = Wilbertils::Search::LocalitySearcher.new)
        postcode = "%04d" % params[:postcode].to_i

        l = Locality.where(locality: params[:locality], postcode: postcode, region: params[:region], country: params[:country]).first
        return l if (l || params[:fuzzy] == false)

        unless postcode=~/^\d{4}$/ && params[:locality] && params[:locality].length > 0
          Rails.logger.info("postcode or locality not valid '#{params[:postcode]}' or '#{params[:locality]}'")
          return nil
        end

        search = locality_search.match_closest_location(params[:locality], postcode)
        if (search.max_score < threshold)
          search = locality_search.match_closest_location(locality_search.find_best_word(params[:locality]), postcode)
        end
        result = search.results.first
        Locality.find(result[:id]) unless search.max_score < threshold || result[:id].nil?
      end


      def search_sublocality_locality_postcode(params, threshold=2, locality_search = Wilbertils::Search::LocalitySearcher.new)
        postcode = "%04d" % params[:postcode].to_i

        l = Locality.where(sublocality: params[:sublocality], locality: params[:locality], postcode: postcode, country: params[:country]).first
        return l if (l || params[:fuzzy] == false)

        unless postcode=~/^\d{4}$/ && params[:locality] && params[:locality].length > 0
          Rails.logger.info("postcode or locality not valid '#{params[:postcode]}' or '#{params[:locality]}'")
          return nil
        end

        search = locality_search.match_closest_location(params[:locality], postcode)
        if (search.max_score < threshold)
          search = locality_search.match_closest_location(locality_search.find_best_word(params[:locality]), postcode)
        end
        result = search.results.first
        Locality.find(result[:id]) unless search.max_score < threshold || result[:id].nil?
      end

    end

    def self.included(base)
      base.extend(ClassMethods)
    end

  end

  class LocalitySearcher

    def initialize(stop_words =%w(mount sands flat beach brook west east north south island river saint))
      @stop_words = stop_words
    end

    def match_closest_location (locality, postcode)
      Locality.search do
        query { fuzzy :locality, locality.downcase }
        filter :term, { postcode: postcode}
      end
    end

    def find_best_word (locality)
      words = locality.split(' ')
      words.reject! { |w| @stop_words.include?(w) } unless words.length == 1
      words.max do |wordA, wordB|
        wordA.length <=> wordB.length
      end
    end

  end

end;end
