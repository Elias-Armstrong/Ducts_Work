module DuctExtension
  module Geometry
    module WyeBuilder
      def self.add_sheet_metal_break_lines(
        entities:,
        center:,
        forward_axis:,
        side_axis:,
        height_axis:,
        half_height:,
        layout:,
        skip_branch_opening: false
      )
        pairs = [
          [layout[:outer_intersection], layout[:branch_outer_end]],
          [layout[:inner_intersection], layout[:branch_inner_end]],
          [layout[:outer_intersection], layout[:inner_intersection]]
        ]

        pairs.each do |pair|
          point_a_2d, point_b_2d = pair
          next unless point_a_2d && point_b_2d

          if skip_branch_opening
            next if same_2d?(point_a_2d, layout[:branch_inner_end]) || same_2d?(point_a_2d, layout[:branch_outer_end])
            next if same_2d?(point_b_2d, layout[:branch_inner_end]) || same_2d?(point_b_2d, layout[:branch_outer_end])
          end

          top_a = point_from_offsets(
            center: center,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis,
            forward_offset: point_a_2d[0],
            side_offset: point_a_2d[1],
            height_offset: half_height
          )

          top_b = point_from_offsets(
            center: center,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis,
            forward_offset: point_b_2d[0],
            side_offset: point_b_2d[1],
            height_offset: half_height
          )

          bottom_a = point_from_offsets(
            center: center,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis,
            forward_offset: point_a_2d[0],
            side_offset: point_a_2d[1],
            height_offset: -half_height
          )

          bottom_b = point_from_offsets(
            center: center,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis,
            forward_offset: point_b_2d[0],
            side_offset: point_b_2d[1],
            height_offset: -half_height
          )

          add_visible_edge(entities, top_a, top_b)
          add_visible_edge(entities, bottom_a, bottom_b)
        end
      rescue
        nil
      end

      def self.add_rectangular_socket_ring_edges(entities:, center:, width_axis:, height_axis:, half_width:, half_height:)
        corners = rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        add_ring_edges(entities, corners)
      rescue
        nil
      end

      def self.add_profile_outline_edges(entities:, top_points:, bottom_points:, layout: nil, skip_branch_opening: false)
        skipped_indices = []

        if skip_branch_opening && layout
          skipped_indices = profile_indices_for_edge(
            layout[:profile],
            layout[:branch_inner_end],
            layout[:branch_outer_end]
          )
        end

        top_points.length.times do |index|
          next_index = (index + 1) % top_points.length

          skip_edge =
            skip_branch_opening &&
            skipped_indices.include?(index) &&
            skipped_indices.include?(next_index)

          unless skip_edge
            add_visible_edge(entities, top_points[index], top_points[next_index])
            add_visible_edge(entities, bottom_points[index], bottom_points[next_index])
          end

          unless skip_branch_opening && skipped_indices.include?(index)
            add_visible_edge(entities, top_points[index], bottom_points[index])
          end
        end
      rescue
        nil
      end

      def self.profile_indices_for_edge(profile, endpoint_a, endpoint_b)
        result = []

        Array(profile).each_with_index do |point, index|
          result << index if same_2d?(point, endpoint_a) || same_2d?(point, endpoint_b)
        end

        result
      rescue
        []
      end

      def self.point_from_offsets(center:, forward_axis:, side_axis:, height_axis:, forward_offset:, side_offset:, height_offset:)
        Geom::Point3d.new(
          center.x + forward_axis.x * forward_offset + side_axis.x * side_offset + height_axis.x * height_offset,
          center.y + forward_axis.y * forward_offset + side_axis.y * side_offset + height_axis.y * height_offset,
          center.z + forward_axis.z * forward_offset + side_axis.z * side_offset + height_axis.z * height_offset
        )
      end

      def self.cleanup_2d_profile(points)
        cleaned = []

        Array(points).each do |point|
          next unless point && point.length >= 2

          candidate = [point[0].to_f, point[1].to_f]
          cleaned << candidate unless cleaned.any? { |existing| same_2d?(existing, candidate, 0.0005) }
        end

        cleaned
      rescue
        []
      end

      def self.mark_matching_edge(result, profile, endpoint_a, endpoint_b)
        profile.length.times do |index|
          next_index = (index + 1) % profile.length
          point_a = profile[index]
          point_b = profile[next_index]

          if (same_2d?(point_a, endpoint_a) && same_2d?(point_b, endpoint_b)) ||
             (same_2d?(point_a, endpoint_b) && same_2d?(point_b, endpoint_a))
            result[[index, next_index]] = true
          end
        end
      rescue
        nil
      end

      def self.same_2d?(point_a, point_b, tolerance = 0.001)
        return false unless point_a && point_b

        (point_a[0].to_f - point_b[0].to_f).abs <= tolerance &&
          (point_a[1].to_f - point_b[1].to_f).abs <= tolerance
      rescue
        false
      end

    end
  end
end
