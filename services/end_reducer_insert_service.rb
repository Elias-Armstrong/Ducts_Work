module DuctExtension
  module Services
    class EndReducerInsertService
      def self.insert_at_port(
        model:,
        network:,
        stem_port:,
        new_diameter: nil,
        new_width: nil,
        new_height: nil,
        length: nil
      )
        return nil unless model && network
        return nil unless stem_port
        return nil unless stem_port.piece
        return nil unless stem_port.piece.group && stem_port.piece.group.valid?

        start_dimensions = Model::Port.dimensions_from_params({}, stem_port)

        end_dimensions =
          if start_dimensions[:shape] == :rectangular
            Model::Port.dimensions_from_params(
              {
                shape: :rectangular,
                width: new_width,
                height: new_height
              },
              stem_port
            )
          else
            Model::Port.dimensions_from_params(
              {
                shape: :round,
                diameter: new_diameter
              },
              stem_port
            )
          end

        return nil unless valid_size_change?(start_dimensions, end_dimensions)

        direction = stem_port.outward_vector.clone
        return nil if direction.length == 0

        direction.normalize!

        transition_length = length.to_f
        transition_length =
          Geometry::ReducerBuilder.default_length(start_dimensions, end_dimensions) if transition_length <= 0.0

        start_point = stem_port.point
        end_point = start_point.offset(direction, transition_length)

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert Increaser / Reducer"
        ) do |operation|

        group = model.active_entities.add_group
        group.name =
          if end_dimensions[:shape] == :rectangular
            rectangular_group_name(start_dimensions, end_dimensions)
          else
            round_group_name(start_dimensions, end_dimensions)
          end

        success = Geometry::ReducerBuilder.build_into(
          group,
          start_point,
          end_point,
          start_dimensions: start_dimensions,
          end_dimensions: end_dimensions,
          preferred_width_axis: stem_port.width_axis,
          preferred_height_axis: stem_port.height_axis
        )

        unless success
          group.erase! if group.valid?
          operation.abort!(nil)
        end

        start_basis =
          if start_dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(
              direction,
              preferred_width_axis: stem_port.width_axis,
              preferred_height_axis: stem_port.height_axis
            )
          else
            nil
          end

        end_basis =
          if end_dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(
              direction,
              preferred_width_axis: stem_port.width_axis,
              preferred_height_axis: stem_port.height_axis
            )
          else
            nil
          end

        reducer_start_port = Model::Port.new(
          point: start_point,
          vector: direction.clone.reverse,
          diameter: start_dimensions[:diameter],
          shape: start_dimensions[:shape],
          width: start_dimensions[:width],
          height: start_dimensions[:height],
          width_axis: start_basis && start_basis[:width_axis],
          height_axis: start_basis && start_basis[:height_axis]
        )

        reducer_end_port = Model::Port.new(
          point: end_point,
          vector: direction.clone,
          diameter: end_dimensions[:diameter],
          shape: end_dimensions[:shape],
          width: end_dimensions[:width],
          height: end_dimensions[:height],
          width_axis: end_basis && end_basis[:width_axis],
          height_axis: end_basis && end_basis[:height_axis]
        )

        piece = Model::DuctPiece.new(
          type: :reducer,
          group: group,
          ports: [reducer_start_port, reducer_end_port]
        )

        network.add_piece(piece)
        PieceMetadataService.save_piece(piece)

        network.connect_ports(stem_port, reducer_start_port)

        PortCapService.remove(stem_port)

        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        {
          piece: piece,
          old_port: reducer_start_port,
          new_port: reducer_end_port,
          start_dimensions: start_dimensions,
          end_dimensions: end_dimensions
        }
        end
      rescue => error
        puts "EndReducerInsertService.insert_at_port failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.valid_size_change?(start_dimensions, end_dimensions)
        return false unless start_dimensions && end_dimensions
        return false unless start_dimensions[:shape] == end_dimensions[:shape]

        if start_dimensions[:shape] == :rectangular
          return false if end_dimensions[:width].to_f <= 0.0
          return false if end_dimensions[:height].to_f <= 0.0

          width_changed = (start_dimensions[:width].to_f - end_dimensions[:width].to_f).abs > 0.001
          height_changed = (start_dimensions[:height].to_f - end_dimensions[:height].to_f).abs > 0.001

          width_changed || height_changed
        else
          return false if end_dimensions[:diameter].to_f <= 0.0

          (start_dimensions[:diameter].to_f - end_dimensions[:diameter].to_f).abs > 0.001
        end
      end

      def self.round_group_name(start_dimensions, end_dimensions)
        if end_dimensions[:diameter].to_f > start_dimensions[:diameter].to_f
          "Round Duct Increaser"
        else
          "Round Duct Reducer"
        end
      end

      def self.rectangular_group_name(start_dimensions, end_dimensions)
        start_area = start_dimensions[:width].to_f * start_dimensions[:height].to_f
        end_area = end_dimensions[:width].to_f * end_dimensions[:height].to_f

        if end_area > start_area
          "Rectangular Duct Increaser"
        else
          "Rectangular Duct Reducer"
        end
      end
    end
  end
end
