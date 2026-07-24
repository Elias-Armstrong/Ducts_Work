module DuctExtension
  module Model
    # Compatibility façade for older callers. New code should prefer
    # DuctDimensions directly so dimension normalization has one owner.
    module DimensionUtils
      def self.positive_number(value, fallback)
        DuctDimensions.positive_number(value, fallback)
      end

      def self.normalize_shape(value, default: :rectangular)
        DuctDimensions.normalize_shape(value, default: default)
      end

      def self.largest(dimensions)
        DuctDimensions.coerce(dimensions).largest
      rescue
        0.0
      end

      def self.max_dimensions(main_dimensions, branch_dimensions)
        main_dimensions = DuctDimensions.coerce(main_dimensions)
        branch_dimensions = DuctDimensions.coerce(branch_dimensions)

        if main_dimensions.rectangular? || branch_dimensions.rectangular?
          DuctDimensions.rectangular(
            width: [main_dimensions.width, branch_dimensions.width].max,
            height: [main_dimensions.height, branch_dimensions.height].max
          )
        else
          DuctDimensions.round(
            diameter: [main_dimensions.diameter, branch_dimensions.diameter].max
          )
        end
      end
    end
  end
end
