module DuctExtension
  module Tool
    # Small shared parser/formatter for SketchUp input boxes.
    # Keeping this here prevents each tool/prompt from growing its own slightly
    # different number and Yes/No handling.
    module InputHelpers
      module_function

      def positive_number(value, fallback = nil)
        Model::DuctDimensions.positive_number(value, fallback)
      rescue
        fallback
      end

      def yes?(value, default: true)
        text = value.to_s.strip.downcase
        return true if %w[yes y true 1].include?(text)
        return false if %w[no n false 0].include?(text)

        default
      rescue
        default
      end

      def format_number(value, precision: 3)
        number = value.to_f
        rounded = number.round(precision)
        return rounded.round.to_s if (rounded - rounded.round).abs < (10.0**-precision)

        rounded.to_s
      rescue
        value.to_s
      end
    end
  end
end
