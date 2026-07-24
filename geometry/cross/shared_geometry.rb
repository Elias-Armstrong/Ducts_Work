module DuctExtension
  module Geometry
    module CrossBuilder
      def self.rectangle_corners(center:, width_axis:, height_axis:, half_width:, half_height:)
        PrimitiveHelpers.rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )
      end

      def self.add_visible_edge(entities, point_a, point_b)
        PrimitiveHelpers.add_visible_edge(
          entities,
          point_a,
          point_b,
          min_distance: 0.001,
          inclusive: false
        )
      end

      def self.edge_midpoint(edge)
        PrimitiveHelpers.edge_midpoint(edge)
      end

      def self.local_coords(point:, center:, forward_axis:, side_axis:, height_axis:)
        vector = center.vector_to(point)

        {
          forward: vector.dot(forward_axis),
          side: vector.dot(side_axis),
          height: vector.dot(height_axis)
        }
      rescue
        nil
      end

      def self.box_point(center, forward_axis, side_axis, height_axis, forward_amount, side_amount, height_amount)
        Geom::Point3d.new(
          center.x +
            forward_axis.x * forward_amount +
            side_axis.x * side_amount +
            height_axis.x * height_amount,

          center.y +
            forward_axis.y * forward_amount +
            side_axis.y * side_amount +
            height_axis.y * height_amount,

          center.z +
            forward_axis.z * forward_amount +
            side_axis.z * side_amount +
            height_axis.z * height_amount
        )
      end

      def self.perpendicularized(vector, axis)
        VectorMath.perpendicularized(vector, axis)
      end

      private_class_method :build_round
      private_class_method :build_rectangular
      private_class_method :build_rectangular_socket
      private_class_method :add_oriented_box
      private_class_method :harden_all_rectangular_edges
      private_class_method :hide_rectangular_cross_seams
      private_class_method :add_rectangular_cross_boundary_edges
      private_class_method :add_rectangular_prism_outline_edges
      private_class_method :rectangle_corners
      private_class_method :add_visible_edge
      private_class_method :edge_midpoint
      private_class_method :local_coords
      private_class_method :box_point
      private_class_method :perpendicularized
      private_class_method :add_oval_hub
    end
  end
end
