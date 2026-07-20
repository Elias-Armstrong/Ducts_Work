module DuctExtension
  module Geometry
    module TeeBuilder
      SOCKET_DEPTH_FACTOR = 0.82

      # The previous hub was a true sphere at 0.72 diameter. It was stable, but
      # it made every tee look like a ball joint.
      #
      # This oval hub is smaller and direction-aware:
      # - stretched a little along the main run
      # - moderate along the branch
      # - thinner around the side-normal
      #
      # It still overlaps the pipe openings enough to hide cracks without
      # requiring fragile boolean operations.
      HUB_MAIN_RADIUS_FACTOR = 0.62
      HUB_BRANCH_RADIUS_FACTOR = 0.58
      HUB_SIDE_RADIUS_FACTOR = 0.52

      HUB_SEGMENTS = 18
      HUB_RINGS = 8

      EPSILON = 0.000001

      def self.socket_depth(diameter)
        diameter.to_f * SOCKET_DEPTH_FACTOR
      end

      def self.build_into(group, center, main_vector, branch_vector, diameter)
        return false unless group && group.valid?

        center = RectangularFrame.point3d(center)
        main_vector = RectangularFrame.normalized(main_vector)
        branch_vector = RectangularFrame.normalized(branch_vector)
        diameter = diameter.to_f

        return false unless center && main_vector && branch_vector
        return false if diameter <= 0.0
        return false if main_vector.parallel?(branch_vector)

        depth = socket_depth(diameter)

        main_a = center.offset(main_vector.clone.reverse, depth)
        main_b = center.offset(main_vector, depth)
        branch_end = center.offset(branch_vector, depth)

        PipeBuilder.build_into(
          group,
          main_a,
          main_b,
          diameter,
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        PipeBuilder.build_into(
          group,
          center,
          branch_end,
          diameter,
          overlap_start: true,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        add_oval_hub(
          group: group,
          center: center,
          main_vector: main_vector,
          branch_vector: branch_vector,
          diameter: diameter
        )

        true
      rescue => error
        puts "TeeBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.add_oval_hub(group:, center:, main_vector:, branch_vector:, diameter:)
        main_axis = RectangularFrame.normalized(main_vector)
        branch_axis = RectangularFrame.normalized(branch_vector)

        return unless main_axis && branch_axis
        return if main_axis.parallel?(branch_axis)

        side_axis = main_axis.cross(branch_axis)
        return if side_axis.length == 0

        side_axis.normalize!

        # Re-clean the branch axis so the oval basis is exactly perpendicular.
        branch_axis = side_axis.cross(main_axis)
        return if branch_axis.length == 0

        branch_axis.normalize!

        radius_main = diameter.to_f * HUB_MAIN_RADIUS_FACTOR
        radius_branch = diameter.to_f * HUB_BRANCH_RADIUS_FACTOR
        radius_side = diameter.to_f * HUB_SIDE_RADIUS_FACTOR

        entities = group.entities
        points = []

        (HUB_RINGS + 1).times do |ring_index|
          phi = -Math::PI / 2.0 + Math::PI * ring_index / HUB_RINGS.to_f

          side_component = Math.sin(phi) * radius_side
          ring_scale = Math.cos(phi)

          ring = []

          HUB_SEGMENTS.times do |segment_index|
            theta = Math::PI * 2.0 * segment_index / HUB_SEGMENTS.to_f

            main_component = Math.cos(theta) * radius_main * ring_scale
            branch_component = Math.sin(theta) * radius_branch * ring_scale

            point = Geom::Point3d.new(
              center.x +
                main_axis.x * main_component +
                branch_axis.x * branch_component +
                side_axis.x * side_component,

              center.y +
                main_axis.y * main_component +
                branch_axis.y * branch_component +
                side_axis.y * side_component,

              center.z +
                main_axis.z * main_component +
                branch_axis.z * branch_component +
                side_axis.z * side_component
            )

            ring << point
          end

          points << ring
        end

        HUB_RINGS.times do |ring_index|
          current = points[ring_index]
          nxt = points[ring_index + 1]

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
        puts "TeeBuilder.add_oval_hub failed: #{error.message}"
      end

      private_class_method :add_oval_hub
    end
  end
end
