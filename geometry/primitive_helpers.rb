module DuctExtension
  module Geometry
    module PrimitiveHelpers
      # Return rectangle corners in the same winding order used by the existing
      # fitting builders. Axes are intentionally not reoriented here; callers
      # remain responsible for choosing their fitting frame.
      def self.rectangle_corners(
        center:,
        width_axis:,
        height_axis:,
        half_width:,
        half_height:,
        normalize_axes: false
      )
        return [] unless center && width_axis && height_axis

        if normalize_axes
          width_axis = VectorMath.normalized(width_axis)
          height_axis = VectorMath.normalized(height_axis)
          return [] unless width_axis && height_axis
        end

        [
          center.offset(width_axis, half_width).offset(height_axis, half_height),
          center.offset(width_axis.clone.reverse, half_width).offset(height_axis, half_height),
          center.offset(width_axis.clone.reverse, half_width).offset(height_axis.clone.reverse, half_height),
          center.offset(width_axis, half_width).offset(height_axis.clone.reverse, half_height)
        ]
      rescue
        []
      end

      # Add an explicitly visible, non-soft, non-smooth edge. Different callers
      # can preserve their old clearance tolerance via +min_distance+.
      def self.add_visible_edge(entities, point_a, point_b, min_distance: 0.0, inclusive: true)
        return unless entities && point_a && point_b

        distance = point_a.distance(point_b)
        too_short = inclusive ? distance <= min_distance.to_f : distance < min_distance.to_f
        return if too_short

        edge = entities.add_line(point_a, point_b)
        return unless edge

        edge.hidden = false
        edge.soft = false if edge.respond_to?(:soft=)
        edge.smooth = false if edge.respond_to?(:smooth=)
        edge
      rescue
        nil
      end
    end
  end
end
