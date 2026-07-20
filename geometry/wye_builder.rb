module DuctExtension
  module Geometry
    module WyeBuilder
      SOCKET_DEPTH_FACTOR = 0.90
      BRANCH_ANGLE_DEGREES = 45.0

      RECTANGULAR_MAIN_EXTRA_FACTOR = 1.35
      ROUND_MAIN_EXTRA_FACTOR = 0.75
      RECTANGULAR_BRANCH_PULL_OUT_FACTOR = 1.25
      ROUND_BRANCH_PULL_OUT_FACTOR = 0.62
      RECTANGULAR_BRANCH_EXTRA_FACTOR = 1.25
      ROUND_BRANCH_EXTRA_FACTOR = 0.75

      ROUND_HUB_FORWARD_RADIUS_FACTOR = 0.86
      ROUND_HUB_SIDE_RADIUS_FACTOR = 0.70
      ROUND_HUB_NORMAL_RADIUS_FACTOR = 0.58
      ROUND_HUB_SEGMENTS = 24
      ROUND_HUB_RINGS = 10
      ROUND_INTERNAL_HIDE_RADIUS_FACTOR = 1.28
      ROUND_BRANCH_NECK_HIDE_FACTOR = 0.62

      RECTANGULAR_OPENING_CLEARANCE = 0.001
      RECTANGULAR_MIN_OPENING_SPAN_FACTOR = 0.38

      ROUND_BRANCH_SIDEWALL_OVERLAP_FACTOR = 0.88
      ROUND_BRANCH_VISIBLE_PROTRUSION_FACTOR = 1.65
      ROUND_BRANCH_SADDLE_WIDTH_FACTOR = 1.10
      ROUND_BRANCH_VISUAL_HIDE_RADIUS_FACTOR = 1.18
      ROUND_BRANCH_ENTRY_ARTIFACT_FORWARD_FACTOR = 1.25
      ROUND_BRANCH_ENTRY_ARTIFACT_HEIGHT_FACTOR = 1.00
      ROUND_BRANCH_ENTRY_ARTIFACT_SIDE_FACTOR = 0.85

      def self.socket_depth(diameter_or_width, height = nil)
        if height
          [diameter_or_width.to_f, height.to_f].max * SOCKET_DEPTH_FACTOR
        else
          diameter_or_width.to_f * SOCKET_DEPTH_FACTOR
        end
      end

      def self.main_outlet_distance(diameter_or_width, height = nil)
        base = socket_depth(diameter_or_width, height)

        if height
          base + [diameter_or_width.to_f, height.to_f].max * RECTANGULAR_MAIN_EXTRA_FACTOR
        else
          base + diameter_or_width.to_f * ROUND_MAIN_EXTRA_FACTOR
        end
      end

      def self.branch_outlet_distance(diameter_or_width, height = nil)
        base = socket_depth(diameter_or_width, height)

        if height
          base + [diameter_or_width.to_f, height.to_f].max * RECTANGULAR_BRANCH_EXTRA_FACTOR
        else
          base + diameter_or_width.to_f * ROUND_BRANCH_EXTRA_FACTOR
        end
      end

      def self.rectangular_round_branch_outlet_distance(main_width, main_height, branch_diameter, branch_axis, side_axis)
        branch_axis = RectangularFrame.normalized(branch_axis)
        side_axis = RectangularFrame.normalized(side_axis)

        return branch_outlet_distance(branch_diameter) unless branch_axis && side_axis

        side_component = branch_axis.dot(side_axis).abs
        side_component = 0.001 if side_component < 0.001

        sidewall_distance = (main_width.to_f / 2.0) / side_component
        visible_protrusion = branch_diameter.to_f * ROUND_BRANCH_VISIBLE_PROTRUSION_FACTOR

        sidewall_distance + visible_protrusion
      rescue => error
        puts "WyeBuilder.rectangular_round_branch_outlet_distance failed: #{error.message}"
        branch_outlet_distance(branch_diameter)
      end

      def self.branch_pullout_distance(width, height = nil)
        if height
          [width.to_f, height.to_f].max * RECTANGULAR_BRANCH_PULL_OUT_FACTOR
        else
          width.to_f * ROUND_BRANCH_PULL_OUT_FACTOR
        end
      end

      def self.branch_angle
        BRANCH_ANGLE_DEGREES.degrees
      end

      def self.build_into(
        group,
        center,
        forward_vector,
        side_vector,
        diameter: nil,
        width: nil,
        height: nil,
        shape: :round,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        branch_shape: nil,
        branch_diameter: nil,
        branch_width: nil,
        branch_height: nil
      )
        return false unless group && group.valid?

        center = RectangularFrame.point3d(center)
        forward_vector = RectangularFrame.normalized(forward_vector)
        side_vector = RectangularFrame.normalized(side_vector)

        return false unless center && forward_vector && side_vector
        return false if forward_vector.parallel?(side_vector)

        if shape == :rectangular
          build_rectangular(
            group: group,
            center: center,
            forward_vector: forward_vector,
            side_vector: side_vector,
            width: width.to_f,
            height: height.to_f,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis,
            branch_shape: branch_shape,
            branch_diameter: branch_diameter,
            branch_width: branch_width,
            branch_height: branch_height
          )
        else
          build_round(
            group: group,
            center: center,
            forward_vector: forward_vector,
            side_vector: side_vector,
            diameter: diameter.to_f,
            branch_diameter: branch_diameter
          )
        end
      rescue => error
        puts "WyeBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.branch_vector(forward_vector, side_vector)
        forward_axis = RectangularFrame.normalized(forward_vector)
        side_axis = perpendicularized(side_vector, forward_axis)
        return nil unless forward_axis && side_axis

        c = Math.cos(branch_angle)
        s = Math.sin(branch_angle)

        result = Geom::Vector3d.new(
          forward_axis.x * c + side_axis.x * s,
          forward_axis.y * c + side_axis.y * s,
          forward_axis.z * c + side_axis.z * s
        )

        return nil if result.length == 0

        result.normalize!
        result
      rescue
        nil
      end

      def self.build_round(group:, center:, forward_vector:, side_vector:, diameter:, branch_diameter: nil)
        return false if diameter <= 0.0

        branch_diameter = branch_diameter.to_f
        branch_diameter = diameter if branch_diameter <= 0.0

        forward_axis = RectangularFrame.normalized(forward_vector)
        side_axis = perpendicularized(side_vector, forward_axis)
        branch_axis = branch_vector(forward_axis, side_axis)
        return false unless forward_axis && side_axis && branch_axis

        main_distance = main_outlet_distance(diameter)
        branch_distance = branch_outlet_distance(branch_diameter)
        branch_pullout = branch_pullout_distance([diameter, branch_diameter].max)

        stem_end = center.offset(forward_axis.clone.reverse, main_distance)
        forward_end = center.offset(forward_axis, main_distance)
        branch_start = center.offset(branch_axis, branch_pullout)
        branch_end = center.offset(branch_axis, branch_distance)

        PipeBuilder.build_into(
          group,
          stem_end,
          forward_end,
          diameter,
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

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

        add_round_wye_hub(
          group: group,
          center: center,
          forward_axis: forward_axis,
          side_axis: side_axis,
          diameter: diameter
        )

        hide_round_wye_internal_edges(
          group: group,
          center: center,
          forward_axis: forward_axis,
          side_axis: side_axis,
          branch_axis: branch_axis,
          diameter: diameter,
          branch_pullout: branch_pullout
        )

        add_round_socket_ring(
          group: group,
          center: stem_end,
          direction: forward_axis.clone.reverse,
          radius: diameter / 2.0
        )

        add_round_socket_ring(
          group: group,
          center: forward_end,
          direction: forward_axis,
          radius: diameter / 2.0
        )

        add_round_socket_ring(
          group: group,
          center: branch_end,
          direction: branch_axis,
          radius: branch_diameter / 2.0
        )

        Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "WyeBuilder.build_round failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

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

      def self.add_round_branch_saddle_edges(
        group:,
        center:,
        side_axis:,
        height_axis:,
        branch_axis:,
        main_half_width:,
        main_half_height:,
        branch_radius:
      )
        entities = group.entities
        side_component = branch_axis.dot(side_axis)
        side_sign = side_component < 0.0 ? -1.0 : 1.0

        sidewall_center = center.offset(side_axis, main_half_width * side_sign)

        vertical_radius = [branch_radius, main_half_height * 0.94].min
        horizontal_radius = branch_radius * ROUND_BRANCH_SADDLE_WIDTH_FACTOR

        wall_tangent = height_axis.cross(side_axis)
        wall_tangent = branch_axis.cross(height_axis) if wall_tangent.length == 0
        return if wall_tangent.length == 0
        wall_tangent.normalize!

        points = []
        segments = PipeBuilder::SEGMENTS rescue 32

        segments.times do |index|
          angle = Math::PI * 2.0 * index / segments.to_f
          tangent_offset = Math.cos(angle) * horizontal_radius
          height_offset = Math.sin(angle) * vertical_radius

          points << Geom::Point3d.new(
            sidewall_center.x + wall_tangent.x * tangent_offset + height_axis.x * height_offset,
            sidewall_center.y + wall_tangent.y * tangent_offset + height_axis.y * height_offset,
            sidewall_center.z + wall_tangent.z * tangent_offset + height_axis.z * height_offset
          )
        end

        add_ring_edges(entities, points)
      rescue => error
        puts "WyeBuilder.add_round_branch_saddle_edges failed: #{error.message}"
      end

      def self.add_round_wye_hub(group:, center:, forward_axis:, side_axis:, diameter:)
        normal_axis = forward_axis.cross(side_axis)
        return if normal_axis.length == 0
        normal_axis.normalize!

        side_axis = normal_axis.cross(forward_axis)
        return if side_axis.length == 0
        side_axis.normalize!

        radius_forward = diameter.to_f * ROUND_HUB_FORWARD_RADIUS_FACTOR
        radius_side = diameter.to_f * ROUND_HUB_SIDE_RADIUS_FACTOR
        radius_normal = diameter.to_f * ROUND_HUB_NORMAL_RADIUS_FACTOR

        entities = group.entities
        rings = []

        (ROUND_HUB_RINGS + 1).times do |ring_index|
          phi = -Math::PI / 2.0 + Math::PI * ring_index / ROUND_HUB_RINGS.to_f
          normal_component = Math.sin(phi) * radius_normal
          ring_scale = Math.cos(phi)
          ring = []

          ROUND_HUB_SEGMENTS.times do |segment_index|
            theta = Math::PI * 2.0 * segment_index / ROUND_HUB_SEGMENTS.to_f
            forward_component = Math.cos(theta) * radius_forward * ring_scale
            side_component = Math.sin(theta) * radius_side * ring_scale

            ring << Geom::Point3d.new(
              center.x + forward_axis.x * forward_component + side_axis.x * side_component + normal_axis.x * normal_component,
              center.y + forward_axis.y * forward_component + side_axis.y * side_component + normal_axis.y * normal_component,
              center.z + forward_axis.z * forward_component + side_axis.z * side_component + normal_axis.z * normal_component
            )
          end

          rings << ring
        end

        ROUND_HUB_RINGS.times do |ring_index|
          current = rings[ring_index]
          nxt = rings[ring_index + 1]

          ROUND_HUB_SEGMENTS.times do |segment_index|
            next_index = (segment_index + 1) % ROUND_HUB_SEGMENTS

            Mesh.add_quad(
              entities,
              current[segment_index],
              current[next_index],
              nxt[next_index],
              nxt[segment_index]
            )
          end
        end

        Mesh.soft_smooth_round_edges(group) if Mesh.respond_to?(:soft_smooth_round_edges)
      rescue => error
        puts "WyeBuilder.add_round_wye_hub failed: #{error.message}"
      end

      def self.hide_round_wye_internal_edges(group:, center:, forward_axis:, side_axis:, branch_axis:, diameter:, branch_pullout:)
        normal_axis = forward_axis.cross(side_axis)
        return if normal_axis.length == 0
        normal_axis.normalize!

        hide_radius = diameter.to_f * ROUND_INTERNAL_HIDE_RADIUS_FACTOR
        branch_neck_length = diameter.to_f * ROUND_BRANCH_NECK_HIDE_FACTOR

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          midpoint = edge_midpoint(edge)
          next unless midpoint

          vector = center.vector_to(midpoint)
          dist = midpoint.distance(center)

          if dist <= hide_radius
            hide_round_edge(edge)
            next
          end

          along_branch = vector.dot(branch_axis)

          if along_branch >= 0.0 && along_branch <= branch_pullout + branch_neck_length
            closest_on_branch = center.offset(branch_axis, along_branch)
            radial_dist = midpoint.distance(closest_on_branch)
            hide_round_edge(edge) if radial_dist <= diameter.to_f * 0.72
          end
        end
      rescue => error
        puts "WyeBuilder.hide_round_wye_internal_edges failed: #{error.message}"
      end

      def self.add_round_socket_ring(group:, center:, direction:, radius:)
        segments = PipeBuilder::SEGMENTS rescue 32
        axis_a, axis_b = PipeBuilder.circle_basis(direction)
        return unless axis_a && axis_b

        points = PipeBuilder.ring_points(center, axis_a, axis_b, radius, segments)
        entities = group.entities

        segments.times do |index|
          next_index = (index + 1) % segments
          add_visible_edge(entities, points[index], points[next_index])
        end
      rescue => error
        puts "WyeBuilder.add_round_socket_ring failed: #{error.message}"
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

      def self.rectangle_corners(center:, width_axis:, height_axis:, half_width:, half_height:)
        PrimitiveHelpers.rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )
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

      def self.clean_round_branch_visual_edges(group:, start_point:, end_point:, axis:, radius:)
        branch_axis = RectangularFrame.normalized(axis)
        return unless branch_axis

        length = start_point.distance(end_point)
        hide_radius = radius.to_f * ROUND_BRANCH_VISUAL_HIDE_RADIUS_FACTOR

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          midpoint = edge_midpoint(edge)
          next unless midpoint

          start_to_mid = start_point.vector_to(midpoint)
          along = start_to_mid.dot(branch_axis)

          next if along < -0.20
          next if along > length + 0.05

          closest = start_point.offset(branch_axis, along)
          radial_distance = midpoint.distance(closest)

          hide_round_edge(edge) if radial_distance <= hide_radius
        end
      rescue => error
        puts "WyeBuilder.clean_round_branch_visual_edges failed: #{error.message}"
      end

      def self.clean_round_branch_entry_artifacts(
        group:,
        center:,
        side_axis:,
        height_axis:,
        branch_axis:,
        main_half_width:,
        main_half_height:,
        branch_radius:
      )
        side_component = branch_axis.dot(side_axis)
        side_sign = side_component < 0.0 ? -1.0 : 1.0

        sidewall_center = center.offset(side_axis, main_half_width * side_sign)

        wall_tangent = height_axis.cross(side_axis)
        wall_tangent = branch_axis.cross(height_axis) if wall_tangent.length == 0
        return if wall_tangent.length == 0
        wall_tangent.normalize!

        forward_limit = branch_radius.to_f * ROUND_BRANCH_ENTRY_ARTIFACT_FORWARD_FACTOR
        height_limit = [branch_radius.to_f * ROUND_BRANCH_ENTRY_ARTIFACT_HEIGHT_FACTOR, main_half_height].min
        side_limit = branch_radius.to_f * ROUND_BRANCH_ENTRY_ARTIFACT_SIDE_FACTOR

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          midpoint = edge_midpoint(edge)
          next unless midpoint

          v = sidewall_center.vector_to(midpoint)
          tangent_offset = v.dot(wall_tangent)
          height_offset = v.dot(height_axis)
          side_offset = v.dot(side_axis)

          next unless tangent_offset.abs <= forward_limit
          next unless height_offset.abs <= height_limit
          next unless side_offset.abs <= side_limit

          hide_round_edge(edge)
        end
      rescue => error
        puts "WyeBuilder.clean_round_branch_entry_artifacts failed: #{error.message}"
      end

      def self.add_ring_edges(entities, ring)
        ring = Array(ring)
        return if ring.length < 3

        ring.length.times do |index|
          next_index = (index + 1) % ring.length
          add_visible_edge(entities, ring[index], ring[next_index])
        end
      rescue
        nil
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

      def self.hide_round_edge(edge)
        edge.hidden = true
        edge.soft = true if edge.respond_to?(:soft=)
        edge.smooth = true if edge.respond_to?(:smooth=)
      rescue
        nil
      end

      def self.edge_midpoint(edge)
        start_point = edge.start.position
        end_point = edge.end.position

        Geom::Point3d.new(
          (start_point.x + end_point.x) / 2.0,
          (start_point.y + end_point.y) / 2.0,
          (start_point.z + end_point.z) / 2.0
        )
      rescue
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

      def self.perpendicularized(vector, axis)
        VectorMath.perpendicularized(vector, axis)
      end

      private_class_method :build_round
      private_class_method :build_rectangular
      private_class_method :build_rectangular_to_round_wye_body
      private_class_method :build_rectangular_to_rectangular_wye_body
      private_class_method :rectangular_union_wye_layout
      private_class_method :add_sheet_metal_break_lines
      private_class_method :add_round_branch_saddle_edges
      private_class_method :add_round_wye_hub
      private_class_method :hide_round_wye_internal_edges
      private_class_method :add_round_socket_ring
      private_class_method :add_rectangular_socket_ring_edges
      private_class_method :rectangle_corners
      private_class_method :add_profile_outline_edges
      private_class_method :profile_indices_for_edge
      private_class_method :clean_round_branch_visual_edges
      private_class_method :clean_round_branch_entry_artifacts
      private_class_method :add_ring_edges
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
