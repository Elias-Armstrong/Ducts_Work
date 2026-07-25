module DuctExtension
  module Geometry
    module WyeBuilder
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
          min_distance: RECTANGULAR_OPENING_CLEARANCE,
          inclusive: false
        )
      end

      def self.harden_all_edges(group)
        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.hidden = false
          edge.soft = false if edge.respond_to?(:soft=)
          edge.smooth = false if edge.respond_to?(:smooth=)
        end
      rescue => error
        puts "WyeBuilder.harden_all_edges failed: #{error.message}"
      end

      def self.perpendicularized(vector, axis)
        VectorMath.perpendicularized(vector, axis)
      end

      private_class_method :build_round
      private_class_method :build_rectangular
      private_class_method :build_rectangular_to_rectangular_wye_body
      private_class_method :rectangular_union_wye_layout
      private_class_method :add_sheet_metal_break_lines
      private_class_method :add_round_wye_hub
      private_class_method :hide_round_wye_internal_edges
      private_class_method :add_round_socket_ring
      private_class_method :add_rectangular_socket_ring_edges
      private_class_method :rectangle_corners
      private_class_method :add_profile_outline_edges
      private_class_method :profile_indices_for_edge
      private_class_method :add_visible_edge
      private_class_method :point_from_offsets
      private_class_method :cleanup_2d_profile
      private_class_method :mark_matching_edge
      private_class_method :same_2d?
      private_class_method :harden_all_edges
      private_class_method :hide_round_edge
      private_class_method :edge_midpoint
      private_class_method :rectangular_stable_basis
      private_class_method :perpendicularized
    end
  end
end
