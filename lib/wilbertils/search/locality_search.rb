module Wilbertils; module Search
  module LocalitySearch

    module ClassMethods
      def match(locality_name, postcode, threshold=2, locality_search = Wilbertils::Search::LocalitySearcher.new)
        throw StandardError.new("postcode or locality not valid #{postcode} or #{locality_name}") unless postcode=~/^\d{4}$/ && locality_name.length > 0
        locality = Locality.find_by_postcode_and_locality(postcode, locality_name)
        return locality unless locality.nil?
        search = locality_search.match_closest_location(locality_name, postcode)
        if (search.max_score < threshold)
          search = locality_search.match_closest_location(locality_search.find_best_word(locality_name), postcode)
        end
        Locality.find(search[id]) unless search.max_score < threshold || search['id'].nil?
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
