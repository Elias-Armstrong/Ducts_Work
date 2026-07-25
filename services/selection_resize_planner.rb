module DuctExtension
  module Services
    module SelectionResizePlanner
      def self.selected_duct_pieces(model, network)
        selected_groups = model.selection.to_a.select { |entity| entity.respond_to?(:get_attribute) }

        network.pieces.select do |piece|
          piece && piece.group && piece.group.valid? && selected_groups.include?(piece.group)
        end
      rescue
        []
      end

      def self.common_shape_for(pieces)
        shapes = pieces.flat_map do |piece|
          Array(piece.ports).map { |port| Model::DuctDimensions.normalize_shape(port.shape) }
        end.compact.uniq

        return nil if shapes.empty? || shapes.length > 1

        shapes.first
      rescue
        nil
      end

      def self.prompt_for_target_dimensions(shape, selected_pieces)
        sample_port = selected_pieces.flat_map(&:ports).compact.first
        current = dimensions_for_port(sample_port)

        if shape == :rectangular
          input = UI.inputbox(
            ["New Width:", "New Height:"],
            [current[:width].to_s, current[:height].to_s],
            [],
            "Resize Selected Rectangular Duct"
          )
          return nil unless input

          width = Model::DuctDimensions.positive_number(input[0], nil)
          height = Model::DuctDimensions.positive_number(input[1], nil)
          unless width && height
            UI.messagebox("Please enter a valid width and height.")
            return nil
          end

          Model::DuctDimensions.rectangular(width: width, height: height)
        else
          input = UI.inputbox(
            ["New Diameter:"],
            [current[:diameter].to_s],
            [],
            "Resize Selected Round Duct"
          )
          return nil unless input

          diameter = Model::DuctDimensions.positive_number(input[0], nil)
          unless diameter
            UI.messagebox("Please enter a valid diameter.")
            return nil
          end

          Model::DuctDimensions.round(diameter: diameter)
        end
      rescue => error
        puts "SelectionResizePlanner.prompt_for_target_dimensions failed: #{error.message}"
        nil
      end

      def self.dimensions_for_piece(piece)
        dimensions_for_port(Array(piece.ports).compact.first)
      rescue
        Model::DuctDimensions.round
      end

      def self.dimensions_for_port(port)
        Model::Port.dimensions_from_params({}, port)
      rescue
        Model::DuctDimensions.round
      end

    end
  end
end
