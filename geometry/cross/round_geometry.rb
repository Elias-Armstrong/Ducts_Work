module DuctExtension
  module Geometry
    module CrossBuilder
      def self.build_round(group:, center:, forward_vector:, side_vector:, diameter:, branch_diameter: nil)
        return false if diameter <= 0.0

        branch_diameter = branch_diameter.to_f
        branch_diameter = diameter if branch_diameter <= 0.0

        depth = socket_depth([diameter, branch_diameter].max)

        stem_start = center.offset(forward_vector.clone.reverse, depth)
        forward_end = center.offset(forward_vector, depth)
        left_end = center.offset(side_vector.clone.reverse, depth)
        right_end = center.offset(side_vector, depth)

        PipeBuilder.build_into(
          group,
          stem_start,
          forward_end,
          diameter,
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        PipeBuilder.build_into(
          group,
          left_end,
          right_end,
          branch_diameter,
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        add_oval_hub(
          group: group,
          center: center,
          forward_vector: forward_vector,
          side_vector: side_vector,
          diameter: [diameter, branch_diameter].max
        )

        true
      end

      def self.add_oval_hub(group:, center:, forward_vector:, side_vector:, diameter:)
        forward_axis = RectangularFrame.normalized(forward_vector)
        side_axis = RectangularFrame.normalized(side_vector)
        return unless forward_axis && side_axis
        return if forward_axis.parallel?(side_axis)

        normal_axis = forward_axis.cross(side_axis)
        return if normal_axis.length == 0
        normal_axis.normalize!

        side_axis = normal_axis.cross(forward_axis)
        return if side_axis.length == 0
        side_axis.normalize!

        radius_forward = diameter.to_f * HUB_MAIN_RADIUS_FACTOR
        radius_side = diameter.to_f * HUB_SIDE_RADIUS_FACTOR
        radius_normal = diameter.to_f * HUB_NORMAL_RADIUS_FACTOR

        entities = group.entities
        rings = []

        (HUB_RINGS + 1).times do |ring_index|
          phi = -Math::PI / 2.0 + Math::PI * ring_index / HUB_RINGS.to_f
          normal_component = Math.sin(phi) * radius_normal
          ring_scale = Math.cos(phi)

          ring = []

          HUB_SEGMENTS.times do |segment_index|
            theta = Math::PI * 2.0 * segment_index / HUB_SEGMENTS.to_f

            forward_component = Math.cos(theta) * radius_forward * ring_scale
            side_component = Math.sin(theta) * radius_side * ring_scale

            ring << Geom::Point3d.new(
              center.x +
                forward_axis.x * forward_component +
                side_axis.x * side_component +
                normal_axis.x * normal_component,

              center.y +
                forward_axis.y * forward_component +
                side_axis.y * side_component +
                normal_axis.y * normal_component,

              center.z +
                forward_axis.z * forward_component +
                side_axis.z * side_component +
                normal_axis.z * normal_component
            )
          end

          rings << ring
        end

        HUB_RINGS.times do |ring_index|
          current = rings[ring_index]
          nxt = rings[ring_index + 1]

          HUB_SEGMENTS.times do |segment_index|
            next_index = (segment_index + 1) % HUB_SEGMENTS

            Mesh.add_quad(
              entities,
              current[segment_index],
              current[next_index],
              nxt[next_index],
              nxt[segment_index]
            )
          end
        end

        Mesh.soft_smooth_round_edges(group)
        Mesh.apply_material_from_group(group)
      rescue => error
        puts "CrossBuilder.add_oval_hub failed: #{error.message}"
      end

    end
  end
end
