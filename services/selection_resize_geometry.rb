# ===== Consolidated from: services/selection_resize_layout_service.rb =====
module DuctExtension
  module Services
    class SelectionResizeLayoutService
      EPSILON = 0.000001
      CONNECTION_TOLERANCE = 0.05

      def self.adjust_selected_layout_for_size_change!(
        network:,
        selected_pieces:,
        selected_set:,
        old_dimensions_by_piece:,
        target_dimensions:
      )
        moved_points = {}

        selected_pieces.each do |piece|
          next unless piece && piece.type.to_sym == :elbow

          old_dimensions = old_dimensions_by_piece[piece.object_id]
          next unless old_dimensions

          delta = target_dimensions.largest.to_f - Model::DuctDimensions.coerce(old_dimensions).largest.to_f
          next if delta.abs <= EPSILON

          offset = delta / 2.0
          Array(piece.ports).each do |port|
            next unless port && port.point && port.outward_vector

            direction = Geometry::VectorMath.normalized(port.outward_vector, epsilon: EPSILON)
            next unless direction

            new_point = port.point.offset(direction, offset)
            port.point = new_point
            moved_points[port.object_id] = new_point
          end
        end

        propagate_selected_port_movements!(
          network: network,
          selected_set: selected_set,
          moved_points: moved_points
        )
      rescue => error
        puts "SelectionResizeLayoutService.adjust_selected_layout_for_size_change! failed: #{error.message}"
        puts error.backtrace.join("\n")
      end

      def self.selected_boundary_connections(network, selected_pieces)
        selected_set = selected_pieces.each_with_object({}) { |piece, hash| hash[piece.object_id] = true }

        network.connections.select do |connection|
          piece_a = connection.port_a&.piece
          piece_b = connection.port_b&.piece
          next false unless piece_a && piece_b
          next false if piece_a == piece_b

          !!selected_set[piece_a.object_id] != !!selected_set[piece_b.object_id]
        end
      rescue
        []
      end

      def self.build_boundary_plan(boundary_connections:, selected_set:, target_dimensions:)
        boundary_connections.map do |connection|
          port_a = connection.port_a
          port_b = connection.port_b
          selected_port = selected_set[port_a.piece.object_id] ? port_a : port_b
          external_port = selected_port.equal?(port_a) ? port_b : port_a
          external_dimensions = SelectionResizePlanner.dimensions_for_port(external_port)

          {
            connection: connection,
            selected_port: selected_port,
            external_port: external_port,
            external_dimensions: external_dimensions,
            reducer_length: Geometry::ReducerBuilder.default_length(external_dimensions, target_dimensions)
          }
        end
      rescue
        []
      end

      def self.apply_boundary_pullbacks!(boundary_plan)
        boundary_plan.each do |item|
          selected_port = item[:selected_port]
          external_port = item[:external_port]
          length = item[:reducer_length].to_f
          next unless selected_port && external_port && selected_port.point && external_port.point
          next if length <= EPSILON

          axis = boundary_reducer_axis(selected_port: selected_port, external_port: external_port)
          next unless axis

          selected_port.point = external_port.point.offset(axis, length)
          selected_port.vector = axis.clone.reverse
        end
      rescue => error
        puts "SelectionResizeLayoutService.apply_boundary_pullbacks! failed: #{error.message}"
        puts error.backtrace.join("\n")
      end

      def self.insert_boundary_reducer!(
        model:,
        network:,
        selected_port:,
        external_port:,
        selected_dimensions:,
        external_dimensions:
      )
        return nil unless selected_port && external_port && selected_port.point && external_port.point

        network.disconnect_ports(selected_port, external_port)
        PortCapService.remove(selected_port)
        PortCapService.remove(external_port)

        start_point = external_port.point
        end_point = selected_port.point
        vector = Geometry::VectorMath.normalized(start_point.vector_to(end_point), epsilon: EPSILON)
        return nil unless vector

        group = model.active_entities.add_group
        group.name = selected_dimensions[:shape] == :rectangular ?
          "Auto Rectangular Duct Increaser / Reducer" :
          "Auto Round Duct Increaser / Reducer"

        preferred_start_width_axis = external_port.width_axis || selected_port.width_axis
        preferred_start_height_axis = external_port.height_axis || selected_port.height_axis
        preferred_end_width_axis = selected_port.width_axis || external_port.width_axis
        preferred_end_height_axis = selected_port.height_axis || external_port.height_axis

        success = Geometry::ReducerBuilder.build_into(
          group,
          start_point,
          end_point,
          start_dimensions: external_dimensions,
          end_dimensions: selected_dimensions,
          preferred_width_axis: preferred_start_width_axis,
          preferred_height_axis: preferred_start_height_axis
        )

        unless success
          group.erase! if group.valid?
          return nil
        end

        start_basis = rectangular_basis(
          dimensions: external_dimensions,
          direction: vector,
          width_axis: preferred_start_width_axis,
          height_axis: preferred_start_height_axis
        )
        end_basis = rectangular_basis(
          dimensions: selected_dimensions,
          direction: vector,
          width_axis: preferred_end_width_axis,
          height_axis: preferred_end_height_axis
        )

        reducer_start_port = Model::Port.new(
          point: start_point,
          vector: vector.clone.reverse,
          diameter: external_dimensions[:diameter],
          shape: external_dimensions[:shape],
          width: external_dimensions[:width],
          height: external_dimensions[:height],
          width_axis: start_basis && start_basis[:width_axis],
          height_axis: start_basis && start_basis[:height_axis]
        )

        reducer_end_port = Model::Port.new(
          point: end_point,
          vector: vector,
          diameter: selected_dimensions[:diameter],
          shape: selected_dimensions[:shape],
          width: selected_dimensions[:width],
          height: selected_dimensions[:height],
          width_axis: end_basis && end_basis[:width_axis],
          height_axis: end_basis && end_basis[:height_axis]
        )

        reducer_piece = Model::DuctPiece.new(
          type: :reducer,
          group: group,
          ports: [reducer_start_port, reducer_end_port]
        )

        network.add_piece(reducer_piece)
        network.connect_ports(external_port, reducer_start_port)
        network.connect_ports(reducer_end_port, selected_port)
        PieceMetadataService.save_piece(reducer_piece)
        reducer_piece
      rescue => error
        puts "SelectionResizeLayoutService.insert_boundary_reducer! failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.propagate_selected_port_movements!(network:, selected_set:, moved_points:)
        return if moved_points.empty?

        50.times do
          changed = false

          network.connections.each do |connection|
            port_a = connection.port_a
            port_b = connection.port_b
            next unless port_a && port_b && port_a.piece && port_b.piece
            next unless selected_set[port_a.piece.object_id] && selected_set[port_b.piece.object_id]

            a_moved = moved_points[port_a.object_id]
            b_moved = moved_points[port_b.object_id]

            if a_moved && !b_moved
              port_b.point = a_moved
              moved_points[port_b.object_id] = a_moved
              changed = true
            elsif b_moved && !a_moved
              port_a.point = b_moved
              moved_points[port_a.object_id] = b_moved
              changed = true
            elsif a_moved && b_moved && a_moved.distance(b_moved) > CONNECTION_TOLERANCE
              shared_midpoint = Geometry::PrimitiveHelpers.midpoint(a_moved, b_moved)
              next unless shared_midpoint

              port_a.point = shared_midpoint
              port_b.point = shared_midpoint
              moved_points[port_a.object_id] = shared_midpoint
              moved_points[port_b.object_id] = shared_midpoint
              changed = true
            end
          end

          break unless changed
        end
      rescue => error
        puts "SelectionResizeLayoutService.propagate_selected_port_movements! failed: #{error.message}"
        puts error.backtrace.join("\n")
      end
      private_class_method :propagate_selected_port_movements!

      def self.boundary_reducer_axis(selected_port:, external_port:)
        external_to_selected = Geometry::VectorMath.normalized(external_port.point.vector_to(selected_port.point), epsilon: EPSILON)
        candidates = []

        if external_port.outward_vector
          axis = Geometry::VectorMath.normalized(external_port.outward_vector, epsilon: EPSILON)
          if axis
            axis = axis.clone.reverse if external_to_selected && axis.dot(external_to_selected) < 0.0
            candidates << axis
          end
        end

        candidates << external_to_selected if external_to_selected

        if selected_port.outward_vector
          axis = Geometry::VectorMath.normalized(selected_port.outward_vector.clone.reverse, epsilon: EPSILON)
          if axis
            axis = axis.clone.reverse if external_to_selected && axis.dot(external_to_selected) < 0.0
            candidates << axis
          end
        end

        candidates.compact.first
      rescue => error
        puts "SelectionResizeLayoutService.boundary_reducer_axis failed: #{error.message}"
        nil
      end
      private_class_method :boundary_reducer_axis

      def self.rectangular_basis(dimensions:, direction:, width_axis:, height_axis:)
        return nil unless dimensions[:shape] == :rectangular

        Geometry::RectangularFrame.basis_for_axis(
          direction,
          preferred_width_axis: width_axis,
          preferred_height_axis: height_axis
        )
      end
      private_class_method :rectangular_basis
    end
  end
