module DuctExtension
  module Services
    class TeeInsertService
      DICTIONARY = "DuctExtension"

      MIN_SEGMENT_LENGTH_FACTOR = 0.5
      FALLBACK_SOCKET_DEPTH_FACTOR = 0.82
      CAP_SEGMENTS = 32

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
              fallback_branch_direction: branch_direction
            )
          else
            Geometry::VectorMath.perpendicularized(branch_direction, main_vector)
          end

        return nil unless branch_vector
        return nil if main_vector.parallel?(branch_vector)

        socket_depth = TeePlacementCalculator.socket_depth(dimensions)

        main_start_socket = center.offset(main_vector.clone.reverse, socket_depth)
        main_end_socket = center.offset(main_vector, socket_depth)

        min_length = Model::DimensionUtils.largest(dimensions) * MIN_SEGMENT_LENGTH_FACTOR

        return nil if point_a.distance(main_start_socket) < min_length
        return nil if point_b.distance(main_end_socket) < min_length

        old_group = pipe_piece.group

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
            socket_depth: socket_depth
          )

          operation.abort!(nil) unless result
          result
        end
      rescue => error
        puts "TeeInsertService.insert_tee_on_pipe failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.build_split_pipe_and_tee(
        model:,
        network:,
        point_a:,
        point_b:,
        center:,
        main_vector:,
        branch_vector:,
        dimensions:,
        socket_depth:
      )
        rectangular_basis =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(main_vector)
          else
            nil
          end

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
            Geometry::RectangularFrame.basis_for_axis(branch_vector)
          else
            nil
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

        add_cap_for_port(tee_group, branch_port)

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

      def self.add_cap_for_port(group, port)
        return unless group && group.valid?
        return unless port

        if port.rectangular?
          add_rectangular_cap_for_port(group, port)
        else
          add_round_cap_for_port(group, port)
        end
      rescue => error
        puts "TeeInsertService.add_cap_for_port failed: #{error.message}"
      end

      def self.add_round_cap_for_port(group, port)
        normal = port.vector.clone
        return if normal.length == 0

        normal.normalize!

        circle = group.entities.add_circle(
          port.point,
          normal,
          port.diameter.to_f / 2.0,
          CAP_SEGMENTS
        )

        face = group.entities.add_face(circle)
        return unless face

        face.reverse! if face.normal.dot(normal) < 0

        face.set_attribute(DICTIONARY, "tee_cap", true)
        face.set_attribute(DICTIONARY, "cap_point", port.point.to_a)
      end

      def self.add_rectangular_cap_for_port(group, port)
        normal = port.vector.clone
        return if normal.length == 0

        normal.normalize!

        corners = Geometry::RectangularFrame.rectangle_corners(
          port.point,
          normal,
          port.width,
          port.height,
          preferred_width_axis: port.width_axis,
          preferred_height_axis: port.height_axis
        )

        return if corners.empty?

        face = group.entities.add_face(corners)
        return unless face

        face.reverse! if face.normal.dot(normal) < 0

        face.set_attribute(DICTIONARY, "tee_cap", true)
        face.set_attribute(DICTIONARY, "cap_point", port.point.to_a)
      end

      def self.remove_cap_for_port(port)
        return unless port
        return unless port.piece
        return unless port.piece.type == :tee

        group = port.piece.group
        return unless group && group.valid?

        group.entities.grep(Sketchup::Face).each do |face|
          next unless face.valid?
          next unless face.get_attribute(DICTIONARY, "tee_cap")

          cap_point = face.get_attribute(DICTIONARY, "cap_point")
          next unless cap_point

          point = Geom::Point3d.new(cap_point)

          if point.distance(port.point) < Model::Network::CONNECTION_DISTANCE * 4.0
            face.erase!
          end
        end
      rescue => error
        puts "TeeInsertService.remove_cap_for_port failed: #{error.message}"
      end

      private_class_method :build_split_pipe_and_tee
      private_class_method :build_pipe_piece
      private_class_method :add_round_cap_for_port
      private_class_method :add_rectangular_cap_for_port
    end
  end
end
