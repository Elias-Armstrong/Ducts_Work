module DuctExtension
  module Services
    class ConnectorSwingService
      PICK_RADIUS_PIXELS = 44

      EPSILON = 0.000001
      ROUND_SWING_ANGLE = 45.degrees
      RECTANGULAR_SWING_ANGLE = 90.degrees

      SWINGABLE_TYPES = [
        :tee,
        :cross,
        :wye
      ].freeze

      def self.swing_at_click(model:, network:, view:, x:, y:, angle: nil)
        return { status: :failed } unless model && network && view

        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        piece = picked_swingable_piece(
          network: network,
          view: view,
          x: x,
          y: y
        )

        return { status: :no_piece } unless piece

        unless SWINGABLE_TYPES.include?(piece.type.to_sym)
          return {
            status: :not_swingable,
            piece: piece
          }
        end

        axis_data = rotation_axis_for_piece(network, piece)

        unless axis_data
          return {
            status: :too_many_connections,
            piece: piece
          }
        end

        if rectangular_piece?(piece)
          rebuild_rectangular_connector(
            model: model,
            network: network,
            piece: piece,
            axis_data: axis_data
          )
        else
          rotate_round_connector(
            model: model,
            network: network,
            piece: piece,
            axis_data: axis_data
          )
        end
      rescue => error
        puts "ConnectorSwingService.swing_at_click failed: #{error.message}"
        puts error.backtrace.join("\n")

        {
          status: :failed
        }
      end

      def self.rotate_round_connector(model:, network:, piece:, axis_data:)
        pivot = axis_data[:pivot]
        axis = axis_data[:axis]

        return { status: :failed, piece: piece } unless pivot && axis
        return { status: :failed, piece: piece } if axis.length <= EPSILON

        axis.normalize!

        model.start_operation("Swing Round Duct Connector", true)

        transformation = Geom::Transformation.rotation(
          pivot,
          axis,
          ROUND_SWING_ANGLE
        )

        piece.group.transform!(transformation)

        transform_piece_ports(piece, transformation)

        PieceMetadataService.save_piece(piece)

        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        model.commit_operation

        {
          status: :ok,
          piece: piece,
          angle: ROUND_SWING_ANGLE,
          angle_degrees: 45
        }
      rescue => error
        model.abort_operation if model
        puts "ConnectorSwingService.rotate_round_connector failed: #{error.message}"
        puts error.backtrace.join("\n")

        {
          status: :failed,
          piece: piece
        }
      end

      def self.rebuild_rectangular_connector(model:, network:, piece:, axis_data:)
        return { status: :failed, piece: piece } unless piece.group && piece.group.valid?

        connected = axis_data[:connected]
        return { status: :too_many_connections, piece: piece } unless connected
        return { status: :too_many_connections, piece: piece } if connected.empty?
        return { status: :too_many_connections, piece: piece } if connected.length > 2

        pivot = axis_data[:pivot]
        axis = axis_data[:axis]

        return { status: :failed, piece: piece } unless pivot && axis
        return { status: :failed, piece: piece } if axis.length <= EPSILON

        axis.normalize!

        dimensions = dimensions_for_piece(piece)
        return { status: :failed, piece: piece } unless dimensions
        return { status: :failed, piece: piece } unless dimensions[:shape] == :rectangular

        current_side = current_side_axis_for_piece(piece, axis)
        current_side ||= fallback_perpendicular_axis(axis)

        return { status: :failed, piece: piece } unless current_side

        current_side.normalize!

        rotation = Geom::Transformation.rotation(
          pivot,
          axis,
          RECTANGULAR_SWING_ANGLE
        )

        new_side = current_side.transform(rotation)
        return { status: :failed, piece: piece } if new_side.length <= EPSILON

        new_side.normalize!

        model.start_operation("Rebuild Rectangular Duct Connector", true)

        success =
          if connected.length == 1
            rebuild_rectangular_end_connector(
              piece: piece,
              connected: connected,
              dimensions: dimensions,
              side_axis: new_side
            )
          else
            rebuild_rectangular_inline_connector(
              piece: piece,
              connected: connected,
              dimensions: dimensions,
              side_axis: new_side
            )
          end

        unless success
          model.abort_operation
          return {
            status: :failed,
            piece: piece
          }
        end

        PieceMetadataService.save_piece(piece)

        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        model.commit_operation

        {
          status: :ok,
          piece: piece,
          angle: RECTANGULAR_SWING_ANGLE,
          angle_degrees: 90
        }
      rescue => error
        model.abort_operation if model
        puts "ConnectorSwingService.rebuild_rectangular_connector failed: #{error.message}"
        puts error.backtrace.join("\n")

        {
          status: :failed,
          piece: piece
        }
      end

      def self.rebuild_rectangular_end_connector(piece:, connected:, dimensions:, side_axis:)
        anchor_port = connected.first[:port]
        return false unless anchor_port

        external_port = connected.first[:external]

        # For an end fitting, the connector's attached port usually points back
        # toward the pipe. The fitting grows in the opposite direction.
        forward_axis = anchor_port.outward_vector.clone.reverse
        return false if forward_axis.length <= EPSILON

        forward_axis.normalize!

        side_axis = perpendicularized(side_axis, forward_axis)
        side_axis ||= fallback_perpendicular_axis(forward_axis)
        return false unless side_axis

        side_axis.normalize!

        height_axis = preferred_height_axis_for_anchor(anchor_port, external_port, forward_axis, side_axis)
        return false unless height_axis

        height_axis.normalize!

        erase_group_geometry(piece.group)

        case piece.type.to_sym
        when :tee
          rebuild_rectangular_end_tee(
            piece: piece,
            anchor_port: anchor_port,
            dimensions: dimensions,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis
          )
        when :cross
          rebuild_rectangular_end_cross(
            piece: piece,
            anchor_port: anchor_port,
            dimensions: dimensions,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis
          )
        when :wye
          rebuild_rectangular_end_wye(
            piece: piece,
            anchor_port: anchor_port,
            dimensions: dimensions,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis
          )
        else
          false
        end
      rescue => error
        puts "ConnectorSwingService.rebuild_rectangular_end_connector failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_rectangular_inline_connector(piece:, connected:, dimensions:, side_axis:)
        return false unless connected.length == 2

        port_a = connected[0][:port]
        port_b = connected[1][:port]

        return false unless port_a && port_b
        return false unless port_a.point && port_b.point

        main_axis = port_a.point.vector_to(port_b.point)
        return false if main_axis.length <= EPSILON

        main_axis.normalize!

        side_axis = perpendicularized(side_axis, main_axis)
        side_axis ||= fallback_perpendicular_axis(main_axis)
        return false unless side_axis

        side_axis.normalize!

        center = midpoint(port_a.point, port_b.point)

        height_axis =
          perpendicularized(port_a.height_axis, main_axis) ||
          perpendicularized(port_b.height_axis, main_axis) ||
          main_axis.cross(side_axis)

        return false unless height_axis
        return false if height_axis.length <= EPSILON

        height_axis.normalize!

        corrected_side = height_axis.cross(main_axis)
        if corrected_side && corrected_side.length > EPSILON
          corrected_side.normalize!
          side_axis = corrected_side
        end

        erase_group_geometry(piece.group)

        case piece.type.to_sym
        when :tee
          rebuild_rectangular_inline_tee(
            piece: piece,
            connected_ports: [port_a, port_b],
            dimensions: dimensions,
            center: center,
            main_axis: main_axis,
            side_axis: side_axis,
            height_axis: height_axis
          )
        when :cross
          rebuild_rectangular_inline_cross(
            piece: piece,
            connected_ports: [port_a, port_b],
            dimensions: dimensions,
            center: center,
            main_axis: main_axis,
            side_axis: side_axis,
            height_axis: height_axis
          )
        else
          # Inline wyes are more ambiguous because the angled branch/trunk choice
          # matters. Keep this safe for now.
          false
        end
      rescue => error
        puts "ConnectorSwingService.rebuild_rectangular_inline_connector failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_rectangular_end_tee(
        piece:,
        anchor_port:,
        dimensions:,
        forward_axis:,
        side_axis:,
        height_axis:
      )
        socket_depth = Geometry::RectangularTeeBuilder.socket_depth(
          dimensions[:width],
          dimensions[:height]
        )

        main_basis = Geometry::RectangularFrame.basis_for_axis(
          side_axis,
          preferred_width_axis: forward_axis,
          preferred_height_axis: height_axis
        )

        return false unless main_basis

        stem_into_tee = forward_axis.clone.reverse

        face_offset = rectangular_face_offset_for_direction(
          direction: stem_into_tee,
          dimensions: dimensions,
          basis: main_basis
        )

        center = anchor_port.point.offset(forward_axis, socket_depth + face_offset)
        branch_base = center.offset(stem_into_tee, face_offset)

        success = Geometry::RectangularTeeBuilder.build_into(
          piece.group,
          center,
          branch_base,
          side_axis,
          stem_into_tee,
          dimensions[:width],
          dimensions[:height],
          socket_depth,
          preferred_main_width_axis: main_basis[:width_axis],
          preferred_main_height_axis: main_basis[:height_axis]
        )

        return false unless success

        left_point = center.offset(side_axis.clone.reverse, socket_depth)
        right_point = center.offset(side_axis, socket_depth)

        free_ports = free_ports_for_piece(piece, [anchor_port])
        return false if free_ports.length < 2

        update_rectangular_port!(
          anchor_port,
          point: anchor_port.point,
          vector: stem_into_tee,
          dimensions: dimensions,
          direction: stem_into_tee,
          preferred_width_axis: main_basis[:width_axis],
          preferred_height_axis: main_basis[:height_axis]
        )

        update_rectangular_port!(
          free_ports[0],
          point: left_point,
          vector: side_axis.clone.reverse,
          dimensions: dimensions,
          direction: side_axis.clone.reverse,
          preferred_width_axis: forward_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          free_ports[1],
          point: right_point,
          vector: side_axis,
          dimensions: dimensions,
          direction: side_axis,
          preferred_width_axis: forward_axis,
          preferred_height_axis: height_axis
        )

        add_caps_to_free_ports(piece.group, free_ports)

        true
      rescue => error
        puts "ConnectorSwingService.rebuild_rectangular_end_tee failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_rectangular_end_cross(
        piece:,
        anchor_port:,
        dimensions:,
        forward_axis:,
        side_axis:,
        height_axis:
      )
        socket_depth = Geometry::CrossBuilder.socket_depth(
          dimensions[:width],
          dimensions[:height]
        )

        center = anchor_port.point.offset(forward_axis, socket_depth)
        stem_into_cross = forward_axis.clone.reverse

        success = Geometry::CrossBuilder.build_into(
          piece.group,
          center,
          forward_axis,
          side_axis,
          diameter: dimensions[:diameter],
          width: dimensions[:width],
          height: dimensions[:height],
          shape: :rectangular,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        return false unless success

        forward_point = center.offset(forward_axis, socket_depth)
        left_point = center.offset(side_axis.clone.reverse, socket_depth)
        right_point = center.offset(side_axis, socket_depth)

        free_ports = free_ports_for_piece(piece, [anchor_port])
        return false if free_ports.length < 3

        update_rectangular_port!(
          anchor_port,
          point: anchor_port.point,
          vector: stem_into_cross,
          dimensions: dimensions,
          direction: stem_into_cross,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          free_ports[0],
          point: forward_point,
          vector: forward_axis,
          dimensions: dimensions,
          direction: forward_axis,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          free_ports[1],
          point: left_point,
          vector: side_axis.clone.reverse,
          dimensions: dimensions,
          direction: side_axis.clone.reverse,
          preferred_width_axis: forward_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          free_ports[2],
          point: right_point,
          vector: side_axis,
          dimensions: dimensions,
          direction: side_axis,
          preferred_width_axis: forward_axis,
          preferred_height_axis: height_axis
        )

        add_caps_to_free_ports(piece.group, free_ports)

        true
      rescue => error
        puts "ConnectorSwingService.rebuild_rectangular_end_cross failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_rectangular_end_wye(
        piece:,
        anchor_port:,
        dimensions:,
        forward_axis:,
        side_axis:,
        height_axis:
      )
        base_socket_depth = Geometry::WyeBuilder.socket_depth(
          dimensions[:width],
          dimensions[:height]
        )

        main_socket_distance = Geometry::WyeBuilder.main_outlet_distance(
          dimensions[:width],
          dimensions[:height]
        )

        branch_socket_distance = Geometry::WyeBuilder.branch_outlet_distance(
          dimensions[:width],
          dimensions[:height]
        )

        center = anchor_port.point.offset(forward_axis, base_socket_depth)

        branch_axis = Geometry::WyeBuilder.branch_vector(forward_axis, side_axis)
        return false unless branch_axis

        success = Geometry::WyeBuilder.build_into(
          piece.group,
          center,
          forward_axis,
          side_axis,
          diameter: dimensions[:diameter],
          width: dimensions[:width],
          height: dimensions[:height],
          shape: :rectangular,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        return false unless success

        stem_into_wye = forward_axis.clone.reverse
        forward_point = center.offset(forward_axis, main_socket_distance)
        branch_point = center.offset(branch_axis, branch_socket_distance)

        free_ports = free_ports_for_piece(piece, [anchor_port])
        return false if free_ports.length < 2

        update_rectangular_port!(
          anchor_port,
          point: anchor_port.point,
          vector: stem_into_wye,
          dimensions: dimensions,
          direction: stem_into_wye,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          free_ports[0],
          point: forward_point,
          vector: forward_axis,
          dimensions: dimensions,
          direction: forward_axis,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        branch_width_axis =
          perpendicularized(side_axis, branch_axis) ||
          perpendicularized(forward_axis, branch_axis)

        branch_height_axis =
          perpendicularized(height_axis, branch_axis) ||
          begin
            axis = branch_axis.cross(branch_width_axis)
            axis.normalize! if axis && axis.length > EPSILON
            axis
          end

        update_rectangular_port!(
          free_ports[1],
          point: branch_point,
          vector: branch_axis,
          dimensions: dimensions,
          direction: branch_axis,
          preferred_width_axis: branch_width_axis,
          preferred_height_axis: branch_height_axis
        )

        add_caps_to_free_ports(piece.group, free_ports)

        true
      rescue => error
        puts "ConnectorSwingService.rebuild_rectangular_end_wye failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_rectangular_inline_tee(
        piece:,
        connected_ports:,
        dimensions:,
        center:,
        main_axis:,
        side_axis:,
        height_axis:
      )
        socket_depth = Geometry::RectangularTeeBuilder.socket_depth(
          dimensions[:width],
          dimensions[:height]
        )

        success = Geometry::RectangularTeeBuilder.build_into(
          piece.group,
          center,
          center,
          main_axis,
          side_axis,
          dimensions[:width],
          dimensions[:height],
          socket_depth,
          preferred_main_width_axis: side_axis,
          preferred_main_height_axis: height_axis
        )

        return false unless success

        port_a, port_b = connected_ports

        sorted = sort_ports_along_axis([port_a, port_b], center, main_axis)
        negative_main = sorted[0]
        positive_main = sorted[1]

        branch_point = center.offset(side_axis, socket_depth)

        free_ports = free_ports_for_piece(piece, connected_ports)
        return false if free_ports.empty?

        update_rectangular_port!(
          negative_main,
          point: center.offset(main_axis.clone.reverse, socket_depth),
          vector: main_axis.clone.reverse,
          dimensions: dimensions,
          direction: main_axis.clone.reverse,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          positive_main,
          point: center.offset(main_axis, socket_depth),
          vector: main_axis,
          dimensions: dimensions,
          direction: main_axis,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          free_ports[0],
          point: branch_point,
          vector: side_axis,
          dimensions: dimensions,
          direction: side_axis,
          preferred_width_axis: main_axis,
          preferred_height_axis: height_axis
        )

        add_caps_to_free_ports(piece.group, free_ports)

        true
      rescue => error
        puts "ConnectorSwingService.rebuild_rectangular_inline_tee failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_rectangular_inline_cross(
        piece:,
        connected_ports:,
        dimensions:,
        center:,
        main_axis:,
        side_axis:,
        height_axis:
      )
        socket_depth = Geometry::CrossBuilder.socket_depth(
          dimensions[:width],
          dimensions[:height]
        )

        success = Geometry::CrossBuilder.build_into(
          piece.group,
          center,
          main_axis,
          side_axis,
          diameter: dimensions[:diameter],
          width: dimensions[:width],
          height: dimensions[:height],
          shape: :rectangular,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        return false unless success

        port_a, port_b = connected_ports

        sorted = sort_ports_along_axis([port_a, port_b], center, main_axis)
        negative_main = sorted[0]
        positive_main = sorted[1]

        left_point = center.offset(side_axis.clone.reverse, socket_depth)
        right_point = center.offset(side_axis, socket_depth)

        free_ports = free_ports_for_piece(piece, connected_ports)
        return false if free_ports.length < 2

        update_rectangular_port!(
          negative_main,
          point: center.offset(main_axis.clone.reverse, socket_depth),
          vector: main_axis.clone.reverse,
          dimensions: dimensions,
          direction: main_axis.clone.reverse,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          positive_main,
          point: center.offset(main_axis, socket_depth),
          vector: main_axis,
          dimensions: dimensions,
          direction: main_axis,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          free_ports[0],
          point: left_point,
          vector: side_axis.clone.reverse,
          dimensions: dimensions,
          direction: side_axis.clone.reverse,
          preferred_width_axis: main_axis,
          preferred_height_axis: height_axis
        )

        update_rectangular_port!(
          free_ports[1],
          point: right_point,
          vector: side_axis,
          dimensions: dimensions,
          direction: side_axis,
          preferred_width_axis: main_axis,
          preferred_height_axis: height_axis
        )

        add_caps_to_free_ports(piece.group, free_ports)

        true
      rescue => error
        puts "ConnectorSwingService.rebuild_rectangular_inline_cross failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.picked_swingable_piece(network:, view:, x:, y:)
        candidates = []

        network.pieces.each do |piece|
          next unless piece
          next unless piece.group && piece.group.valid?
          next unless SWINGABLE_TYPES.include?(piece.type.to_sym)

          distance = screen_distance_to_piece(piece, view, x, y)
          next unless distance
          next if distance > PICK_RADIUS_PIXELS

          candidates << [piece, distance]
        end

        candidates.min_by { |item| item[1] }&.first
      rescue => error
        puts "ConnectorSwingService.picked_swingable_piece failed: #{error.message}"
        nil
      end

      def self.screen_distance_to_piece(piece, view, x, y)
        distances = []

        Array(piece.ports).each do |port|
          next unless port && port.point

          screen_point = view.screen_coords(port.point)
          distances << screen_distance(screen_point, x, y)
        end

        center = piece_center(piece)
        if center
          screen_center = view.screen_coords(center)
          distances << screen_distance(screen_center, x, y)
        end

        distances.compact.min
      rescue
        nil
      end

      def self.piece_center(piece)
        points = Array(piece.ports).map(&:point).compact
        return nil if points.empty?

        x = points.map(&:x).sum / points.length.to_f
        y = points.map(&:y).sum / points.length.to_f
        z = points.map(&:z).sum / points.length.to_f

        Geom::Point3d.new(x, y, z)
      rescue
        nil
      end

      def self.screen_distance(screen_point, x, y)
        dx = screen_point.x.to_f - x.to_f
        dy = screen_point.y.to_f - y.to_f

        Math.sqrt(dx * dx + dy * dy)
      rescue
        nil
      end

      def self.rotation_axis_for_piece(network, piece)
        connected = connected_external_ports(network, piece)

        return nil if connected.empty?

        if connected.length == 1
          port = connected.first[:port]
          axis = port.outward_vector.clone

          return nil if axis.length <= EPSILON

          axis.normalize!

          return {
            pivot: port.point,
            axis: axis,
            connected: connected
          }
        end

        if connected.length == 2
          port_a = connected[0][:port]
          port_b = connected[1][:port]

          return nil unless connected_ports_are_inline?(port_a, port_b)

          axis = port_a.point.vector_to(port_b.point)
          return nil if axis.length <= EPSILON

          axis.normalize!

          return {
            pivot: port_a.point,
            axis: axis,
            connected: connected
          }
        end

        nil
      rescue => error
        puts "ConnectorSwingService.rotation_axis_for_piece failed: #{error.message}"
        nil
      end

      def self.connected_external_ports(network, piece)
        Array(piece.ports).map do |port|
          external = network.connected_ports(port).find do |other|
            other && other.piece != piece
          end

          external ? { port: port, external: external } : nil
        end.compact
      rescue
        []
      end

      def self.connected_ports_are_inline?(port_a, port_b)
        return false unless port_a && port_b
        return false unless port_a.point && port_b.point

        point_axis = port_a.point.vector_to(port_b.point)
        return false if point_axis.length <= EPSILON

        point_axis.normalize!

        vector_a = port_a.outward_vector.clone
        vector_b = port_b.outward_vector.clone

        return false if vector_a.length <= EPSILON
        return false if vector_b.length <= EPSILON

        vector_a.normalize!
        vector_b.normalize!

        return false unless vector_a.dot(vector_b) < -0.60

        aligned_a = vector_a.dot(point_axis).abs
        aligned_b = vector_b.dot(point_axis).abs

        aligned_a > 0.60 && aligned_b > 0.60
      rescue
        false
      end

      def self.rectangular_piece?(piece)
        Array(piece.ports).any? do |port|
          port && Model::Port.normalize_shape_value(port.shape) == :rectangular
        end
      rescue
        false
      end

      def self.dimensions_for_piece(piece)
        port = Array(piece.ports).find { |item| item && item.shape }
        return nil unless port

        Model::Port.dimensions_from_params({}, port)
      rescue
        nil
      end

      def self.current_side_axis_for_piece(piece, main_axis)
        center = piece_center(piece)
        main_axis = normalized(main_axis)
        return nil unless center && main_axis

        candidates = []

        Array(piece.ports).each do |port|
          next unless port && port.point

          from_center = center.vector_to(port.point)
          if from_center.length > EPSILON
            side = perpendicularized(from_center, main_axis)
            candidates << side if side
          end

          if port.outward_vector && port.outward_vector.length > EPSILON
            side = perpendicularized(port.outward_vector, main_axis)
            candidates << side if side
          end
        end

        candidates.compact.max_by(&:length)
      rescue
        nil
      end

      def self.preferred_height_axis_for_anchor(anchor_port, external_port, forward_axis, side_axis)
        perpendicularized(anchor_port.height_axis, forward_axis) ||
          perpendicularized(external_port && external_port.height_axis, forward_axis) ||
          begin
            axis = forward_axis.cross(side_axis)
            axis.normalize! if axis && axis.length > EPSILON
            axis
          end
      rescue
        nil
      end

      def self.rectangular_face_offset_for_direction(direction:, dimensions:, basis:)
        return 0.0 unless direction && dimensions && basis

        vector = direction.clone
        return 0.0 if vector.length <= EPSILON

        vector.normalize!

        width_dot = vector.dot(basis[:width_axis]).abs
        height_dot = vector.dot(basis[:height_axis]).abs

        if width_dot >= height_dot
          dimensions[:width].to_f / 2.0
        else
          dimensions[:height].to_f / 2.0
        end
      rescue
        0.0
      end

      def self.update_rectangular_port!(
        port,
        point:,
        vector:,
        dimensions:,
        direction:,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        basis = Geometry::RectangularFrame.basis_for_axis(
          direction,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )

        port.point = point
        port.vector = normalized(vector) || vector

        port.shape = :rectangular
        port.diameter = dimensions[:diameter]
        port.width = dimensions[:width]
        port.height = dimensions[:height]

        if basis
          port.width_axis = basis[:width_axis]
          port.height_axis = basis[:height_axis]
        end

        port
      rescue => error
        puts "ConnectorSwingService.update_rectangular_port! failed: #{error.message}"
        port
      end

      def self.free_ports_for_piece(piece, connected_ports)
        connected_ports = Array(connected_ports)

        Array(piece.ports).reject do |port|
          connected_ports.include?(port)
        end
      rescue
        []
      end

      def self.sort_ports_along_axis(ports, center, axis)
        axis = normalized(axis)
        return ports unless axis

        ports.sort_by do |port|
          center.vector_to(port.point).dot(axis)
        end
      rescue
        ports
      end

      def self.add_caps_to_free_ports(group, ports)
        Array(ports).each do |port|
          next unless port
          next unless port.point

          begin
            TeeInsertService.send(:add_cap_for_port, group, port)
          rescue
            nil
          end
        end
      rescue
        nil
      end

      def self.erase_group_geometry(group)
        return unless group && group.valid?

        entities = group.entities

        begin
          entities.clear!
          return
        rescue
          nil
        end

        entities.to_a.reverse_each do |entity|
          begin
            entity.erase! if entity && entity.valid?
          rescue
            nil
          end
        end
      rescue => error
        puts "ConnectorSwingService.erase_group_geometry failed: #{error.message}"
      end

      def self.midpoint(point_a, point_b)
        Geom::Point3d.new(
          (point_a.x + point_b.x) / 2.0,
          (point_a.y + point_b.y) / 2.0,
          (point_a.z + point_b.z) / 2.0
        )
      rescue
        nil
      end

      def self.perpendicularized(vector, axis)
        Geometry::VectorMath.perpendicularized(vector, axis, epsilon: EPSILON)
      end

      def self.fallback_perpendicular_axis(axis)
        Geometry::VectorMath.fallback_perpendicular_axis(axis, epsilon: EPSILON)
      end

      def self.normalized(vector)
        Geometry::VectorMath.normalized(vector, epsilon: EPSILON)
      end

      def self.transform_piece_ports(piece, transformation)
        Array(piece.ports).each do |port|
          port.point = port.point.transform(transformation) if port.point

          if port.vector
            transformed_vector = port.vector.transform(transformation)
            transformed_vector.normalize! if transformed_vector.length > EPSILON
            port.vector = transformed_vector
          end

          if port.width_axis
            transformed_width = port.width_axis.transform(transformation)
            transformed_width.normalize! if transformed_width.length > EPSILON
            port.width_axis = transformed_width
          end

          if port.height_axis
            transformed_height = port.height_axis.transform(transformation)
            transformed_height.normalize! if transformed_height.length > EPSILON
            port.height_axis = transformed_height
          end
        end
      rescue => error
        puts "ConnectorSwingService.transform_piece_ports failed: #{error.message}"
      end

      private_class_method :rotate_round_connector
      private_class_method :rebuild_rectangular_connector
      private_class_method :rebuild_rectangular_end_connector
      private_class_method :rebuild_rectangular_inline_connector
      private_class_method :rebuild_rectangular_end_tee
      private_class_method :rebuild_rectangular_end_cross
      private_class_method :rebuild_rectangular_end_wye
      private_class_method :rebuild_rectangular_inline_tee
      private_class_method :rebuild_rectangular_inline_cross
      private_class_method :picked_swingable_piece
      private_class_method :screen_distance_to_piece
      private_class_method :piece_center
      private_class_method :screen_distance
      private_class_method :rotation_axis_for_piece
      private_class_method :connected_external_ports
      private_class_method :connected_ports_are_inline?
      private_class_method :rectangular_piece?
      private_class_method :dimensions_for_piece
      private_class_method :current_side_axis_for_piece
      private_class_method :preferred_height_axis_for_anchor
      private_class_method :rectangular_face_offset_for_direction
      private_class_method :update_rectangular_port!
      private_class_method :free_ports_for_piece
      private_class_method :sort_ports_along_axis
      private_class_method :add_caps_to_free_ports
      private_class_method :erase_group_geometry
      private_class_method :midpoint
      private_class_method :perpendicularized
      private_class_method :fallback_perpendicular_axis
      private_class_method :normalized
      private_class_method :transform_piece_ports
    end
  end
end
