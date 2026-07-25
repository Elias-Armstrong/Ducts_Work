module DuctExtension
  module Services
    module EndFittingSupport
      # Build the stable local frame used by end-cross/end-wye insertion.
      # +reclean_rectangular_axes+ preserves the extra cleanup pass that the
      # cross service historically performed.
      def self.frame_for_stem_port(
        stem_port:,
        side_vector:,
        forward_vector:,
        dimensions:,
        reclean_rectangular_axes: false
      )
        forward_axis = Geometry::VectorMath.normalized(forward_vector)
        return nil unless forward_axis

        if dimensions[:shape] == :rectangular
          height_axis = Geometry::VectorMath.perpendicularized(stem_port.height_axis, forward_axis)
          width_axis = Geometry::VectorMath.perpendicularized(stem_port.width_axis, forward_axis)

          if width_axis && height_axis
            if reclean_rectangular_axes
              height_axis = Geometry::VectorMath.perpendicularized(height_axis, forward_axis)
              width_axis = Geometry::VectorMath.perpendicularized(width_axis, forward_axis)
            end

            corrected_height = forward_axis.cross(width_axis)
            if corrected_height && corrected_height.length > 0
              corrected_height.normalize!
              height_axis = corrected_height
            end

            return {
              side_axis: width_axis,
              height_axis: height_axis
            }
          end

          if height_axis
            width_axis = height_axis.cross(forward_axis)
            if width_axis && width_axis.length > 0
              width_axis.normalize!
              return {
                side_axis: width_axis,
                height_axis: height_axis
              }
            end
          end

          if width_axis
            height_axis = forward_axis.cross(width_axis)
            if height_axis && height_axis.length > 0
              height_axis.normalize!
              return {
                side_axis: width_axis,
                height_axis: height_axis
              }
            end
          end
        end

        side_axis = Geometry::VectorMath.perpendicularized(side_vector, forward_axis)
        side_axis ||= Geometry::VectorMath.fallback_perpendicular_axis(forward_axis)
        return nil unless side_axis

        height_axis = forward_axis.cross(side_axis)
        return nil if height_axis.length == 0

        height_axis.normalize!

        {
          side_axis: side_axis,
          height_axis: height_axis
        }
      rescue
        nil
      end

      def self.port_basis_for_direction(dimensions:, direction:, width_axis:, height_axis:)
        return nil unless dimensions[:shape] == :rectangular

        direction = Geometry::VectorMath.normalized(direction)
        return nil unless direction

        clean_width = Geometry::VectorMath.perpendicularized(width_axis, direction)
        clean_height = Geometry::VectorMath.perpendicularized(height_axis, direction)

        if clean_width && clean_height
          corrected_height = direction.cross(clean_width)
          if corrected_height && corrected_height.length > 0
            corrected_height.normalize!
            clean_height = corrected_height
          end

          return {
            width_axis: clean_width,
            height_axis: clean_height
          }
        end

        Geometry::RectangularFrame.basis_for_axis(direction)
      rescue
        nil
      end

      def self.rectangular_face_offset_for_direction(direction:, dimensions:, basis:)
        return 0.0 unless direction && basis

        vector = Geometry::VectorMath.normalized(direction)
        return 0.0 unless vector

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

      def self.socket_depth(dimensions:, round_builder:, rectangular_builder: round_builder, fallback_factor: 0.82)
        if dimensions[:shape] == :rectangular
          return rectangular_builder.socket_depth(
            dimensions[:width],
            dimensions[:height]
          )
        end

        round_builder.socket_depth(dimensions[:diameter])
      rescue
        Model::DuctDimensions.coerce(dimensions).largest * fallback_factor.to_f
      end

      # Shared topology/metadata finalization for end fittings. Geometry remains
      # fitting-specific; only the identical network bookkeeping lives here.
      def self.finalize_end_fitting!(
        network:,
        original_stem_port:,
        piece:,
        fitting_stem_port:,
        outlet_ports:
      )
        network.add_piece(piece)
        PieceMetadataService.save_piece(piece)
        network.connect_ports(original_stem_port, fitting_stem_port)

        PortCapService.remove(original_stem_port)

        Array(outlet_ports).compact.each do |port|
          PortCapService.add(piece.group, port)
        end

        network.rebuild_index! if network.respond_to?(:rebuild_index!)
        piece
      end
    end
  end
end
