module DuctExtension
  module Geometry
    module RectangularFrame
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

      # Move an already transported rectangular frame partway toward its normal
      # world-up orientation. The caller supplies a maximum amount of roll that
      # the current fitting is allowed to absorb.
      #
      # Straight duct should not use this. It is intended for a fabricated
      # fitting, such as a rolled elbow, where a small controlled roll change is
      # more believable than twisting a long straight duct shell.
      def self.limited_relevel_plan(
        axis:,
        basis:,
        width:,
        height:,
        max_roll:,
        world_up: WORLD_Z,
        minimum_roll: 0.0
      )
        main_axis = normalized(axis)
        return nil unless main_axis && basis

        current_basis = basis_from_preferred_axes(
          main_axis,
          preferred_width_axis: basis[:width_axis],
          preferred_height_axis: basis[:height_axis]
        )
        return nil unless current_basis

        unchanged = {
          start_basis: current_basis,
          end_basis: current_basis,
          roll_angle: 0.0,
          remaining_roll_angle: 0.0,
          relevel: false
        }

        max_roll = max_roll.to_f.abs
        return unchanged if max_roll <= EPSILON

        target_basis = relevel_basis_for_axis(
          main_axis,
          width.to_f,
          height.to_f,
          world_up: world_up
        )
        return unchanged unless target_basis

        target_basis = nearest_equivalent_basis(current_basis, target_basis)
        return unchanged unless target_basis

        desired_roll = signed_roll_angle(
          current_basis[:width_axis],
          target_basis[:width_axis],
          main_axis
        )
        return unchanged unless desired_roll

        minimum_roll = minimum_roll.to_f.abs
        return unchanged if desired_roll.abs <= [minimum_roll, EPSILON].max

        applied_roll = [[desired_roll, max_roll].min, -max_roll].max
        end_basis = rotate_basis_about_axis(current_basis, main_axis, applied_roll)
        return unchanged unless end_basis

        {
          start_basis: current_basis,
          end_basis: end_basis,
          roll_angle: applied_roll,
          remaining_roll_angle: desired_roll - applied_roll,
          relevel: applied_roll.abs > EPSILON
        }
      rescue => error
        puts "RectangularFrame.limited_relevel_plan failed: #{error.message}"
        nil
      end

      def self.nearest_equivalent_basis(reference_basis, candidate_basis)
        return nil unless reference_basis && candidate_basis

        reference_width = normalized(reference_basis[:width_axis])
        candidate_width = normalized(candidate_basis[:width_axis])
        candidate_height = normalized(candidate_basis[:height_axis])

        return nil unless reference_width && candidate_width && candidate_height

        # Reversing both axes describes the same physical rectangle. Use the
        # equivalent frame requiring the smaller roll correction.
        if reference_width.dot(candidate_width) < 0.0
          candidate_width.reverse!
          candidate_height.reverse!
        end

        {
          axis: normalized(candidate_basis[:axis]) || normalized(reference_basis[:axis]),
          width_axis: candidate_width,
          height_axis: candidate_height
        }
      rescue
        nil
      end
      private_class_method :nearest_equivalent_basis

      def self.signed_roll_angle(from_width, to_width, axis)
        axis = normalized(axis)
        from_width = perpendicularized(from_width, axis)
        to_width = perpendicularized(to_width, axis)

        return nil unless from_width && to_width && axis

        angle = from_width.angle_between(to_width)
        return 0.0 if angle <= EPSILON

        cross = from_width.cross(to_width)
        axis.dot(cross) < 0.0 ? -angle : angle
      rescue
        nil
      end
      private_class_method :signed_roll_angle

      def self.rotate_basis_about_axis(basis, axis, angle)
        axis = normalized(axis)
        return nil unless basis && axis

        transform = Geom::Transformation.rotation(
          Geom::Point3d.new(0, 0, 0),
          axis,
          angle.to_f
        )

        width_axis = basis[:width_axis].transform(transform)
        height_axis = basis[:height_axis].transform(transform)

        basis_for_axis(
          axis,
          preferred_width_axis: width_axis,
          preferred_height_axis: height_axis
        )
      rescue
        nil
      end
      private_class_method :rotate_basis_about_axis
    end
  end
end
