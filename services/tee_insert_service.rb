module DuctExtension
  module Services
    class TeeInsertService
      MIN_SEGMENT_LENGTH_FACTOR = 0.5
      FALLBACK_SOCKET_DEPTH_FACTOR = 0.82

      def self.insert_tee_on_pipe(model:, network:, pipe_piece:, tap_point:, branch_direction:)
        return nil unless pipe_piece
        return nil unless pipe_piece.type == :pipe
        return nil unless pipe_piece.ports.length == 2

        old_port_a = pipe_piece.ports[0]
        old_port_b = pipe_piece.ports[1]

        dimensions = Model::Port.dimensions_from_params({}, old_port_a)

        point_a = old_port_a.point
        point_b = old_port_b.point

        main_vector = point_a.vector_to(point_b)
        return nil if main_vector.length == 0

        main_vector.normalize!

        rectangular_basis =
          if dimensions[:shape] == :rectangular
            basis_for_existing_rectangular_pipe(
              main_vector: main_vector,
              port_a: old_port_a,
              port_b: old_port_b
            )
          end
        return nil if dimensions[:shape] == :rectangular && !rectangular_basis

        center = TeePlacementCalculator.project_point_to_segment(
          point: tap_point,
          line_start: point_a,
          line_end: point_b
        )
        return nil unless center

        branch_vector =
          if dimensions[:shape] == :rectangular
            TeePlacementCalculator.rectangular_side_branch_vector(
              tap_point: tap_point,
              center: center,
              main_vector: main_vector,
              fallback_branch_direction: branch_direction,
              basis: rectangular_basis
            )
          else
            Geometry::VectorMath.perpendicularized(branch_direction, main_vector)
          end

        return nil unless branch_vector
        return nil if main_vector.parallel?(branch_vector)

        socket_depth = TeePlacementCalculator.socket_depth(dimensions)

        main_start_socket = center.offset(main_vector.clone.reverse, socket_depth)
        main_end_socket = center.offset(main_vector, socket_depth)

        min_length = Model::DuctDimensions.coerce(dimensions).largest * MIN_SEGMENT_LENGTH_FACTOR

        return nil if point_a.distance(main_start_socket) < min_length
        return nil if point_b.distance(main_end_socket) < min_length

        old_group = pipe_piece.group
        external_neighbors_a = external_neighbors(network, old_port_a, pipe_piece)
        external_neighbors_b = external_neighbors(network, old_port_b, pipe_piece)

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert Duct Tee"
        ) do |operation|
          old_group.erase! if old_group && old_group.valid?
          network.remove_piece(pipe_piece)

          result = build_split_pipe_and_tee(
            model: model,
            network: network,
            point_a: point_a,
            point_b: point_b,
            center: center,
            main_vector: main_vector,
            branch_vector: branch_vector,
            dimensions: dimensions,
            socket_depth: socket_depth,
            rectangular_basis: rectangular_basis,
            external_neighbors_a: external_neighbors_a,
            external_neighbors_b: external_neighbors_b
          )

          operation.abort!(nil) unless result
          result
        end
      rescue => error
        puts "TeeInsertService.insert_tee_on_pipe failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.basis_for_existing_rectangular_pipe(main_vector:, port_a:, port_b:)
        Geometry::RectangularFrame.basis_for_axis(
          main_vector,
          preferred_width_axis: port_a&.width_axis || port_b&.width_axis,
          preferred_height_axis: port_a&.height_axis || port_b&.height_axis
        )
      rescue
        nil
      end
      private_class_method :basis_for_existing_rectangular_pipe

      def self.external_neighbors(network, port, piece)
        Array(network.connected_ports(port)).select { |other| other && other.piece != piece }
      rescue
        []
      end
      private_class_method :external_neighbors

      def self.reconnect_neighbors(network, replacement_port, neighbors)
        Array(neighbors).each { |neighbor| network.connect_ports(replacement_port, neighbor) }
      end
      private_class_method :reconnect_neighbors

      def self.build_split_pipe_and_tee(
        model:,
        network:,
        point_a:,
        point_b:,
        center:,
        main_vector:,
        branch_vector:,
        dimensions:,
        socket_depth:,
        rectangular_basis: nil,
        external_neighbors_a: [],
        external_neighbors_b: []
      )

        main_start_socket = center.offset(main_vector.clone.reverse, socket_depth)
        main_end_socket = center.offset(main_vector, socket_depth)

        branch_base =
          if dimensions[:shape] == :rectangular
            TeePlacementCalculator.rectangular_branch_base_point(
              center: center,
              branch_vector: branch_vector,
              dimensions: dimensions,
              basis: rectangular_basis
            )
          else
            center
          end

        branch_socket = branch_base.offset(branch_vector, socket_depth)

        pipe_a = build_pipe_piece(
          model: model,
          network: network,
          start_point: point_a,
          end_point: main_start_socket,
          dimensions: dimensions,
          preferred_width_axis: rectangular_basis && rectangular_basis[:width_axis],
          preferred_height_axis: rectangular_basis && rectangular_basis[:height_axis]
        )

        pipe_b = build_pipe_piece(
          model: model,
          network: network,
          start_point: main_end_socket,
          end_point: point_b,
          dimensions: dimensions,
          preferred_width_axis: rectangular_basis && rectangular_basis[:width_axis],
          preferred_height_axis: rectangular_basis && rectangular_basis[:height_axis]
        )

        return nil unless pipe_a && pipe_b

        tee_group = model.active_entities.add_group
        tee_group.name =
          if dimensions[:shape] == :rectangular
            "Rectangular Duct Tee"
          else
            "Duct Tee"
          end

        success =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularTeeBuilder.build_into(
              tee_group,
              center,
              branch_base,
              main_vector,
              branch_vector,
              dimensions[:width],
              dimensions[:height],
              socket_depth,
              preferred_main_width_axis: rectangular_basis && rectangular_basis[:width_axis],
              preferred_main_height_axis: rectangular_basis && rectangular_basis[:height_axis]
            )
          else
            Geometry::TeeBuilder.build_into(
              tee_group,
              center,
              main_vector,
              branch_vector,
              dimensions[:diameter]
            )
          end

        unless success
          tee_group.erase! if tee_group.valid?
          return nil
        end

        branch_basis =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularTeeBuilder.branch_basis(
              main_vector,
              branch_vector,
              main_basis: rectangular_basis
            )
          end

        main_start_port = Model::Port.new(
          point: main_start_socket,
          vector: main_vector.clone.reverse,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: rectangular_basis && rectangular_basis[:width_axis],
          height_axis: rectangular_basis && rectangular_basis[:height_axis]
        )

        main_end_port = Model::Port.new(
          point: main_end_socket,
          vector: main_vector.clone,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: rectangular_basis && rectangular_basis[:width_axis],
          height_axis: rectangular_basis && rectangular_basis[:height_axis]
        )

        branch_port = Model::Port.new(
          point: branch_socket,
          vector: branch_vector.clone,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: branch_basis && branch_basis[:width_axis],
          height_axis: branch_basis && branch_basis[:height_axis]
        )

        tee_piece = Model::DuctPiece.new(
          type: :tee,
          group: tee_group,
          ports: [main_start_port, main_end_port, branch_port]
        )

        network.add_piece(tee_piece)
        PieceMetadataService.save_piece(tee_piece)

        network.connect_ports(pipe_a.ports[1], main_start_port)
        network.connect_ports(pipe_b.ports[0], main_end_port)
        reconnect_neighbors(network, pipe_a.ports[0], external_neighbors_a)
        reconnect_neighbors(network, pipe_b.ports[1], external_neighbors_b)

        PortCapService.add(tee_group, branch_port)

        {
          tee_piece: tee_piece,
          branch_port: branch_port,
          pipe_a: pipe_a,
          pipe_b: pipe_b
        }
      end

      def self.build_pipe_piece(
        model:,
        network:,
        start_point:,
        end_point:,
        dimensions:,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        vector = start_point.vector_to(end_point)
        return nil if vector.length == 0

        vector.normalize!

        group = model.active_entities.add_group
        group.name =
          if dimensions[:shape] == :rectangular
            "Rectangular Duct Pipe"
          else
            "Duct Pipe"
          end

        success =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularPipeBuilder.build_into(
              group,
              start_point,
              end_point,
              dimensions[:width],
              dimensions[:height],
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false,
              preferred_width_axis: preferred_width_axis,
              preferred_height_axis: preferred_height_axis
            )
          else
            Geometry::PipeBuilder.build_into(
              group,
              start_point,
              end_point,
              dimensions[:diameter],
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false
            )
          end

        unless success
          group.erase! if group.valid?
          return nil
        end

        basis =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(
              vector,
              preferred_width_axis: preferred_width_axis,
              preferred_height_axis: preferred_height_axis
            )
          else
            nil
          end

        start_port = Model::Port.new(
          point: start_point,
          vector: vector.clone.reverse,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: basis && basis[:width_axis],
          height_axis: basis && basis[:height_axis]
        )

        end_port = Model::Port.new(
          point: end_point,
          vector: vector.clone,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: basis && basis[:width_axis],
          height_axis: basis && basis[:height_axis]
        )

        piece = Model::DuctPiece.new(
          type: :pipe,
          group: group,
          ports: [start_port, end_port]
        )

        network.add_piece(piece)
        PieceMetadataService.save_piece(piece)

        piece
      end

      private_class_method :build_split_pipe_and_tee
      private_class_method :build_pipe_piece
    end
  end
end
