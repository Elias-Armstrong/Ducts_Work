module DuctExtension
  module Geometry
    module RectangularFrame
      RELEVEL_MIN_ANGLE = 4.0 * Math::PI / 180.0
      RELEVEL_MIN_LENGTH_FACTOR = 1.50
      RELEVEL_QUARTER_TURN_LENGTH_FACTOR = 3.00
      RELEVEL_DEGREES_PER_SEGMENT = 7.5
      RELEVEL_MIN_SEGMENTS = 4
      RELEVEL_MAX_SEGMENTS = 16

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

      # Build a frame plan for a straight rectangular run.
      #
      # A connected run must begin with the exact incoming frame or its first face
      # will not match the source socket. If the run is sufficiently long and
      # mostly horizontal, the far end may gradually roll back to the normal
      # world-up orientation. Short runs preserve the incoming frame unchanged.
      def self.straight_run_plan(
        axis:,
        length:,
        width:,
        height:,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        world_up: WORLD_Z,
        allow_relevel: true
      )
        main_axis = normalized(axis)
        return nil unless main_axis

        width_value = width.to_f
        height_value = height.to_f
        length_value = length.to_f

        return nil if width_value <= 0.0 || height_value <= 0.0
        return nil if length_value <= EPSILON

        start_basis = basis_from_preferred_axes(
          main_axis,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )

        start_basis ||= stable_basis_for_axis(
          main_axis,
          width_value,
          height_value,
          world_up: world_up,
          allow_relevel: true
        )

        return nil unless start_basis

        unchanged = {
          start_basis: start_basis,
          end_basis: start_basis,
          roll_angle: 0.0,
          segments: 1,
          relevel: false
        }

        return unchanged unless allow_relevel

        target_basis = relevel_basis_for_axis(
          main_axis,
          width_value,
          height_value,
          world_up: world_up
        )
        return unchanged unless target_basis

        target_basis = nearest_equivalent_basis(start_basis, target_basis)
        return unchanged unless target_basis

        roll_angle = signed_roll_angle(
          start_basis[:width_axis],
          target_basis[:width_axis],
          main_axis
        )
        return unchanged unless roll_angle
        return unchanged if roll_angle.abs < RELEVEL_MIN_ANGLE

        largest = [width_value, height_value].max
        required_length = relevel_required_length(largest, roll_angle.abs)
        return unchanged if length_value + EPSILON < required_length

        segment_angle = RELEVEL_DEGREES_PER_SEGMENT * Math::PI / 180.0
        segments = (roll_angle.abs / segment_angle).ceil
        segments = [segments, RELEVEL_MIN_SEGMENTS].max
        segments = [segments, RELEVEL_MAX_SEGMENTS].min

        {
          start_basis: start_basis,
          end_basis: target_basis,
          roll_angle: roll_angle,
          segments: segments,
          relevel: true,
          required_length: required_length
        }
      rescue => error
        puts "RectangularFrame.straight_run_plan failed: #{error.message}"
        nil
      end

      def self.nearest_equivalent_basis(reference_basis, candidate_basis)
        return nil unless reference_basis && candidate_basis

        reference_width = normalized(reference_basis[:width_axis])
        candidate_width = normalized(candidate_basis[:width_axis])
        candidate_height = normalized(candidate_basis[:height_axis])

        return nil unless reference_width && candidate_width && candidate_height

        # Reversing both rectangular axes describes the same physical rectangle.
        # Choose that equivalent orientation when it avoids an unnecessary turn
        # greater than 90 degrees.
        if reference_width.dot(candidate_width) < 0.0
          candidate_width.reverse!
          candidate_height.reverse!
        end

        {
          axis: candidate_basis[:axis],
          width_axis: candidate_width,
          height_axis: candidate_height
        }
      rescue
        nil
      end
      private_class_method :nearest_equivalent_basis

      def self.signed_roll_angle(from_width, to_width, axis)
        from_width = perpendicularized(from_width, axis)
        to_width = perpendicularized(to_width, axis)
        axis = normalized(axis)

        return nil unless from_width && to_width && axis

        angle = from_width.angle_between(to_width)
        return 0.0 if angle <= EPSILON

        cross = from_width.cross(to_width)
        sign = axis.dot(cross) < 0.0 ? -1.0 : 1.0
        angle * sign
      rescue
        nil
      end
      private_class_method :signed_roll_angle

      def self.relevel_required_length(largest_dimension, absolute_angle)
        quarter_turn_fraction = absolute_angle.to_f / (Math::PI / 2.0)
        angle_factor = RELEVEL_QUARTER_TURN_LENGTH_FACTOR * quarter_turn_fraction
        largest_dimension.to_f * [RELEVEL_MIN_LENGTH_FACTOR, angle_factor].max
      rescue
        largest_dimension.to_f * RELEVEL_MIN_LENGTH_FACTOR
      end
      private_class_method :relevel_required_length
    end
  end
end

