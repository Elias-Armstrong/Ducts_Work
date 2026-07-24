module DuctExtension
  module Geometry
    module RectangularFrame
      def self.basis_for_axis(
        axis,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        main_axis = normalized(axis)
        return nil unless main_axis

        preferred_basis = basis_from_preferred_axes(
          main_axis,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )

        return preferred_basis if preferred_basis

        reference = best_reference_axis(main_axis)
        width_axis = main_axis.cross(reference)

        return nil if width_axis.length <= EPSILON

        width_axis.normalize!

        height_axis = main_axis.cross(width_axis)
        return nil if height_axis.length <= EPSILON

        height_axis.normalize!

        {
          axis: main_axis,
          width_axis: width_axis,
          height_axis: height_axis
        }
      end

      # Professional rectangular duct orientation rule:
      #
      # 1. If the piece starts from an existing rectangular port, preserve that
      #    port's width/height axes.
      # 2. If there is no existing rectangular frame, use +Z to make mostly
      #    horizontal ducts flat.
      # 3. Do not snap to world X/Y unless absolutely necessary as a fallback.
      #
      # This should stop rectangular pieces from free-swiveling when they are
      # already connected to a valid rectangular start point.
      def self.stable_basis_for_axis(
        axis,
        width = nil,
        height = nil,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        world_up: WORLD_Z,
        allow_relevel: true
      )
        main_axis = normalized(axis)
        return nil unless main_axis

        preferred_basis = basis_from_preferred_axes(
          main_axis,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )

        return preferred_basis if preferred_basis

        if allow_relevel
          relevel_basis = relevel_basis_for_axis(
            main_axis,
            width.to_f,
            height.to_f,
            world_up: world_up
          )

          return relevel_basis if relevel_basis
        end

        basis_for_axis(
          main_axis,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )
      rescue => error
        puts "RectangularFrame.stable_basis_for_axis failed: #{error.message}"
        nil
      end

      # Compatibility helper.
      #
      # Earlier versions tried to force a legal X/Y roll here. That caused the
      # bad swiveling. Now this simply follows stable_basis_for_axis so connected
      # rectangular ducts keep their start-port orientation.
      def self.legal_roll_basis_for_axis(
        axis,
        width = nil,
        height = nil,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        world_up: WORLD_Z
      )
        stable_basis_for_axis(
          axis,
          width,
          height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          world_up: world_up,
          allow_relevel: true
        )
      rescue => error
        puts "RectangularFrame.legal_roll_basis_for_axis failed: #{error.message}"
        nil
      end

      def self.relevel_basis_for_axis(main_axis, width_value, height_value, world_up: WORLD_Z)
        main_axis = normalized(main_axis)
        world_up = normalized(world_up)

        return nil unless main_axis && world_up
        return nil unless width_value.to_f > 0.0 && height_value.to_f > 0.0
        return nil if (width_value.to_f - height_value.to_f).abs <= EPSILON

        # +Z only defines a useful rectangular roll for mostly horizontal ducts.
        # For vertical or steep ducts, preserve the incoming frame instead.
        return nil if main_axis.dot(world_up).abs > HORIZONTAL_AXIS_MAX_Z_DOT

        up_axis = perpendicularized(world_up, main_axis)
        return nil unless up_axis
        return nil if up_axis.length < MIN_RELEVEL_UP_PROJECTION

        up_axis.normalize!

        if width_value >= height_value
          # Wider-than-tall duct: height is the thin/up direction when flat.
          height_axis = up_axis
          width_axis = height_axis.cross(main_axis)

          return nil if width_axis.length <= EPSILON

          width_axis.normalize!

          height_axis = main_axis.cross(width_axis)
          return nil if height_axis.length <= EPSILON

          height_axis.normalize!

          if height_axis.dot(world_up) < 0.0
            height_axis.reverse!
            width_axis.reverse!
          end

          return {
            axis: main_axis,
            width_axis: width_axis,
            height_axis: height_axis
          }
        end

        # Taller-than-wide duct: width is the thin/up direction when flat.
        width_axis = up_axis
        height_axis = main_axis.cross(width_axis)

        return nil if height_axis.length <= EPSILON

        height_axis.normalize!

        width_axis = height_axis.cross(main_axis)
        return nil if width_axis.length <= EPSILON

        width_axis.normalize!

        if width_axis.dot(world_up) < 0.0
          width_axis.reverse!
          height_axis.reverse!
        end

        {
          axis: main_axis,
          width_axis: width_axis,
          height_axis: height_axis
        }
      rescue
        nil
      end

      def self.basis_from_preferred_axes(
        main_axis,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        main_axis = normalized(main_axis)
        return nil unless main_axis

        width_axis = perpendicularized(preferred_width_axis, main_axis)
        height_axis = perpendicularized(preferred_height_axis, main_axis)

        if width_axis && height_axis
          rebuilt_height = main_axis.cross(width_axis)
          return nil if rebuilt_height.length <= EPSILON

          rebuilt_height.normalize!

          if rebuilt_height.dot(height_axis) < 0.0
            width_axis.reverse!
            rebuilt_height.reverse!
          end

          return {
            axis: main_axis,
            width_axis: width_axis,
            height_axis: rebuilt_height
          }
        end

        if width_axis
          height_axis = main_axis.cross(width_axis)
          return nil if height_axis.length <= EPSILON

          height_axis.normalize!

          return {
            axis: main_axis,
            width_axis: width_axis,
            height_axis: height_axis
          }
        end

        if height_axis
          width_axis = height_axis.cross(main_axis)
          return nil if width_axis.length <= EPSILON

          width_axis.normalize!

          rebuilt_height = main_axis.cross(width_axis)
          return nil if rebuilt_height.length <= EPSILON

          rebuilt_height.normalize!

          return {
            axis: main_axis,
            width_axis: width_axis,
            height_axis: rebuilt_height
          }
        end

        nil
      rescue
        nil
      end

      def self.rectangle_corners(
        center,
        axis,
        width,
        height,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        basis = basis_for_axis(
          axis,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )

        return [] unless basis

        rectangle_corners_from_basis(
          center,
          basis[:width_axis],
          basis[:height_axis],
          width,
          height
        )
      end

      def self.stable_rectangle_corners(
        center,
        axis,
        width,
        height,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        world_up: WORLD_Z,
        allow_relevel: true
      )
        basis = stable_basis_for_axis(
          axis,
          width,
          height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          world_up: world_up,
          allow_relevel: allow_relevel
        )

        return [] unless basis

        rectangle_corners_from_basis(
          center,
          basis[:width_axis],
          basis[:height_axis],
          width,
          height
        )
      end

      def self.legal_roll_rectangle_corners(
        center,
        axis,
        width,
        height,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        world_up: WORLD_Z
      )
        stable_rectangle_corners(
          center,
          axis,
          width,
          height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          world_up: world_up,
          allow_relevel: true
        )
      end

      def self.rectangle_corners_from_basis(center, width_axis, height_axis, width, height)
        center = point3d(center)
        width_axis = normalized(width_axis)
        height_axis = normalized(height_axis)

        return [] unless center && width_axis && height_axis

        half_width = width.to_f / 2.0
        half_height = height.to_f / 2.0

        [
          center.offset(width_axis, half_width).offset(height_axis, half_height),
          center.offset(width_axis.clone.reverse, half_width).offset(height_axis, half_height),
          center.offset(width_axis.clone.reverse, half_width).offset(height_axis.clone.reverse, half_height),
          center.offset(width_axis, half_width).offset(height_axis.clone.reverse, half_height)
        ]
      end

      # Smoothly carries a rectangular frame from one axis to another.
      # This is the core behavior elbows need.
    end
  end
end
