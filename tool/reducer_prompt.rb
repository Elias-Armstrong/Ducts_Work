module DuctExtension
  module Tool
    # One prompt implementation for both DuctTool's End Reducer mode and the
    # standalone ReducerTool. The last-used values are shared intentionally.
    module ReducerPrompt
      @last_round_diameter = 10.0
      @last_rectangular_width = 16.0
      @last_rectangular_height = 10.0
      @last_length = 0.0

      class << self
        def prompt_for_port(port)
          dimensions = Model::Port.dimensions_from_params({}, port)
          dimensions[:shape] == :rectangular ? prompt_rectangular(dimensions) : prompt_round(dimensions)
        end

        private

        def prompt_round(dimensions)
          default_length = Geometry::ReducerBuilder.default_length(
            dimensions,
            { shape: :round, diameter: @last_round_diameter }
          )

          input = ::UI.inputbox(
            ["Current Diameter:", "New Diameter:", "Transition Length:"],
            [dimensions[:diameter].to_s, @last_round_diameter.to_s, length_default(default_length)],
            [],
            "Round Increaser / Reducer"
          )
          return nil unless input

          diameter = InputHelpers.positive_number(input[1])
          length = InputHelpers.positive_number(input[2], 0.0)
          return invalid("Please enter a valid new diameter.") unless diameter
          return invalid("The new diameter must be different from the current diameter.") if
            (diameter - dimensions[:diameter].to_f).abs <= 0.001

          @last_round_diameter = diameter
          @last_length = length
          { diameter: diameter, width: diameter, height: diameter, length: length }
        end

        def prompt_rectangular(dimensions)
          default_length = Geometry::ReducerBuilder.default_length(
            dimensions,
            {
              shape: :rectangular,
              width: @last_rectangular_width,
              height: @last_rectangular_height
            }
          )

          input = ::UI.inputbox(
            ["Current Width:", "Current Height:", "New Width:", "New Height:", "Transition Length:"],
            [
              dimensions[:width].to_s,
              dimensions[:height].to_s,
              @last_rectangular_width.to_s,
              @last_rectangular_height.to_s,
              length_default(default_length)
            ],
            [],
            "Rectangular Increaser / Reducer"
          )
          return nil unless input

          width = InputHelpers.positive_number(input[2])
          height = InputHelpers.positive_number(input[3])
          length = InputHelpers.positive_number(input[4], 0.0)
          return invalid("Please enter a valid new width and height.") unless width && height

          changed =
            (width - dimensions[:width].to_f).abs > 0.001 ||
            (height - dimensions[:height].to_f).abs > 0.001
          return invalid("The new width or height must be different from the current size.") unless changed

          @last_rectangular_width = width
          @last_rectangular_height = height
          @last_length = length
          { diameter: [width, height].max, width: width, height: height, length: length }
        end

        def length_default(default_length)
          @last_length.to_f > 0.0 ? @last_length.to_s : default_length.round(2).to_s
        end

        def invalid(message)
          ::UI.messagebox(message)
          nil
        end
      end
    end
  end
end
