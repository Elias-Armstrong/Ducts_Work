module DuctExtension
  module Tool
    module DuctToolNavigation
      private

      def middle_mouse_down?(flags)
        return false unless flags

        (flags.to_i & MK_MBUTTON_VALUE.to_i) != 0
      rescue
        false
      end

      def shift_down?(flags)
        return false unless flags

        (flags.to_i & SHIFT_MODIFIER_VALUE.to_i) != 0
      rescue
        false
      end

      def ctrl_down?(flags)
        return false unless flags

        (flags.to_i & CONTROL_MODIFIER_VALUE.to_i) != 0
      rescue
        false
      end

      def orbit_view(view, x, y)
        return unless view
        return unless @orbit_last_x && @orbit_last_y

        dx = x.to_f - @orbit_last_x.to_f
        dy = y.to_f - @orbit_last_y.to_f

        @orbit_last_x = x
        @orbit_last_y = y

        return if dx.abs < 0.001 && dy.abs < 0.001

        camera = view.camera
        return unless camera

        target = orbit_target_point(camera)
        eye = camera.eye
        up = camera.up

        return unless target && eye && up

        yaw_angle = -dx * ORBIT_SENSITIVITY
        pitch_angle = -dy * ORBIT_SENSITIVITY

        world_up = Geom::Vector3d.new(0, 0, 1)

        yaw_transform = Geom::Transformation.rotation(
          target,
          world_up,
          yaw_angle
        )

        new_eye = eye.transform(yaw_transform)
        new_up = up.transform(yaw_transform)

        target_to_eye = target.vector_to(new_eye)
        return if target_to_eye.length == 0

        right_axis = new_up.cross(target_to_eye)

        if right_axis.length == 0
          right_axis = Geom::Vector3d.new(1, 0, 0)
        end

        right_axis.normalize!

        pitch_transform = Geom::Transformation.rotation(
          target,
          right_axis,
          pitch_angle
        )

        final_eye = new_eye.transform(pitch_transform)
        final_up = new_up.transform(pitch_transform)

        final_target_to_eye = target.vector_to(final_eye)
        return if final_target_to_eye.length < 0.001

        final_up = safe_camera_up(final_up, final_target_to_eye)

        camera.set(final_eye, target, final_up)

        view.invalidate
      rescue => error
        puts "Orbit failed: #{error.message}"
        puts error.backtrace.join("\n")
      end

      def orbit_target_point(camera)
        active = active_route_start_point
        return active if active

        if camera.respond_to?(:target) && camera.target
          camera.target
        else
          Geom::Point3d.new(0, 0, 0)
        end
      rescue
        active_route_start_point || Geom::Point3d.new(0, 0, 0)
      end

      def safe_camera_up(up_vector, target_to_eye)
        up = up_vector.clone
        view_axis = target_to_eye.clone

        return Geom::Vector3d.new(0, 0, 1) if up.length == 0
        return Geom::Vector3d.new(0, 0, 1) if view_axis.length == 0

        up.normalize!
        view_axis.normalize!

        dot = up.dot(view_axis)

        cleaned = Geom::Vector3d.new(
          up.x - view_axis.x * dot,
          up.y - view_axis.y * dot,
          up.z - view_axis.z * dot
        )

        if cleaned.length < 0.001
          fallback = Geom::Vector3d.new(0, 0, 1)
          dot = fallback.dot(view_axis)

          cleaned = Geom::Vector3d.new(
            fallback.x - view_axis.x * dot,
            fallback.y - view_axis.y * dot,
            fallback.z - view_axis.z * dot
          )
        end

        cleaned.normalize! if cleaned.length > 0
        cleaned
      rescue
        Geom::Vector3d.new(0, 0, 1)
      end

    end
  end
end
