# ===== Consolidated from: geometry/wye/rectangular_geometry.rb =====
module DuctExtension
  module Geometry
    module WyeBuilder
      def self.build_rectangular(
        group:,
        center:,
        forward_vector:,
        side_vector:,
        width:,
        height:,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        branch_shape: nil,
        branch_diameter: nil,
        branch_width: nil,
        branch_height: nil
      )
        return false if width <= 0.0 || height <= 0.0

        # Mixed-shape outlets are now built as a stable rectangular fitting
        # followed by ReducerBuilder's rectangular/round transition. Keeping
        # this builder rectangular-only removes the fragile intersecting-pipe
        # implementation that used to create the "tube stuck through a box" look.
        branch_width = branch_width.to_f
        branch_height = branch_height.to_f
        branch_width = width if branch_width <= 0.0
        branch_height = height if branch_height <= 0.0

        forward_axis = RectangularFrame.normalized(forward_vector)
        return false unless forward_axis

        main_basis = rectangular_stable_basis(
          forward_axis,
          width,
          height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          allow_relevel: false
        )
        return false unless main_basis

        side_axis = perpendicularized(preferred_width_axis, forward_axis)
        side_axis ||= perpendicularized(side_vector, forward_axis)
        side_axis ||= main_basis[:width_axis]
        return false unless side_axis

        height_axis = perpendicularized(preferred_height_axis, forward_axis)
        height_axis ||= main_basis[:height_axis]
        height_axis ||= forward_axis.cross(side_axis)
        return false unless height_axis && height_axis.length > 0
        height_axis.normalize!

        corrected_side = height_axis.cross(forward_axis)

        if corrected_side && corrected_side.length > 0
          corrected_side.normalize!
          side_axis = corrected_side
        end

        branch_axis = branch_vector(forward_axis, side_axis)
        return false unless branch_axis

        branch_width_axis = height_axis.cross(branch_axis)
        return false unless branch_width_axis && branch_width_axis.length > 0
        branch_width_axis.normalize!
        branch_width_axis.reverse! if branch_width_axis.dot(side_axis) < 0.0

        main_distance = main_outlet_distance(width, height)

        branch_distance = branch_outlet_distance(branch_width, branch_height)

        build_rectangular_to_rectangular_wye_body(
          group: group,
          center: center,
          forward_axis: forward_axis,
          side_axis: side_axis,
          height_axis: height_axis,
          branch_axis: branch_axis,
          branch_width_axis: branch_width_axis,
          width: width,
          height: height,
          branch_width: branch_width,
          branch_height: branch_height,
          main_distance: main_distance,
          branch_distance: branch_distance
        )

        Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "WyeBuilder.build_rectangular failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_rectangular_to_rectangular_wye_body(
        group:,
        center:,
        forward_axis:,
        side_axis:,
        height_axis:,
        branch_axis:,
        branch_width_axis:,
        width:,
        height:,
        branch_width:,
        branch_height:,
        main_distance:,
        branch_distance:
      )
        entities = group.entities
        half_width = width.to_f / 2.0
        half_height = height.to_f / 2.0
        half_branch_width = branch_width.to_f / 2.0
        half_branch_height = branch_height.to_f / 2.0

        layout = rectangular_union_wye_layout(
          branch_axis: branch_axis,
          branch_width_axis: branch_width_axis,
          forward_axis: forward_axis,
          side_axis: side_axis,
          half_width: half_width,
          branch_half_width: half_branch_width,
          main_distance: main_distance,
          branch_distance: branch_distance
        )
        return false unless layout && layout[:profile].length >= 7

        top_points = layout[:profile].map do |pair|
          point_from_offsets(
            center: center,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis,
            forward_offset: pair[0],
            side_offset: pair[1],
            height_offset: half_height
          )
        end

        bottom_points = layout[:profile].map do |pair|
          point_from_offsets(
            center: center,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis,
            forward_offset: pair[0],
            side_offset: pair[1],
            height_offset: -half_height
          )
        end

        Mesh.add_face_safe(entities, top_points)
        Mesh.add_face_safe(entities, bottom_points.reverse)

        layout[:profile].length.times do |index|
          next_index = (index + 1) % layout[:profile].length
          next if layout[:open_edges][[index, next_index]]
          next if layout[:open_edges][[next_index, index]]

          Mesh.add_quad(
            entities,
            top_points[index],
            top_points[next_index],
            bottom_points[next_index],
            bottom_points[index]
          )
        end

        add_profile_outline_edges(
          entities: entities,
          top_points: top_points,
          bottom_points: bottom_points,
          layout: layout,
          skip_branch_opening: false
        )

        add_rectangular_socket_ring_edges(
          entities: entities,
          center: center.offset(forward_axis.clone.reverse, main_distance),
          width_axis: side_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        add_rectangular_socket_ring_edges(
          entities: entities,
          center: center.offset(forward_axis, main_distance),
          width_axis: side_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        add_rectangular_socket_ring_edges(
          entities: entities,
          center: center.offset(branch_axis, branch_distance),
          width_axis: branch_width_axis,
          height_axis: height_axis,
          half_width: half_branch_width,
          half_height: half_branch_height
        )

        add_sheet_metal_break_lines(
          entities: entities,
          center: center,
          forward_axis: forward_axis,
          side_axis: side_axis,
          height_axis: height_axis,
          half_height: half_height,
          layout: layout,
          skip_branch_opening: false
        )

        harden_all_edges(group)
        true
      rescue => error
        puts "WyeBuilder.build_rectangular_to_rectangular_wye_body failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rectangular_union_wye_layout(
        branch_axis:,
        branch_width_axis:,
        forward_axis:,
        side_axis:,
        half_width:,
        branch_half_width:,
        main_distance:,
        branch_distance:
      )
        branch_forward = branch_axis.dot(forward_axis)
        branch_side = branch_axis.dot(side_axis)
        width_forward = branch_width_axis.dot(forward_axis)
        width_side = branch_width_axis.dot(side_axis)

        return nil if branch_side.abs <= 0.001
        return nil if width_side.abs <= 0.001

        branch_outer_end = [
          branch_forward * branch_distance + width_forward * branch_half_width,
          branch_side * branch_distance + width_side * branch_half_width
        ]

        branch_inner_end = [
          branch_forward * branch_distance - width_forward * branch_half_width,
          branch_side * branch_distance - width_side * branch_half_width
        ]

        outer_intersection_t = (half_width - width_side * branch_half_width) / branch_side
        inner_intersection_t = (half_width + width_side * branch_half_width) / branch_side

        outer_intersection = [
          branch_forward * outer_intersection_t + width_forward * branch_half_width,
          half_width
        ]

        inner_intersection = [
          branch_forward * inner_intersection_t - width_forward * branch_half_width,
          half_width
        ]

        min_span = half_width * 2.0 * RECTANGULAR_MIN_OPENING_SPAN_FACTOR

        outer_intersection[0] = [
          [outer_intersection[0], -main_distance + min_span].max,
          main_distance - min_span
        ].min

        inner_intersection[0] = [
          [inner_intersection[0], outer_intersection[0] + min_span].max,
          main_distance - min_span * 0.35
        ].min

        profile = [
          [-main_distance, -half_width],
          [main_distance, -half_width],
          [main_distance, half_width],
          inner_intersection,
          branch_inner_end,
          branch_outer_end,
          outer_intersection,
          [-main_distance, half_width]
        ]

        profile = cleanup_2d_profile(profile)

        open_edges = {}
        mark_matching_edge(open_edges, profile, [-main_distance, -half_width], [-main_distance, half_width])
        mark_matching_edge(open_edges, profile, [main_distance, -half_width], [main_distance, half_width])
        mark_matching_edge(open_edges, profile, branch_inner_end, branch_outer_end)

        {
          profile: profile,
          open_edges: open_edges,
          outer_intersection: outer_intersection,
          inner_intersection: inner_intersection,
          branch_inner_end: branch_inner_end,
          branch_outer_end: branch_outer_end
        }
      rescue => error
        puts "WyeBuilder.rectangular_union_wye_layout failed: #{error.message}"
        nil
      end

      def self.rectangular_stable_basis(axis, width, height, preferred_width_axis: nil, preferred_height_axis: nil, allow_relevel: false)
        if RectangularFrame.respond_to?(:stable_basis_for_axis)
          RectangularFrame.stable_basis_for_axis(
            axis,
            width,
            height,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis,
            allow_relevel: allow_relevel
          )
        else
          RectangularFrame.basis_for_axis(
            axis,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )
        end
      rescue
        RectangularFrame.basis_for_axis(
          axis,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )
      end

    end
  end
end

# ===== Consolidated from: geometry/wye/rectangular_visual_geometry.rb =====
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

# ===== Consolidated from: geometry/wye/shared_geometry.rb =====
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
