# ===== Consolidated from: services/selection_resize_planner.rb =====
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

# ===== Consolidated from: services/selection_resize_service.rb =====
module DuctExtension
  module Services
    class SelectionResizeService
      SUPPORTED_TYPES = [:pipe, :elbow, :reducer, :tee, :wye, :cross].freeze

      def self.run(model:, network:)
        return false unless model

        network ||= DuctExtension.network_for_model(model)
        NetworkRebuildService.rebuild(model, target_network: network)

        selected_pieces = SelectionResizePlanner.selected_duct_pieces(model, network)
        if selected_pieces.empty?
          UI.messagebox(
            "Select one or more duct pieces first.\n\n" \
            "Supported pieces include pipes, elbows, reducers, tees, crosses, and wyes."
          )
          return false
        end

        unsupported = selected_pieces.reject { |piece| SUPPORTED_TYPES.include?(piece.type.to_sym) }
        unless unsupported.empty?
          types = unsupported.map { |piece| piece.type.to_s }.uniq.sort.join(", ")
          UI.messagebox(
            "Resize Selected Duct Pieces supports pipes, elbows, reducers, tees, crosses, and wyes.\n\n" \
            "Your selection includes unsupported fitting types:\n\n#{types}"
          )
          return false
        end

        shape = SelectionResizePlanner.common_shape_for(selected_pieces)
        unless shape
          UI.messagebox(
            "Please select only one duct shape at a time.\n\n" \
            "Do not mix round and rectangular duct pieces in the same resize operation."
          )
          return false
        end

        target_dimensions = SelectionResizePlanner.prompt_for_target_dimensions(shape, selected_pieces)
        return false unless target_dimensions

        selected_set = selected_pieces.each_with_object({}) { |piece, hash| hash[piece.object_id] = true }
        old_dimensions_by_piece = selected_pieces.each_with_object({}) do |piece, hash|
          hash[piece.object_id] = SelectionResizePlanner.dimensions_for_piece(piece)
        end

        boundary_count = 0
        failed_piece = nil

        success = ModelOperation.run(
          model: model,
          network: network,
          name: "Resize Selected Duct Pieces"
        ) do |operation|
          SelectionResizeLayoutService.adjust_selected_layout_for_size_change!(
            network: network,
            selected_pieces: selected_pieces,
            selected_set: selected_set,
            old_dimensions_by_piece: old_dimensions_by_piece,
            target_dimensions: target_dimensions
          )

          boundary_connections = SelectionResizeLayoutService.selected_boundary_connections(network, selected_pieces)
          boundary_plan = SelectionResizeLayoutService.build_boundary_plan(
            boundary_connections: boundary_connections,
            selected_set: selected_set,
            target_dimensions: target_dimensions
          )
          boundary_count = boundary_plan.length
          SelectionResizeLayoutService.apply_boundary_pullbacks!(boundary_plan)

          selected_pieces.each do |piece|
            next if SelectionPieceResizeService.rebuild!(piece: piece, target_dimensions: target_dimensions)

            failed_piece = piece
            operation.abort!(false)
          end

          boundary_plan.each do |item|
            reducer = SelectionResizeLayoutService.insert_boundary_reducer!(
              model: model,
              network: network,
              selected_port: item[:selected_port],
              external_port: item[:external_port],
              selected_dimensions: target_dimensions,
              external_dimensions: item[:external_dimensions]
            )
            operation.abort!(false) unless reducer
          end

          selected_pieces.each { |piece| PieceMetadataService.save_piece(piece) }
          true
        end

        unless success
          UI.messagebox(
            "Resize failed#{failed_piece ? " while rebuilding a #{failed_piece.type}" : ""}.\n\n" \
            "No changes were committed.\n\nCheck the Ruby Console for details."
          )
          return false
        end

        UI.messagebox(
          "Resized #{selected_pieces.length} selected duct piece(s).\n\n" \
          "Inserted #{boundary_count} automatic reducer/increaser fitting(s) at selected-to-unselected boundaries."
        )
        true
      rescue => error
        puts "SelectionResizeService.run failed: #{error.message}"
        puts error.backtrace.join("\n")
        UI.messagebox("Resize Selected Duct Pieces failed.\n\nCheck the Ruby Console for details.")
        false
      end
    end
  end
end
