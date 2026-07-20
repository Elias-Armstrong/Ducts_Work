module DuctExtension
  module Model
    module DimensionUtils
      def self.positive_number(value, fallback)
        number = value.to_f
        number > 0.0 ? number : fallback.to_f
      rescue
        fallback.to_f
      end

      def self.normalize_shape(value, default: :rectangular)
        text = value.to_s.downcase.strip
        return :round if text == "round"
        return :rectangular if text == "rectangular"

        default
      rescue
        default
      end

      def self.largest(dimensions)
        return 0.0 unless dimensions

        [
          dimensions[:diameter].to_f,
          dimensions[:width].to_f,
          dimensions[:height].to_f
        ].max
      end

      def self.max_dimensions(main_dimensions, branch_dimensions)
        main_dimensions ||= {}
        branch_dimensions ||= {}

        if main_dimensions[:shape] == :rectangular || branch_dimensions[:shape] == :rectangular
          {
            shape: :rectangular,
            diameter: [main_dimensions[:diameter].to_f, branch_dimensions[:diameter].to_f].max,
            width: [main_dimensions[:width].to_f, branch_dimensions[:width].to_f].max,
            height: [main_dimensions[:height].to_f, branch_dimensions[:height].to_f].max
          }
        else
          diameter = [main_dimensions[:diameter].to_f, branch_dimensions[:diameter].to_f].max
          {
            shape: :round,
            diameter: diameter,
            width: diameter,
            height: diameter
          }
        end
      end
    end
  end
end
