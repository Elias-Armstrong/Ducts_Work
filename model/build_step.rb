module DuctExtension
  module Model
    class BuildStep
      attr_reader :type
      attr_reader :params

      def initialize(type, params = {})
        @type = type.to_sym
        @params = params || {}
      end

      def [](key)
        @params[key]
      end

      def fetch(key, fallback = nil)
        @params.fetch(key, fallback)
      end

      def merge(extra_params)
        self.class.new(@type, @params.merge(extra_params || {}))
      end
    end
  end
end
