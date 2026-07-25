module DuctExtension
  module Geometry
    module WyeBuilder
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

      def self.hide_round_edge(edge)
        edge.hidden = true
        edge.soft = true if edge.respond_to?(:soft=)
        edge.smooth = true if edge.respond_to?(:smooth=)
      rescue
        nil
      end

      def self.edge_midpoint(edge)
        PrimitiveHelpers.edge_midpoint(edge)
      end

    end
  end
end
