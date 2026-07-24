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
