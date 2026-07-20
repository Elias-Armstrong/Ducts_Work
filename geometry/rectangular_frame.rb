module DuctExtension
  module Geometry
    module RectangularFrame
      EPSILON = 0.000001

      WORLD_X = Geom::Vector3d.new(1, 0, 0)
      WORLD_Y = Geom::Vector3d.new(0, 1, 0)
      WORLD_Z = Geom::Vector3d.new(0, 0, 1)

      HORIZONTAL_AXIS_MAX_Z_DOT = 0.20
      MIN_RELEVEL_UP_PROJECTION = 0.72

      # Basic basis builder.
      #
      # Rule:
      # - If a preferred rectangular frame is supplied, preserve it.
      # - Otherwise choose a safe fallback basis.
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
      def self.transport_basis(
        from_axis:,
        to_axis:,
        width_axis:,
        height_axis: nil
      )
        from_axis = normalized(from_axis)
        to_axis = normalized(to_axis)
        width_axis = normalized(width_axis)
        height_axis = normalized(height_axis)

        return nil unless from_axis && to_axis && width_axis

        angle = from_axis.angle_between(to_axis)

        if angle <= EPSILON
          transported_width = perpendicularized(width_axis, to_axis)
          transported_width ||= basis_for_axis(to_axis)[:width_axis]

          transported_height = to_axis.cross(transported_width)
          return nil if transported_height.length <= EPSILON

          transported_height.normalize!

          return {
            axis: to_axis,
            width_axis: transported_width,
            height_axis: transported_height
          }
        end

        rotation_axis = from_axis.cross(to_axis)

        if rotation_axis.length <= EPSILON
          rotation_axis = perpendicularized(height_axis, from_axis)
          rotation_axis ||= perpendicularized(best_reference_axis(from_axis), from_axis)
        end

        return nil unless rotation_axis
        return nil if rotation_axis.length <= EPSILON

        rotation_axis.normalize!

        transform = Geom::Transformation.rotation(
          Geom::Point3d.new(0, 0, 0),
          rotation_axis,
          angle
        )

        transported_width = width_axis.transform(transform)
        transported_width = perpendicularized(transported_width, to_axis)
        transported_width ||= basis_for_axis(to_axis)[:width_axis]

        transported_height = to_axis.cross(transported_width)
        return nil if transported_height.length <= EPSILON

        transported_height.normalize!

        {
          axis: to_axis,
          width_axis: transported_width,
          height_axis: transported_height
        }
      rescue => error
        puts "RectangularFrame.transport_basis failed: #{error.message}"
        nil
      end

      def self.stable_transport_basis(
        from_axis:,
        to_axis:,
        width_axis:,
        height_axis: nil,
        width: nil,
        height: nil,
        world_up: WORLD_Z,
        allow_relevel: false
      )
        transported = transport_basis(
          from_axis: from_axis,
          to_axis: to_axis,
          width_axis: width_axis,
          height_axis: height_axis
        )

        return transported if transported && !allow_relevel

        stable_basis_for_axis(
          to_axis,
          width,
          height,
          preferred_width_axis: transported && transported[:width_axis],
          preferred_height_axis: transported && transported[:height_axis],
          world_up: world_up,
          allow_relevel: allow_relevel
        )
      rescue => error
        puts "RectangularFrame.stable_transport_basis failed: #{error.message}"
        nil
      end

      def self.legal_transport_basis(
        from_axis:,
        to_axis:,
        width_axis:,
        height_axis: nil,
        width: nil,
        height: nil,
        world_up: WORLD_Z
      )
        stable_transport_basis(
          from_axis: from_axis,
          to_axis: to_axis,
          width_axis: width_axis,
          height_axis: height_axis,
          width: width,
          height: height,
          world_up: world_up,
          allow_relevel: false
        )
      rescue => error
        puts "RectangularFrame.legal_transport_basis failed: #{error.message}"
        nil
      end

      def self.normalized(vector)
        VectorMath.normalized(vector, epsilon: EPSILON)
      end

      def self.point3d(value)
        return value if value.is_a?(Geom::Point3d)

        if value.respond_to?(:to_a)
          Geom::Point3d.new(value.to_a)
        else
          nil
        end
      rescue
        nil
      end

      def self.perpendicularized(vector, axis)
        VectorMath.perpendicularized(vector, axis, epsilon: EPSILON)
      end

      def self.fallback_perpendicular_axis(axis)
        VectorMath.fallback_perpendicular_axis(
          axis,
          epsilon: EPSILON,
          candidates: [WORLD_Z, WORLD_Y, WORLD_X]
        )
      end

      def self.best_reference_axis(axis)
        axis = normalized(axis)
        return WORLD_Z unless axis

        candidates = [WORLD_Z, WORLD_Y, WORLD_X]
        candidates.min_by { |candidate| candidate.dot(axis).abs }
      end
    end
  end
end