end

# ===== Consolidated from: services/selection_piece_resize_service.rb =====
module DuctExtension
  module Services
    class SelectionPieceResizeService
      extend FittingRebuildSupport

      EPSILON = 0.000001

      def self.rebuild!(piece:, target_dimensions:)
        return false unless piece && piece.group && piece.group.valid?

        case piece.type.to_sym
        when :pipe
          rebuild_pipe!(piece, target_dimensions)
        when :elbow
          rebuild_elbow!(piece, target_dimensions)
        when :reducer
          rebuild_reducer_as_same_size_piece!(piece, target_dimensions)
        when :tee, :wye, :cross
          FittingRebuildService.resize(piece: piece, dimensions: target_dimensions)
        else
          false
        end
      rescue => error
        puts "SelectionPieceResizeService.rebuild! failed for #{piece&.type}: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_pipe!(piece, dimensions)
        ports = Array(piece.ports)
        return false unless ports.length >= 2

        start_port = ports[0]
        end_port = ports[1]
        start_point = start_port.point
        end_point = end_port.point
        vector = Geometry::VectorMath.normalized(start_point.vector_to(end_point), epsilon: EPSILON)
        return false unless vector

        erase_group_geometry(piece.group)

        success =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularPipeBuilder.build_into(
              piece.group,
              start_point,
              end_point,
              dimensions[:width],
              dimensions[:height],
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false,
              preferred_width_axis: start_port.width_axis || end_port.width_axis,
              preferred_height_axis: start_port.height_axis || end_port.height_axis
            )
          else
            Geometry::PipeBuilder.build_into(
              piece.group,
              start_point,
              end_point,
              dimensions[:diameter],
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false
            )
          end
        return false unless success

        update_port_dimensions!(
          start_port,
          dimensions,
          direction: vector.clone.reverse,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )
        update_port_dimensions!(
          end_port,
          dimensions,
          direction: vector,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )
        true
      rescue => error
        puts "SelectionPieceResizeService.rebuild_pipe! failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end
      private_class_method :rebuild_pipe!

      def self.rebuild_elbow!(piece, dimensions)
        ports = Array(piece.ports)
        return false unless ports.length >= 2

        start_port = ports[0]
        end_port = ports[1]
        start_point = start_port.point
        end_point = end_port.point
        entry_vector = Geometry::VectorMath.normalized(start_port.outward_vector.clone.reverse, epsilon: EPSILON)
        exit_vector = Geometry::VectorMath.normalized(end_port.outward_vector, epsilon: EPSILON)
        return false unless entry_vector && exit_vector

        bend_radius = infer_bend_radius(
          start_point: start_point,
          end_point: end_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          dimensions: dimensions
        )
        return false unless bend_radius && bend_radius > EPSILON

        erase_group_geometry(piece.group)

        success =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularElbowBuilder.build_into(
              piece.group,
              start_point,
              entry_vector,
              exit_vector,
              dimensions[:width],
              dimensions[:height],
              bend_radius,
              cap_start: false,
              cap_end: false,
              preferred_width_axis: start_port.width_axis || end_port.width_axis,
              preferred_height_axis: start_port.height_axis || end_port.height_axis
            )
          else
            Geometry::ElbowBuilder.build_into(
              piece.group,
              start_point,
              entry_vector,
              exit_vector,
              dimensions[:diameter],
              bend_radius,
              cap_start: false,
              cap_end: false
            )
          end

        unless success
          puts "SelectionPieceResizeService.rebuild_elbow! builder returned false."
          puts "  shape=#{dimensions[:shape]} bend_radius=#{bend_radius}"
          return false
        end

        update_port_dimensions!(
          start_port,
          dimensions,
          direction: start_port.outward_vector,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )
        update_port_dimensions!(
          end_port,
          dimensions,
          direction: end_port.outward_vector,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )
        true
      rescue => error
        puts "SelectionPieceResizeService.rebuild_elbow! failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end
      private_class_method :rebuild_elbow!

      def self.rebuild_reducer_as_same_size_piece!(piece, dimensions)
        ports = Array(piece.ports)
        return false unless ports.length >= 2

        start_port = ports[0]
        end_port = ports[1]
        start_point = start_port.point
        end_point = end_port.point
        vector = Geometry::VectorMath.normalized(start_point.vector_to(end_point), epsilon: EPSILON)
        return false unless vector

        erase_group_geometry(piece.group)

        success = Geometry::ReducerBuilder.build_into(
          piece.group,
          start_point,
          end_point,
          start_dimensions: dimensions,
          end_dimensions: dimensions,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )
        return false unless success

        update_port_dimensions!(
          start_port,
          dimensions,
          direction: vector.clone.reverse,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )
        update_port_dimensions!(
          end_port,
          dimensions,
          direction: vector,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )
        true
      rescue => error
        puts "SelectionPieceResizeService.rebuild_reducer_as_same_size_piece! failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end
      private_class_method :rebuild_reducer_as_same_size_piece!

      def self.infer_bend_radius(start_point:, end_point:, entry_vector:, exit_vector:, dimensions:)
        angle = entry_vector.angle_between(exit_vector)
        return nil if angle <= EPSILON || angle >= Math::PI - EPSILON

        chord = start_point.distance(end_point)
        radius = chord / (2.0 * Math.sin(angle / 2.0))
        min_radius = Model::DuctDimensions.coerce(dimensions).largest * 0.75
        [radius, min_radius].max
      rescue
        nil
      end
      private_class_method :infer_bend_radius
    end
  end
end
