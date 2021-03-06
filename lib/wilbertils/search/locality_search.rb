module Wilbertils; module Search
  module LocalitySearch

    module ClassMethods
      def match(params, threshold=2, locality_search = Wilbertils::Search::LocalitySearcher.new)

        # for sublocality and locality, try transposing swap words
        transposed_sublocality = locality_search.transpose_words(params[:sublocality])
        transposed_locality = locality_search.transpose_words(params[:locality])
        l = Locality.where(sublocality: [params[:sublocality], transposed_sublocality], locality: [params[:locality], transposed_locality], postcode: params[:postcode], region: params[:region], country: params[:country]).first
        return l if (l || !params[:fuzzy])

        unless params[:locality] && params[:locality].length > 0
          Rails.logger.info("locality not valid '#{params[:locality]}'")
          return nil
        end

        search = locality_search.match_closest_location(params)
        if (search.max_score < threshold)
          modified_params = params.dup
          modified_params[:sublocality] = locality_search.find_best_word(params[:sublocality])
          modified_params[:locality] = locality_search.find_best_word(params[:locality])
          search = locality_search.match_closest_location(modified_params)
        end
        result = search.results.first
        Locality.find(result[:id]) unless search.max_score < threshold || result[:id].nil?
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

  end

  # warning: fuzzy matching has caused issues with wrong matches
  class LocalitySearcher

    def initialize(stop_words =%w(mount sands flat beach brook west east north south island river saint))
      @stop_words = stop_words
    end

    # TODO: region and locality should boost score
    # fuzzy matching scoring is strange - eg. 'SWAN BA' does not match 'SWAN BAY' for any score, but 'SWAN B' gets close to 1.0
    # this is truncated by find_best_word which reduces 'SWAN xxx' to 'SWAN'
    # locality search against multiple fields (fuzzy_like_this) is a future option
    def match_closest_location(params)
      Locality.search do
        query {
          boolean {
            should { fuzzy :sublocality, params[:sublocality]&.downcase }
            should { fuzzy :locality, params[:locality]&.downcase }
          }
        }
        filter :term, { postcode: params[:postcode]&.downcase }
        filter :term, { country: params[:country]&.downcase }
      end
    end

    def find_best_word (locality)
      return if locality.nil?
      words = locality.split(' ')
      words.reject! { |w| @stop_words.include?(w) } unless words.length == 1
      words.max do |wordA, wordB|
        wordA.length <=> wordB.length
      end
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
