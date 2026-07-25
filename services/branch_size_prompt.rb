module DuctExtension
  module Services
    # Shared branch-size UI for fittings whose side outlet may differ from the
    # main duct. Keeping this here prevents wye/cross tools from drifting into
    # slightly different validation/default rules.
    module BranchSizePrompt
      def self.ask(main_dimensions:, title:, allow_round_from_rectangular: false)
        main = Model::DuctDimensions.coerce(main_dimensions)

        if main.round?
          input = ::UI.inputbox(
            ["Main Diameter:", "Branch Diameter:"],
            [main.diameter.to_s, main.diameter.to_s],
            [],
            title
          )
          return nil unless input

          return Model::DuctDimensions.round(
            diameter: Model::DuctDimensions.positive_number(input[1], main.diameter)
          )
        end

        if allow_round_from_rectangular
          input = ::UI.inputbox(
            [
              "Main Width:", "Main Height:", "Branch Shape:",
              "Round Branch Diameter:", "Rectangular Branch Width:", "Rectangular Branch Height:"
            ],
            [
              main.width.to_s, main.height.to_s, "Rectangular",
              main.largest.to_s, main.width.to_s, main.height.to_s
            ],
            ["", "", "Rectangular|Round", "", "", ""],
            title
          )
          return nil unless input

          if Model::DuctDimensions.normalize_shape(input[2]) == :round
            return Model::DuctDimensions.round(
              diameter: Model::DuctDimensions.positive_number(input[3], main.largest)
            )
          end

          return Model::DuctDimensions.rectangular(
            width: Model::DuctDimensions.positive_number(input[4], main.width),
            height: Model::DuctDimensions.positive_number(input[5], main.height)
          )
        end

        input = ::UI.inputbox(
          ["Main Width:", "Main Height:", "Branch Width:", "Branch Height:"],
          [main.width.to_s, main.height.to_s, main.width.to_s, main.height.to_s],
          [],
          title
        )
        return nil unless input

        Model::DuctDimensions.rectangular(
          width: Model::DuctDimensions.positive_number(input[2], main.width),
          height: Model::DuctDimensions.positive_number(input[3], main.height)
        )
      rescue => error
        puts "BranchSizePrompt.ask failed: #{error.message}"
        nil
      end
    end
  end
end
