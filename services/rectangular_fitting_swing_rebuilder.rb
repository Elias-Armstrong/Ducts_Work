module DuctExtension
  module Services
    class RectangularFittingSwingRebuilder
      extend FittingRebuildSupport

      EPSILON = FittingRebuildSupport::EPSILON

      def self.rebuild(piece:, connected:, dimensions:, side_axis:)
        return false unless piece && piece.group && piece.group.valid?
        return false unless connected && !connected.empty?

        case connected.length
        when 1
          rebuild_rectangular_end_connector(
            piece: piece,
            connected: connected,
            dimensions: dimensions,
            side_axis: side_axis
          )
        when 2
          rebuild_rectangular_inline_connector(
            piece: piece,
            connected: connected,
            dimensions: dimensions,
            side_axis: side_axis
          )
        else
          false
        end
      rescue => error
        puts "RectangularFittingSwingRebuilder.rebuild failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
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
        puts "RectangularFittingSwingRebuilder.rebuild_rectangular_end_connector failed: #{error.message}"
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
        puts "RectangularFittingSwingRebuilder.rebuild_rectangular_inline_connector failed: #{error.message}"
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

        apply_rectangular_port_layout(
          piece: piece,
          fixed_ports: [anchor_port],
          fixed_specs: [
            port_spec(anchor_port.point, stem_into_tee, main_basis[:width_axis], main_basis[:height_axis])
          ],
          free_specs: [
            port_spec(left_point, side_axis.clone.reverse, forward_axis, height_axis),
            port_spec(right_point, side_axis, forward_axis, height_axis)
          ],
          dimensions: dimensions
        )
      rescue => error
        puts "RectangularFittingSwingRebuilder.rebuild_rectangular_end_tee failed: #{error.message}"
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

        apply_rectangular_port_layout(
          piece: piece,
          fixed_ports: [anchor_port],
          fixed_specs: [
            port_spec(anchor_port.point, stem_into_cross, side_axis, height_axis)
          ],
          free_specs: [
            port_spec(forward_point, forward_axis, side_axis, height_axis),
            port_spec(left_point, side_axis.clone.reverse, forward_axis, height_axis),
            port_spec(right_point, side_axis, forward_axis, height_axis)
          ],
          dimensions: dimensions
        )
      rescue => error
        puts "RectangularFittingSwingRebuilder.rebuild_rectangular_end_cross failed: #{error.message}"
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
        if side_takeoff_wye?(piece, anchor_port, forward_axis)
          return rebuild_rectangular_side_takeoff_wye(
            piece: piece,
            anchor_port: anchor_port,
            dimensions: dimensions,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis
          )
        end

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

        apply_rectangular_port_layout(
          piece: piece,
          fixed_ports: [anchor_port],
          fixed_specs: [
            port_spec(anchor_port.point, stem_into_wye, side_axis, height_axis)
          ],
          free_specs: [
            port_spec(forward_point, forward_axis, side_axis, height_axis),
            port_spec(branch_point, branch_axis, branch_width_axis, branch_height_axis)
          ],
          dimensions: dimensions
        )
      rescue => error
        puts "RectangularFittingSwingRebuilder.rebuild_rectangular_end_wye failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.side_takeoff_wye?(piece, anchor_port, forward_axis)
        free_ports = Array(piece.ports).compact.reject { |port| port == anchor_port }
        branch_port = free_ports.min_by do |port|
          vector = Geometry::VectorMath.normalized(port.outward_vector)
          vector ? vector.dot(forward_axis).abs : 1.0
        end
        return false unless branch_port

        branch_vector = Geometry::VectorMath.normalized(branch_port.outward_vector)
        branch_vector && branch_vector.dot(forward_axis).abs < 0.20
      rescue
        false
      end
      private_class_method :side_takeoff_wye?

      def self.rebuild_rectangular_side_takeoff_wye(
        piece:,
        anchor_port:,
        dimensions:,
        forward_axis:,
        side_axis:,
        height_axis:
      )
        main_depth = Geometry::RectangularTeeBuilder.socket_depth(
          dimensions[:width],
          dimensions[:height]
        )
        branch_depth = Geometry::RectangularTeeBuilder.side_takeoff_branch_depth(
          dimensions[:width],
          dimensions[:height]
        )

        center = anchor_port.point.offset(forward_axis, main_depth)
        branch_axis = side_axis.clone
        branch_axis.normalize!

        main_basis = {
          width_axis: side_axis,
          height_axis: height_axis
        }

        face_offset = rectangular_face_offset_for_direction(
          direction: branch_axis,
          dimensions: dimensions,
          basis: main_basis
        )
        branch_base = center.offset(branch_axis, face_offset)

        success = Geometry::RectangularTeeBuilder.build_into(
          piece.group,
          center,
          branch_base,
          forward_axis,
          branch_axis,
          dimensions[:width],
          dimensions[:height],
          main_depth,
          branch_depth: branch_depth,
          preferred_main_width_axis: side_axis,
          preferred_main_height_axis: height_axis
        )
        return false unless success

        branch_basis = Geometry::RectangularTeeBuilder.branch_basis(
          forward_axis,
          branch_axis,
          main_basis: main_basis
        )
        return false unless branch_basis

        stem_into_wye = forward_axis.clone.reverse
        forward_point = center.offset(forward_axis, main_depth)
        branch_point = branch_base.offset(branch_axis, branch_depth)

        apply_rectangular_port_layout(
          piece: piece,
          fixed_ports: [anchor_port],
          fixed_specs: [
            port_spec(anchor_port.point, stem_into_wye, side_axis, height_axis)
          ],
          free_specs: [
            port_spec(forward_point, forward_axis, side_axis, height_axis),
            port_spec(
              branch_point,
              branch_axis,
              branch_basis[:width_axis],
              branch_basis[:height_axis]
            )
          ],
          dimensions: dimensions
        )
      rescue => error
        puts "RectangularFittingSwingRebuilder.rebuild_rectangular_side_takeoff_wye failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end
      private_class_method :rebuild_rectangular_side_takeoff_wye

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

        apply_rectangular_port_layout(
          piece: piece,
          fixed_ports: [negative_main, positive_main],
          fixed_specs: [
            port_spec(center.offset(main_axis.clone.reverse, socket_depth), main_axis.clone.reverse, side_axis, height_axis),
            port_spec(center.offset(main_axis, socket_depth), main_axis, side_axis, height_axis)
          ],
          free_specs: [
            port_spec(branch_point, side_axis, main_axis, height_axis)
          ],
          dimensions: dimensions
        )
      rescue => error
        puts "RectangularFittingSwingRebuilder.rebuild_rectangular_inline_tee failed: #{error.message}"
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

        apply_rectangular_port_layout(
          piece: piece,
          fixed_ports: [negative_main, positive_main],
          fixed_specs: [
            port_spec(center.offset(main_axis.clone.reverse, socket_depth), main_axis.clone.reverse, side_axis, height_axis),
            port_spec(center.offset(main_axis, socket_depth), main_axis, side_axis, height_axis)
          ],
          free_specs: [
            port_spec(left_point, side_axis.clone.reverse, main_axis, height_axis),
            port_spec(right_point, side_axis, main_axis, height_axis)
          ],
          dimensions: dimensions
        )
      rescue => error
        puts "RectangularFittingSwingRebuilder.rebuild_rectangular_inline_cross failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.port_spec(point, vector, width_axis, height_axis, direction = nil)
        {
          point: point,
          vector: vector,
          direction: direction || vector,
          preferred_width_axis: width_axis,
          preferred_height_axis: height_axis
        }
      end

      def self.apply_rectangular_port_layout(piece:, fixed_ports:, fixed_specs:, free_specs:, dimensions:)
        free_ports = free_ports_for_piece(piece, fixed_ports)
        return false if free_ports.length < free_specs.length

        Array(fixed_ports).zip(Array(fixed_specs)).each do |port, spec|
          apply_rectangular_port_spec(port, spec, dimensions)
        end

        Array(free_specs).each_with_index do |spec, index|
          apply_rectangular_port_spec(free_ports[index], spec, dimensions)
        end

        add_caps_to_free_ports(piece.group, free_ports)
        true
      end

      def self.apply_rectangular_port_spec(port, spec, dimensions)
        update_rectangular_port!(
          port,
          point: spec[:point],
          vector: spec[:vector],
          dimensions: dimensions,
          direction: spec[:direction],
          preferred_width_axis: spec[:preferred_width_axis],
          preferred_height_axis: spec[:preferred_height_axis]
        )
      end

    end
  end
end
