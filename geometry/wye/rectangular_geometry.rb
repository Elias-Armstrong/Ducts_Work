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

        branch_shape = branch_shape.to_sym rescue nil
        branch_shape = :rectangular unless branch_shape == :round

        branch_diameter = branch_diameter.to_f
        branch_width = branch_width.to_f
        branch_height = branch_height.to_f

        if branch_shape == :round
          branch_diameter = [width, height].max if branch_diameter <= 0.0
          branch_width = branch_diameter
          branch_height = branch_diameter
        else
          branch_width = width if branch_width <= 0.0
          branch_height = height if branch_height <= 0.0
          branch_diameter = [branch_width, branch_height].max
        end

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

        if branch_shape == :round
          branch_distance = rectangular_round_branch_outlet_distance(
            width,
            height,
            branch_diameter,
            branch_axis,
            side_axis
          )

          build_rectangular_to_round_wye_body(
            group: group,
            center: center,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis,
            branch_axis: branch_axis,
            width: width,
            height: height,
            branch_diameter: branch_diameter,
            main_distance: main_distance,
            branch_distance: branch_distance
          )
        else
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
        end

        Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "WyeBuilder.build_rectangular failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_rectangular_to_round_wye_body(
        group:,
        center:,
        forward_axis:,
        side_axis:,
        height_axis:,
        branch_axis:,
        width:,
        height:,
        branch_diameter:,
        main_distance:,
        branch_distance:
      )
        half_width = width.to_f / 2.0
        half_height = height.to_f / 2.0
        radius = branch_diameter.to_f / 2.0

        stem_end = center.offset(forward_axis.clone.reverse, main_distance)
        forward_end = center.offset(forward_axis, main_distance)

        RectangularPipeBuilder.build_into(
          group,
          stem_end,
          forward_end,
          width,
          height,
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false,
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis
        )

        branch_side_component = branch_axis.dot(side_axis).abs
        branch_side_component = 0.001 if branch_side_component < 0.001

        sidewall_distance = half_width / branch_side_component

        branch_start_distance = sidewall_distance - radius * ROUND_BRANCH_SIDEWALL_OVERLAP_FACTOR
        branch_start_distance = 0.0 if branch_start_distance < 0.0

        branch_start = center.offset(branch_axis, branch_start_distance)
        branch_end = center.offset(branch_axis, branch_distance)

        PipeBuilder.build_into(
          group,
          branch_start,
          branch_end,
          branch_diameter,
          overlap_start: true,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        add_rectangular_socket_ring_edges(
          entities: group.entities,
          center: stem_end,
          width_axis: side_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        add_rectangular_socket_ring_edges(
          entities: group.entities,
          center: forward_end,
          width_axis: side_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        add_round_branch_saddle_edges(
          group: group,
          center: center,
          side_axis: side_axis,
          height_axis: height_axis,
          branch_axis: branch_axis,
          main_half_width: half_width,
          main_half_height: half_height,
          branch_radius: radius
        )

        harden_all_edges(group)

        clean_round_branch_visual_edges(
          group: group,
          start_point: branch_start,
          end_point: branch_end,
          axis: branch_axis,
          radius: radius
        )

        clean_round_branch_entry_artifacts(
          group: group,
          center: center,
          side_axis: side_axis,
          height_axis: height_axis,
          branch_axis: branch_axis,
          main_half_width: half_width,
          main_half_height: half_height,
          branch_radius: radius
        )

        add_round_socket_ring(
          group: group,
          center: branch_end,
          direction: branch_axis,
          radius: radius
        )

        true
      rescue => error
        puts "WyeBuilder.build_rectangular_to_round_wye_body failed: #{error.message}"
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
