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

        ModelOperation.run(
          model: model,
          network: network,
          name: "Swing Round Duct Connector"
        ) do
          transformation = Geom::Transformation.rotation(
            pivot,
            axis,
            ROUND_SWING_ANGLE
          )

          piece.group.transform!(transformation)
          transform_piece_ports(piece, transformation)
          PieceMetadataService.save_piece(piece)

          {
            status: :ok,
            piece: piece,
            angle: ROUND_SWING_ANGLE,
            angle_degrees: 45
          }
        end
      rescue => error
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
        current_side ||= Geometry::VectorMath.fallback_perpendicular_axis(axis, epsilon: EPSILON)

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

        ModelOperation.run(
          model: model,
          network: network,
          name: "Rebuild Rectangular Duct Connector"
        ) do |operation|
          success = FittingRebuildService.swing_rectangular(
            piece: piece,
            connected: connected,
            dimensions: dimensions,
            side_axis: new_side
          )

          operation.abort!({ status: :failed, piece: piece }) unless success
          PieceMetadataService.save_piece(piece)

          {
            status: :ok,
            piece: piece,
            angle: RECTANGULAR_SWING_ANGLE,
            angle_degrees: 90
          }
        end
      rescue => error
        puts "ConnectorSwingService.rebuild_rectangular_connector failed: #{error.message}"
        puts error.backtrace.join("\n")

        {
          status: :failed,
          piece: piece
        }
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

        candidates.compact.max_by(&:length)
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

      private_class_method :rotate_round_connector
      private_class_method :rebuild_rectangular_connector
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
      private_class_method :transform_piece_ports
    end
  end
end
