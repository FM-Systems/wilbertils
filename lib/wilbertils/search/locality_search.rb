module Wilbertils; module Search
  module LocalitySearch

    module ClassMethods
      def match(params, threshold=10, locality_search = Wilbertils::Search::LocalitySearcher.new)

        # look for exact match first
        l = Locality.where(sublocality: params[:sublocality], locality: params[:locality], postcode: params[:postcode], region: params[:region], country: params[:country]).first
        return l if (l || !params[:fuzzy])

        unless params[:locality] && params[:locality].length > 0
          Rails.logger.info("locality not valid '#{params[:locality]}'")
          return nil
        end

        # for sublocality and locality, try transposing swap words before ES fuzzy search
        transposed_sublocality = locality_search.transpose_words(params[:sublocality])
        transposed_locality = locality_search.transpose_words(params[:locality])
        l = Locality.where(sublocality: [params[:sublocality], transposed_sublocality], locality: [params[:locality], transposed_locality], postcode: params[:postcode], region: params[:region], country: params[:country]).first
        return l if l

        search = locality_search.match_closest_location(params)
        result = search.results.first
        Locality.find(result[:id]) unless (search.response["hits"]["max_score"] < threshold || result[:id].nil?)
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

  end

  # warning: fuzzy matching has caused issues with wrong matches
  class LocalitySearcher

    def match_closest_location(params)
      Locality.search([params[:sublocality], params[:locality], params[:region]].join(" "), where:
                                {
                                    postcode: params[:postcode],
                                    country: params[:country].upcase
                                },
                      fields:   [:full_locality],
                      operator: "OR",
                      limit:    10,
                      order:    {_score: :desc},
                      load:     false)
    end

    SWAP_WORDS = %w(north east south west)

    def transpose_words(locality)
      return if locality.nil?

      words = locality.split(' ')
      return locality if words.length < 2
      SWAP_WORDS.include?(words[0].downcase) || SWAP_WORDS.include?(words[-1].downcase) ? transpose(words) : locality
    end

    def transpose(words)
      words[0], words[-1] = words[-1], words[0]
      words.join(' ')
    end

  end

end;end
