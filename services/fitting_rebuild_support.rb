module DuctExtension
  module Services
    module FittingRebuildSupport
      EPSILON = 0.000001

      def normalized(vector)
        Geometry::VectorMath.normalized(vector, epsilon: EPSILON)
      end

      def perpendicularized(vector, axis)
        Geometry::VectorMath.perpendicularized(vector, axis, epsilon: EPSILON)
      end

      def fallback_perpendicular_axis(axis)
        Geometry::VectorMath.fallback_perpendicular_axis(axis, epsilon: EPSILON)
      end

      def erase_group_geometry(group)
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
        puts "FittingRebuildSupport.erase_group_geometry failed: #{error.message}"
      end

      def midpoint(point_a, point_b)
        Geometry::PrimitiveHelpers.midpoint(point_a, point_b)
      end

      def average_point(points)
        points = Array(points).compact
        return nil if points.empty?

        Geom::Point3d.new(
          points.map(&:x).sum / points.length.to_f,
          points.map(&:y).sum / points.length.to_f,
          points.map(&:z).sum / points.length.to_f
        )
      rescue
        nil
      end

      def tee_port_layout(ports)
        pair = most_opposite_pair(ports)
        return [nil, nil, nil] unless pair

        branch = ports.find { |port| port != pair[0] && port != pair[1] }
        [pair[0], pair[1], branch]
      rescue
        [nil, nil, nil]
      end

      def cross_port_layout(ports)
        first_pair = most_opposite_pair(ports)
        return [nil, nil] unless first_pair

        remaining = ports.reject { |port| port == first_pair[0] || port == first_pair[1] }
        return [nil, nil] unless remaining.length >= 2

        second_pair = most_opposite_pair(remaining) || [remaining[0], remaining[1]]
        [first_pair, second_pair]
      rescue
        [nil, nil]
      end

      def most_opposite_pair(ports)
        pairs = []

        Array(ports).combination(2) do |a, b|
          next unless a && b && a.outward_vector && b.outward_vector

          va = normalized(a.outward_vector)
          vb = normalized(b.outward_vector)
          next unless va && vb

          distance = a.point && b.point ? a.point.distance(b.point) : 0.0
          pairs << {
            pair: [a, b],
            score: (-va.dot(vb) * 1000.0) + distance
          }
        end

        pairs.max_by { |entry| entry[:score] }&.dig(:pair)
      rescue
        nil
      end

      def free_ports_for_piece(piece, connected_ports)
        connected_ports = Array(connected_ports)
        Array(piece.ports).reject { |port| connected_ports.include?(port) }
      rescue
        []
      end

      def sort_ports_along_axis(ports, center, axis)
        axis = normalized(axis)
        return ports unless axis

        Array(ports).sort_by { |port| center.vector_to(port.point).dot(axis) }
      rescue
        ports
      end

      def add_caps_to_free_ports(group, ports)
        Array(ports).each do |port|
          next unless port && port.point

          begin
            DuctExtension::Services::PortCapService.add(group, port)
          rescue
            nil
          end
        end
      rescue
        nil
      end

      def update_port_dimensions!(
        port,
        dimensions,
        direction:,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        port.dimensions = dimensions

        vector = normalized(direction) || direction
        port.vector = vector

        if dimensions[:shape] == :rectangular
          basis = Geometry::RectangularFrame.basis_for_axis(
            vector,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )

          if basis
            port.width_axis = basis[:width_axis]
            port.height_axis = basis[:height_axis]
          end
        else
          port.width_axis = nil
          port.height_axis = nil
        end

        port
      rescue => error
        puts "FittingRebuildSupport.update_port_dimensions! failed: #{error.message}"
        port
      end

      def update_rectangular_port!(
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
        port.dimensions = dimensions

        if basis
          port.width_axis = basis[:width_axis]
          port.height_axis = basis[:height_axis]
        end

        port
      rescue => error
        puts "FittingRebuildSupport.update_rectangular_port! failed: #{error.message}"
        port
      end

      def update_fitting_port_dimensions!(ports:, center:, dimensions:)
        Array(ports).each do |port|
          next unless port && port.point

          direction = center.vector_to(port.point)
          direction = port.outward_vector.clone if direction.length <= EPSILON && port.outward_vector
          next if direction.length <= EPSILON

          update_port_dimensions!(
            port,
            dimensions,
            direction: direction,
            preferred_width_axis: port.width_axis,
            preferred_height_axis: port.height_axis
          )
        end
      rescue => error
        puts "FittingRebuildSupport.update_fitting_port_dimensions! failed: #{error.message}"
      end

      def fitting_rectangular_basis_for_axis(axis, dimensions, port_a = nil, port_b = nil)
        preferred_width_axis = port_a&.width_axis || port_b&.width_axis
        preferred_height_axis = port_a&.height_axis || port_b&.height_axis

        if Geometry::RectangularFrame.respond_to?(:stable_basis_for_axis)
          Geometry::RectangularFrame.stable_basis_for_axis(
            axis,
            dimensions[:width],
            dimensions[:height],
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis,
            allow_relevel: false
          )
        else
          Geometry::RectangularFrame.basis_for_axis(
            axis,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )
        end
      rescue
        Geometry::RectangularFrame.basis_for_axis(axis)
      end

      def preferred_height_axis_for_anchor(anchor_port, external_port, forward_axis, side_axis)
        perpendicularized(anchor_port.height_axis, forward_axis) ||
          perpendicularized(external_port && external_port.height_axis, forward_axis) ||
          begin
            axis = forward_axis.cross(side_axis)
            normalized(axis)
          end
      rescue
        nil
      end

      def rectangular_face_offset_for_direction(direction:, dimensions:, basis:)
        return 0.0 unless direction && dimensions && basis

        vector = normalized(direction)
        return 0.0 unless vector

        width_dot = vector.dot(basis[:width_axis]).abs
        height_dot = vector.dot(basis[:height_axis]).abs

        width_dot >= height_dot ? dimensions[:width].to_f / 2.0 : dimensions[:height].to_f / 2.0
      rescue
        0.0
      end

      def box_point(center, axis_a, axis_b, axis_c, amount_a, amount_b, amount_c)
        Geom::Point3d.new(
          center.x + axis_a.x * amount_a + axis_b.x * amount_b + axis_c.x * amount_c,
          center.y + axis_a.y * amount_a + axis_b.y * amount_b + axis_c.y * amount_c,
          center.z + axis_a.z * amount_a + axis_b.z * amount_b + axis_c.z * amount_c
        )
      end

      def add_visible_edge(entities, point_a, point_b)
        Geometry::PrimitiveHelpers.add_visible_edge(
          entities,
          point_a,
          point_b,
          min_distance: EPSILON
        )
      end
    end
  end
end
