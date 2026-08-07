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

      def self.build_into(
        group,
        center,
        main_vector,
        branch_vector,
        diameter,
        main_depth: nil,
        branch_depth: nil
      )
        return false unless group && group.valid?

        center = RectangularFrame.point3d(center)
        main_vector = RectangularFrame.normalized(main_vector)
        branch_vector = RectangularFrame.normalized(branch_vector)
        diameter = diameter.to_f

        return false unless center && main_vector && branch_vector
        return false if diameter <= 0.0
        return false if main_vector.parallel?(branch_vector)

        default_depth = socket_depth(diameter)
        main_depth = main_depth.to_f
        branch_depth = branch_depth.to_f
        main_depth = default_depth if main_depth <= 0.0
        branch_depth = default_depth if branch_depth <= 0.0

        main_a = center.offset(main_vector.clone.reverse, main_depth)
        main_b = center.offset(main_vector, main_depth)
        branch_end = center.offset(branch_vector, branch_depth)

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

# ===== Consolidated from: geometry/rectangular_tee_builder.rb =====
module DuctExtension
  module Geometry
    module RectangularTeeBuilder
      SOCKET_DEPTH_FACTOR = 0.82
      SIDE_TAKEOFF_BRANCH_DEPTH_FACTOR = 0.16
      SIDE_TAKEOFF_BRANCH_DEPTH_MIN = 1.0
      EPSILON = 0.000001

      def self.socket_depth(width, height)
        [width.to_f, height.to_f].max * SOCKET_DEPTH_FACTOR
      end

      def self.side_takeoff_branch_depth(width, height)
        [
          [width.to_f, height.to_f].max * SIDE_TAKEOFF_BRANCH_DEPTH_FACTOR,
          SIDE_TAKEOFF_BRANCH_DEPTH_MIN
        ].max
      end

      # The branch shell and the branch Port must use the exact same frame.
      # Width follows the main run; height is the remaining perpendicular axis.
      def self.branch_basis(main_axis, branch_axis, main_basis: nil)
        main_axis = VectorMath.normalized(main_axis)
        branch_axis = VectorMath.normalized(branch_axis)
        return nil unless main_axis && branch_axis

        width_axis = VectorMath.perpendicularized(main_axis, branch_axis)
        return nil unless width_axis

        height_axis = branch_axis.cross(width_axis)
        return nil if height_axis.length <= EPSILON
        height_axis.normalize!

        if main_basis
          remaining_axis =
            if branch_axis.dot(main_basis[:width_axis]).abs >= branch_axis.dot(main_basis[:height_axis]).abs
              main_basis[:height_axis]
            else
              main_basis[:width_axis]
            end

          if remaining_axis && height_axis.dot(remaining_axis) < 0.0
            width_axis.reverse!
            height_axis.reverse!
          end
        end

        { axis: branch_axis, width_axis: width_axis, height_axis: height_axis }
      rescue
        nil
      end

      # Build a robust rectangular T from two open rectangular duct shells.
      # The caller already owns the topology/ports; this builder only creates
      # geometry at the exact socket locations supplied by the insertion service.
      # Reusing RectangularPipeBuilder removes a large second implementation of
      # rectangular frames and prevents malformed custom tee faces on angled runs.
      def self.build_into(
        group,
        center,
        branch_base,
        main_vector,
        branch_vector,
        width,
        height,
        socket_depth = nil,
        branch_depth: nil,
        preferred_main_width_axis: nil,
        preferred_main_height_axis: nil
      )
        return false unless group && group.valid?

        center = RectangularFrame.point3d(center)
        branch_base = RectangularFrame.point3d(branch_base)
        main_axis = VectorMath.normalized(main_vector)
        branch_axis = VectorMath.normalized(branch_vector)
        width = width.to_f
        height = height.to_f
        depth = socket_depth ? socket_depth.to_f : self.socket_depth(width, height)
        branch_depth = branch_depth ? branch_depth.to_f : depth

        return false unless center && branch_base && main_axis && branch_axis
        return false if width <= 0.0 || height <= 0.0 || depth <= EPSILON
        return false if branch_depth <= EPSILON
        return false if main_axis.parallel?(branch_axis)

        # Make the requested branch vector agree with the supplied branch-base
        # location. This keeps manually inserted and end tees consistent.
        toward_base = center.vector_to(branch_base)
        if toward_base.length > EPSILON && toward_base.dot(branch_axis) < 0.0
          branch_axis.reverse!
        end

        main_basis = RectangularFrame.stable_basis_for_axis(
          main_axis,
          width,
          height,
          preferred_width_axis: preferred_main_width_axis,
          preferred_height_axis: preferred_main_height_axis,
          allow_relevel: false
        )
        return false unless main_basis

        main_start = center.offset(main_axis.clone.reverse, depth)
        main_end = center.offset(main_axis, depth)
        branch_end = branch_base.offset(branch_axis, branch_depth)

        main_ok = RectangularPipeBuilder.build_into(
          group,
          main_start,
          main_end,
          width,
          height,
          cap_start: false,
          cap_end: false,
          preferred_width_axis: main_basis[:width_axis],
          preferred_height_axis: main_basis[:height_axis],
          allow_relevel: false
        )
        return false unless main_ok

        branch_basis = self.branch_basis(main_axis, branch_axis, main_basis: main_basis)
        return false unless branch_basis

        RectangularPipeBuilder.build_into(
          group,
          branch_base,
          branch_end,
          width,
          height,
          cap_start: false,
          cap_end: false,
          preferred_width_axis: branch_basis[:width_axis],
          preferred_height_axis: branch_basis[:height_axis],
          allow_relevel: false
        )
      rescue => error
        puts "RectangularTeeBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end
    end
  end
end
