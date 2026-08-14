module DuctExtension
  module Services
    class ConnectorSwingService
      PICK_RADIUS_PIXELS = 44
      DRAG_START_PIXELS = 4.0
      DRAG_SNAP_DEGREES = 15
      DRAG_SAMPLE_COUNT = 360 / DRAG_SNAP_DEGREES

      EPSILON = 0.000001
      ROUND_SWING_ANGLE = 45.degrees
      RECTANGULAR_SWING_ANGLE = 90.degrees
      DRAG_SNAP_ANGLE = DRAG_SNAP_DEGREES.degrees

      SWINGABLE_TYPES = [
        :tee,
        :cross,
        :wye
      ].freeze

      SwingSession = Struct.new(
        :model,
        :network,
        :piece,
        :axis_data,
        :dimensions,
        :rectangular,
        :initial_side,
        :drag_reference,
        :drag_radius,
        :start_x,
        :start_y,
        :current_angle,
        :dragged,
        :dependent_pieces,
        :operation,
        keyword_init: true
      )

      # Legacy one-click behavior remains available for callers outside
      # DuctTool. DuctTool itself now uses begin_drag/update_drag/finish_drag.
      def self.swing_at_click(model:, network:, view:, x:, y:, angle: nil)
        result = begin_drag(
          model: model,
          network: network,
          view: view,
          x: x,
          y: y
        )
        return result unless result[:status] == :ok

        session = result[:session]
        target_angle = angle || default_click_angle(session)
        applied = apply_absolute_angle(session, target_angle)

        unless applied
          cancel_drag(session)
          return { status: :failed, piece: session.piece }
        end

        session.dragged = true
        finish_drag(session, legacy_click: false)
      rescue => error
        puts "ConnectorSwingService.swing_at_click failed: #{error.message}"
        puts error.backtrace.join("\n")
        cancel_drag(session) if defined?(session) && session
        { status: :failed }
      end

      # Prepare an interactive Ctrl-drag. No geometry moves until the cursor
      # crosses DRAG_START_PIXELS, so a simple Ctrl-click can still use the
      # original 45/90-degree step on mouse-up.
      def self.begin_drag(model:, network:, view:, x:, y:)
        return { status: :failed } unless model && network && view

        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        piece = picked_swingable_piece(
          network: network,
          view: view,
          x: x,
          y: y
        )
        return { status: :no_piece } unless piece

        if Catalog::Manager.catalog_locked_piece?(piece)
          return { status: :catalog_locked, piece: piece }
        end

        unless SWINGABLE_TYPES.include?(piece.type.to_sym)
          return { status: :not_swingable, piece: piece }
        end

        dependent_pieces = terminal_transition_dependencies(network, piece)
        axis_data = rotation_axis_for_piece(
          network,
          piece,
          ignored_pieces: dependent_pieces
        )
        return { status: :too_many_connections, piece: piece } unless axis_data

        pivot = axis_data[:pivot]
        axis = Geometry::VectorMath.normalized(axis_data[:axis], epsilon: EPSILON)
        return { status: :failed, piece: piece } unless pivot && axis

        rectangular = rectangular_piece?(piece)
        dimensions = rectangular ? dimensions_for_piece(piece) : nil
        return { status: :failed, piece: piece } if rectangular && !dimensions

        initial_side = swing_side_axis_for_piece(piece, axis_data.merge(axis: axis))
        initial_side ||= Geometry::VectorMath.fallback_perpendicular_axis(axis, epsilon: EPSILON)
        return { status: :failed, piece: piece } unless initial_side

        initial_side.normalize!

        drag_reference = reference_axis_nearest_cursor(
          view: view,
          pivot: pivot,
          axis: axis,
          reference: initial_side,
          radius: drag_radius_for_piece(piece, pivot, axis, dimensions),
          x: x,
          y: y
        )
        drag_reference ||= initial_side.clone

        drag_radius = drag_radius_for_piece(piece, pivot, axis, dimensions)

        operation = ModelOperation.new(
          model: model,
          network: network,
          name: "Swing Duct Connector"
        )
        operation.start!

        session = SwingSession.new(
          model: model,
          network: network,
          piece: piece,
          axis_data: axis_data.merge(axis: axis),
          dimensions: dimensions,
          rectangular: rectangular,
          initial_side: initial_side,
          drag_reference: drag_reference,
          drag_radius: drag_radius,
          start_x: x.to_f,
          start_y: y.to_f,
          current_angle: 0.0,
          dragged: false,
          dependent_pieces: dependent_pieces,
          operation: operation
        )

        {
          status: :ok,
          session: session,
          piece: piece,
          angle: 0.0,
          angle_degrees: 0
        }
      rescue => error
        puts "ConnectorSwingService.begin_drag failed: #{error.message}"
        puts error.backtrace.join("\n")
        operation.rollback! if defined?(operation) && operation
        { status: :failed }
      end

      def self.update_drag(session:, view:, x:, y:)
        return { status: :failed } unless session && view

        unless session.dragged
          distance = screen_distance_xy(session.start_x, session.start_y, x, y)
          return angle_result(session) if distance < DRAG_START_PIXELS

          session.dragged = true
        end

        angle = snapped_angle_for_cursor(session, view, x, y)
        return angle_result(session) unless angle

        if shortest_angle_delta(session.current_angle, angle).abs >= (DRAG_SNAP_ANGLE * 0.5)
          success = apply_absolute_angle(session, angle)
          unless success
            cancel_drag(session)
            return { status: :failed, piece: session.piece }
          end
        end

        angle_result(session)
      rescue => error
        puts "ConnectorSwingService.update_drag failed: #{error.message}"
        puts error.backtrace.join("\n")
        cancel_drag(session)
        { status: :failed }
      end

      def self.finish_drag(session, legacy_click: true)
        return { status: :failed } unless session

        if legacy_click && !session.dragged
          success = apply_absolute_angle(session, default_click_angle(session))
          unless success
            cancel_drag(session)
            return { status: :failed, piece: session.piece }
          end
        end

        PieceMetadataService.save_piece(session.piece)
        Array(session.dependent_pieces).each { |piece| PieceMetadataService.save_piece(piece) }
        result = angle_result(session).merge(status: :ok)
        session.operation.commit!(result)
      rescue => error
        puts "ConnectorSwingService.finish_drag failed: #{error.message}"
        puts error.backtrace.join("\n")
        cancel_drag(session)
        { status: :failed }
      end

      def self.cancel_drag(session)
        return { status: :cancelled } unless session

        session.operation.rollback! if session.operation
        { status: :cancelled }
      rescue => error
        puts "ConnectorSwingService.cancel_drag failed: #{error.message}"
        { status: :failed }
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
        return nil unless screen_point

        screen_distance_xy(screen_point.x, screen_point.y, x, y)
      rescue
        nil
      end

      def self.screen_distance_xy(x1, y1, x2, y2)
        dx = x1.to_f - x2.to_f
        dy = y1.to_f - y2.to_f
        Math.sqrt(dx * dx + dy * dy)
      rescue
        0.0
      end

      def self.rotation_axis_for_piece(network, piece, ignored_pieces: [])
        connected = connected_external_ports(network, piece, ignored_pieces: ignored_pieces)
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

      def self.connected_external_ports(network, piece, ignored_pieces: [])
        Array(piece.ports).map do |port|
          external = network.connected_ports(port).find do |other|
            other &&
              other.piece != piece &&
              !Array(ignored_pieces).include?(other.piece)
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
          port && Model::DuctDimensions.normalize_shape(port.shape) == :rectangular
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


      def self.swing_side_axis_for_piece(piece, axis_data)
        axis = Geometry::VectorMath.normalized(axis_data[:axis], epsilon: EPSILON)
        pivot = axis_data[:pivot]
        connected_ports = Array(axis_data[:connected]).map { |entry| entry[:port] }
        return nil unless axis && pivot

        candidates = Array(piece.ports).filter_map do |port|
          next unless port && port.point
          next if connected_ports.include?(port)

          vector = pivot.vector_to(port.point)
          amount = vector.dot(axis)
          radial = Geom::Vector3d.new(
            vector.x - axis.x * amount,
            vector.y - axis.y * amount,
            vector.z - axis.z * amount
          )
          next if radial.length <= EPSILON

          length = radial.length
          radial.normalize!
          [radial, length]
        end

        best = candidates.max_by { |entry| entry[1] }
        best ? best[0] : current_side_axis_for_piece(piece, axis)
      rescue
        current_side_axis_for_piece(piece, axis_data[:axis])
      end

      def self.current_side_axis_for_piece(piece, main_axis)
        center = piece_center(piece)
        main_axis = Geometry::VectorMath.normalized(main_axis, epsilon: EPSILON)
        return nil unless center && main_axis

        candidates = []

        Array(piece.ports).each do |port|
          next unless port && port.point

          from_center = center.vector_to(port.point)
          if from_center.length > EPSILON
            side = Geometry::VectorMath.perpendicularized(from_center, main_axis, epsilon: EPSILON)
            candidates << side if side
          end

          if port.outward_vector && port.outward_vector.length > EPSILON
            side = Geometry::VectorMath.perpendicularized(port.outward_vector, main_axis, epsilon: EPSILON)
            candidates << side if side
          end
        end

        candidates.compact.first
      rescue
        nil
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

      def self.terminal_transition_dependencies(network, piece)
        Array(piece.ports).filter_map do |port|
          external = network.connected_ports(port).find do |other|
            other && other.piece && other.piece != piece
          end
          next unless external

          transition_piece = external.piece
          next unless transition_piece.type.to_sym == :reducer

          outer_port = Array(transition_piece.ports).find { |candidate| candidate != external }
          next unless outer_port

          outer_connected = network.connected_ports(outer_port).any? do |other|
            other && other.piece != transition_piece
          end
          next if outer_connected

          transition_piece
        end.uniq
      rescue
        []
      end
      private_class_method :terminal_transition_dependencies

      def self.transform_dependent_pieces(pieces, transformation)
        Array(pieces).each do |piece|
          next unless piece && piece.group && piece.group.valid?

          piece.group.transform!(transformation)
          transform_piece_ports(piece, transformation)
        end
      rescue => error
        puts "ConnectorSwingService.transform_dependent_pieces failed: #{error.message}"
      end
      private_class_method :transform_dependent_pieces

      def self.remove_caps_from_connected_ports(network, piece)
        Array(piece.ports).each do |port|
          next unless network.connected_ports(port).any? { |other| other && other.piece != piece }

          PortCapService.remove(port)
        end
      rescue => error
        puts "ConnectorSwingService.remove_caps_from_connected_ports failed: #{error.message}"
      end
      private_class_method :remove_caps_from_connected_ports

      def self.default_click_angle(session)
        session.rectangular ? RECTANGULAR_SWING_ANGLE : ROUND_SWING_ANGLE
      end

      def self.apply_absolute_angle(session, target_angle)
        target_angle = normalize_angle(target_angle)
        delta = shortest_angle_delta(session.current_angle, target_angle)
        return true if delta.abs <= EPSILON

        if session.rectangular
          rotation = Geom::Transformation.rotation(
            session.axis_data[:pivot],
            session.axis_data[:axis],
            target_angle
          )
          new_side = session.initial_side.transform(rotation)
          return false if new_side.length <= EPSILON

          new_side.normalize!
          success = FittingRebuildService.swing_rectangular(
            piece: session.piece,
            connected: session.axis_data[:connected],
            dimensions: session.dimensions,
            side_axis: new_side
          )
          return false unless success
        else
          transformation = Geom::Transformation.rotation(
            session.axis_data[:pivot],
            session.axis_data[:axis],
            delta
          )
          session.piece.group.transform!(transformation)
          transform_piece_ports(session.piece, transformation)
        end

        dependency_rotation = Geom::Transformation.rotation(
          session.axis_data[:pivot],
          session.axis_data[:axis],
          delta
        )
        transform_dependent_pieces(session.dependent_pieces, dependency_rotation)
        remove_caps_from_connected_ports(session.network, session.piece)

        session.current_angle = target_angle
        true
      rescue => error
        puts "ConnectorSwingService.apply_absolute_angle failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.snapped_angle_for_cursor(session, view, x, y)
        pivot = session.axis_data[:pivot]
        axis = session.axis_data[:axis]
        reference = session.drag_reference
        radius = session.drag_radius
        return nil unless pivot && axis && reference && radius

        best = nil

        DRAG_SAMPLE_COUNT.times do |index|
          angle = index * DRAG_SNAP_ANGLE
          rotation = Geom::Transformation.rotation(pivot, axis, angle)
          direction = reference.transform(rotation)
          next if direction.length <= EPSILON

          direction.normalize!
          world_point = pivot.offset(direction, radius)
          screen_point = view.screen_coords(world_point)
          next unless screen_point

          distance = screen_distance(screen_point, x, y)
          next unless distance

          if !best || distance < best[:distance]
            best = { angle: angle, distance: distance }
          end
        end

        best && best[:angle]
      rescue => error
        puts "ConnectorSwingService.snapped_angle_for_cursor failed: #{error.message}"
        nil
      end

      def self.drag_radius_for_piece(piece, pivot, axis, dimensions = nil)
        radial = Array(piece.ports).filter_map do |port|
          next unless port && port.point

          vector = pivot.vector_to(port.point)
          amount = vector.dot(axis)
          perpendicular = Geom::Vector3d.new(
            vector.x - axis.x * amount,
            vector.y - axis.y * amount,
            vector.z - axis.z * amount
          )
          perpendicular.length if perpendicular.length > EPSILON
        end

        radius = radial.max

        if (!radius || radius <= EPSILON) && dimensions
          radius = [dimensions[:diameter], dimensions[:width], dimensions[:height]].compact.map(&:to_f).max
        end

        radius = 12.0 unless radius && radius > EPSILON
        [radius, 1.0].max
      rescue
        12.0
      end

      def self.reference_axis_nearest_cursor(view:, pivot:, axis:, reference:, radius:, x:, y:)
        candidates = [reference.clone, reference.clone.reverse]

        candidates.min_by do |candidate|
          world_point = pivot.offset(candidate, radius)
          screen_point = view.screen_coords(world_point)
          screen_point ? screen_distance(screen_point, x, y) : Float::INFINITY
        end
      rescue
        reference
      end

      def self.normalize_angle(angle)
        full = 2.0 * Math::PI
        value = angle.to_f % full
        value += full if value < 0.0
        value
      end

      def self.shortest_angle_delta(from_angle, to_angle)
        full = 2.0 * Math::PI
        half = Math::PI
        delta = (to_angle.to_f - from_angle.to_f) % full
        delta -= full if delta > half
        delta
      end

      def self.display_angle_degrees(angle)
        degrees = normalize_angle(angle) * 180.0 / Math::PI
        degrees -= 360.0 if degrees > 180.0
        degrees.round
      end

      def self.angle_result(session)
        {
          status: :ok,
          piece: session.piece,
          angle: session.current_angle,
          angle_degrees: display_angle_degrees(session.current_angle),
          dragged: session.dragged
        }
      end

      private_class_method :screen_distance_to_piece
      private_class_method :piece_center
      private_class_method :screen_distance
      private_class_method :screen_distance_xy
      private_class_method :rotation_axis_for_piece
      private_class_method :connected_external_ports
      private_class_method :connected_ports_are_inline?
      private_class_method :rectangular_piece?
      private_class_method :dimensions_for_piece
      private_class_method :swing_side_axis_for_piece
      private_class_method :current_side_axis_for_piece
      private_class_method :transform_piece_ports
      private_class_method :default_click_angle
      private_class_method :apply_absolute_angle
      private_class_method :snapped_angle_for_cursor
      private_class_method :drag_radius_for_piece
      private_class_method :reference_axis_nearest_cursor
      private_class_method :normalize_angle
      private_class_method :shortest_angle_delta
      private_class_method :display_angle_degrees
      private_class_method :angle_result
    end
  end
end
