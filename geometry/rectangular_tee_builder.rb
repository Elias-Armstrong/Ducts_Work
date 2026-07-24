module DuctExtension
  module Geometry
    module RectangularTeeBuilder
      SOCKET_DEPTH_FACTOR = 0.82
      EPSILON = 0.000001

      def self.socket_depth(width, height)
        [width.to_f, height.to_f].max * SOCKET_DEPTH_FACTOR
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

        return false unless center && branch_base && main_axis && branch_axis
        return false if width <= 0.0 || height <= 0.0 || depth <= EPSILON
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
        branch_end = branch_base.offset(branch_axis, depth)

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

        # Across the branch opening, the main-run axis is the most stable width
        # reference. The cross product supplies a perpendicular height axis.
        branch_width_axis = VectorMath.perpendicularized(main_axis, branch_axis)
        branch_height_axis = branch_axis.cross(branch_width_axis) if branch_width_axis
        branch_height_axis.normalize! if branch_height_axis && branch_height_axis.length > EPSILON

        RectangularPipeBuilder.build_into(
          group,
          branch_base,
          branch_end,
          width,
          height,
          cap_start: false,
          cap_end: false,
          preferred_width_axis: branch_width_axis,
          preferred_height_axis: branch_height_axis,
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
