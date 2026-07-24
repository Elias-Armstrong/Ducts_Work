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
