module DuctExtension
  module Geometry
    module RectangularTeeBuilder
      SOCKET_DEPTH_FACTOR = 0.82
      EPSILON = 0.000001

      def self.socket_depth(width, height)
        [width.to_f, height.to_f].max * SOCKET_DEPTH_FACTOR
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
