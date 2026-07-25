module DuctExtension
  module Geometry
    module RectangularFrame
      def self.transport_basis(
        from_axis:,
        to_axis:,
        width_axis:,
        height_axis: nil
      )
        from_axis = normalized(from_axis)
        to_axis = normalized(to_axis)
        width_axis = normalized(width_axis)
        height_axis = normalized(height_axis)

        return nil unless from_axis && to_axis && width_axis

        angle = from_axis.angle_between(to_axis)

        if angle <= EPSILON
          transported_width = perpendicularized(width_axis, to_axis)
          transported_width ||= basis_for_axis(to_axis)[:width_axis]

          transported_height = to_axis.cross(transported_width)
          return nil if transported_height.length <= EPSILON

          transported_height.normalize!

          return {
            axis: to_axis,
            width_axis: transported_width,
            height_axis: transported_height
          }
        end

        rotation_axis = from_axis.cross(to_axis)

        if rotation_axis.length <= EPSILON
          rotation_axis = perpendicularized(height_axis, from_axis)
          rotation_axis ||= perpendicularized(best_reference_axis(from_axis), from_axis)
        end

        return nil unless rotation_axis
        return nil if rotation_axis.length <= EPSILON

        rotation_axis.normalize!

        transform = Geom::Transformation.rotation(
          Geom::Point3d.new(0, 0, 0),
          rotation_axis,
          angle
        )

        transported_width = width_axis.transform(transform)
        transported_width = perpendicularized(transported_width, to_axis)
        transported_width ||= basis_for_axis(to_axis)[:width_axis]

        transported_height = to_axis.cross(transported_width)
        return nil if transported_height.length <= EPSILON

        transported_height.normalize!

        {
          axis: to_axis,
          width_axis: transported_width,
          height_axis: transported_height
        }
      rescue => error
        puts "RectangularFrame.transport_basis failed: #{error.message}"
        nil
      end

      def self.stable_transport_basis(
        from_axis:,
        to_axis:,
        width_axis:,
        height_axis: nil,
        width: nil,
        height: nil,
        world_up: WORLD_Z,
        allow_relevel: false
      )
        transported = transport_basis(
          from_axis: from_axis,
          to_axis: to_axis,
          width_axis: width_axis,
          height_axis: height_axis
        )

        return transported if transported && !allow_relevel

        stable_basis_for_axis(
          to_axis,
          width,
          height,
          preferred_width_axis: transported && transported[:width_axis],
          preferred_height_axis: transported && transported[:height_axis],
          world_up: world_up,
          allow_relevel: allow_relevel
        )
      rescue => error
        puts "RectangularFrame.stable_transport_basis failed: #{error.message}"
        nil
      end


    end
  end
end
