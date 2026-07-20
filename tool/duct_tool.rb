module DuctExtension
  module Tool
    class DuctTool
      DEFAULT_LENGTH_INCREMENT = 0.25

      KEY_LEFT  = defined?(VK_LEFT)  ? VK_LEFT  : 37
      KEY_UP    = defined?(VK_UP)    ? VK_UP    : 38
      KEY_RIGHT = defined?(VK_RIGHT) ? VK_RIGHT : 39
      KEY_DOWN  = defined?(VK_DOWN)  ? VK_DOWN  : 40
      KEY_RETURN = defined?(VK_RETURN) ? VK_RETURN : 13
      KEY_ENTER  = defined?(VK_ENTER)  ? VK_ENTER  : 13
      KEY_BACK   = defined?(VK_BACK)   ? VK_BACK   : 8
      KEY_DELETE = defined?(VK_DELETE) ? VK_DELETE : 46
      KEY_ESCAPE = defined?(VK_ESCAPE) ? VK_ESCAPE : 27

      PREVIEW_ROUND_SEGMENTS = 16
      PREVIEW_MIN_LENGTH = 0.001

      # Lower = slower orbit.
      ORBIT_SENSITIVITY = 0.004

      MK_MBUTTON_VALUE =
        if defined?(MK_MBUTTON)
          MK_MBUTTON
        else
          16
        end

      SHIFT_MODIFIER_VALUE =
        if defined?(CONSTRAIN_MODIFIER_MASK)
          CONSTRAIN_MODIFIER_MASK
        elsif defined?(MK_SHIFT)
          MK_SHIFT
        else
          4
        end

      CONTROL_MODIFIER_VALUE =
        if defined?(COPY_MODIFIER_MASK)
          COPY_MODIFIER_MASK
        elsif defined?(MK_CONTROL)
          MK_CONTROL
        else
          8
        end

      @@last_duct_shape = :round
      @@last_diameter = 8.0
      @@last_width = 12.0
      @@last_height = 8.0
      @@last_length_increment = DEFAULT_LENGTH_INCREMENT
      @@last_round_tee_side_mode = :from_click

      @@last_reducer_round_diameter = 10.0
      @@last_reducer_rectangular_width = 16.0
      @@last_reducer_rectangular_height = 10.0
      @@last_reducer_length = 0.0

      def initialize
        @network = ::DuctExtension.network_for_model(Sketchup.active_model)

        @start_point = nil
        @last_port = nil

        @duct_shape = @@last_duct_shape
        @current_diameter = @@last_diameter
        @current_width = @@last_width
        @current_height = @@last_height
        @length_increment = @@last_length_increment
        @round_tee_side_mode = @@last_round_tee_side_mode

        @fitting_mode = :elbow
        @orthogonal_axis_lock = nil

        @current_ip = Sketchup::InputPoint.new
        @last_mouse_x = nil
        @last_mouse_y = nil

        @middle_orbiting = false
        @shift_left_orbiting = false
        @orbit_last_x = nil
        @orbit_last_y = nil

        @typed_length_buffer = ""
      end

      def activate
        prompts = [
          "Duct Shape:",
          "Round Diameter (Inches):",
          "Rectangular Width (Inches):",
          "Rectangular Height (Inches):",
          "Length Increment:"
        ]

        defaults = [
          shape_label(@duct_shape),
          @current_diameter.to_s,
          @current_width.to_s,
          @current_height.to_s,
          increment_label(@length_increment)
        ]

        lists = [
          "Round|Rectangular",
          "",
          "",
          "",
          "1/4 inch|1/2 inch|1 inch"
        ]

        input = ::UI.inputbox(
          prompts,
          defaults,
          lists,
          "Orthogonal Duct Settings"
        )

        @network = Services::NetworkRebuildService.rebuild(Sketchup.active_model)
        Sketchup.set_status_text("Orthogonal Duct Tool active.")

        unless input
          Sketchup.active_model.select_tool(nil)
          return
        end

        @duct_shape = normalize_shape(input[0])
        @current_diameter = positive_number(input[1], @current_diameter)
        @current_width = positive_number(input[2], @current_width)
        @current_height = positive_number(input[3], @current_height)
        @length_increment = normalize_increment(input[4])

        if @duct_shape == :round
          @current_width = @current_diameter
          @current_height = @current_diameter
        end

        @@last_duct_shape = @duct_shape
        @@last_diameter = @current_diameter
        @@last_width = @current_width
        @@last_height = @current_height
        @@last_length_increment = @length_increment
        @@last_round_tee_side_mode = @round_tee_side_mode

        @start_point = nil
        @last_port = nil
        @orthogonal_axis_lock = nil
        @last_mouse_x = nil
        @last_mouse_y = nil

        @middle_orbiting = false
        @shift_left_orbiting = false
        @orbit_last_x = nil
        @orbit_last_y = nil
        reset_typed_length

        update_status_for_current_shape
      end

      def getMenu(menu, flags, x, y, view)
        menu.add_item("Mode: Auto-Elbow") {
          @fitting_mode = :elbow
          update_status_for_current_shape
        }

        menu.add_item("Mode: Straight Only") {
          @fitting_mode = :straight
          update_status_for_current_shape
        }

        menu.add_separator

        components_menu = menu.add_submenu("New Components")

        components_menu.add_item("Add Tee") {
          @fitting_mode = :tee
          @round_tee_side_mode = :from_click
          @@last_round_tee_side_mode = @round_tee_side_mode
          update_status_for_current_shape
        }

        components_menu.add_item("End Tee") {
          @fitting_mode = :end_tee
          @round_tee_side_mode = :from_click
          @@last_round_tee_side_mode = @round_tee_side_mode
          update_status_for_current_shape
        }

        components_menu.add_item("End Cross") {
          @fitting_mode = :end_cross
          update_status_for_current_shape
        }

        components_menu.add_item("End Wye") {
          @fitting_mode = :end_wye
          update_status_for_current_shape
        }

        components_menu.add_item("End Increaser / Reducer") {
          @fitting_mode = :end_reducer
          update_status_for_current_shape
        }

        components_menu.add_item("Add Vent") {
          @fitting_mode = :vent
          update_status_for_current_shape
          Sketchup.status_text = "Add Vent mode: click near a pipe end for a cover, or click the side for a register."
        }

        menu.add_separator

        axis_menu = menu.add_submenu("Lock Axis")

        axis_menu.add_item("Clear") {
          @orthogonal_axis_lock = nil
          update_status_for_current_shape
        }

        axis_menu.add_item("Up / +Z") {
          toggle_orthogonal_axis_lock(:positive_z)
          update_status_for_current_shape
        }

        axis_menu.add_item("Down / -Z") {
          toggle_orthogonal_axis_lock(:negative_z)
          update_status_for_current_shape
        }

        axis_menu.add_item("X") {
          toggle_orthogonal_axis_lock(:x)
          update_status_for_current_shape
        }

        axis_menu.add_item("Y") {
          toggle_orthogonal_axis_lock(:y)
          update_status_for_current_shape
        }

        length_menu = menu.add_submenu("Length Increment")

        length_menu.add_item("1/4 inch") {
          @length_increment = 0.25
          @@last_length_increment = @length_increment
          update_status_for_current_shape
        }

        length_menu.add_item("1/2 inch") {
          @length_increment = 0.5
          @@last_length_increment = @length_increment
          update_status_for_current_shape
        }

        length_menu.add_item("1 inch") {
          @length_increment = 1.0
          @@last_length_increment = @length_increment
          update_status_for_current_shape
        }
      end

      def onCancel(reason, view)
        @start_point = nil
        @last_port = nil
        @orthogonal_axis_lock = nil
        @last_mouse_x = nil
        @last_mouse_y = nil

        @middle_orbiting = false
        @shift_left_orbiting = false
        @orbit_last_x = nil
        @orbit_last_y = nil
        reset_typed_length

        update_status_for_current_shape
        view.invalidate if view
      end

      def onMButtonDown(flags, x, y, view)
        @middle_orbiting = true
        @orbit_last_x = x
        @orbit_last_y = y
        Sketchup.status_text = "Middle mouse orbit. Release middle mouse to continue duct drawing."
        view.invalidate if view
        true
      end

      def onMButtonUp(flags, x, y, view)
        @middle_orbiting = false
        @orbit_last_x = nil
        @orbit_last_y = nil
        update_status_for_current_shape
        view.invalidate if view
        true
      end

      def onMouseMove(flags, x, y, view)
        @last_mouse_x = x
        @last_mouse_y = y

        middle_down = middle_mouse_down?(flags)

        if @shift_left_orbiting || middle_down
          unless @middle_orbiting || @shift_left_orbiting
            @middle_orbiting = true
            @orbit_last_x = x
            @orbit_last_y = y
            Sketchup.status_text = "Orbiting around active duct point. Release mouse to continue duct drawing."
            view.invalidate if view
            return
          end

          orbit_view(view, x, y)
          view.invalidate if view
          return
        elsif @middle_orbiting
          @middle_orbiting = false
          @orbit_last_x = nil
          @orbit_last_y = nil
          update_status_for_current_shape
          view.invalidate if view
          return
        end

        @current_ip.pick(view, x, y)
        update_length_status(view, x, y)

        view.invalidate
      end

      def onKeyDown(key, repeat, flags, view)
        case key
        when KEY_UP
          toggle_orthogonal_axis_lock(:positive_z)
          update_status_for_current_shape
          view.invalidate if view
          return
        when KEY_DOWN
          toggle_orthogonal_axis_lock(:negative_z)
          update_status_for_current_shape
          view.invalidate if view
          return
        when KEY_RIGHT
          toggle_orthogonal_axis_lock(:x)
          update_status_for_current_shape
          view.invalidate if view
          return
        when KEY_LEFT
          toggle_orthogonal_axis_lock(:y)
          update_status_for_current_shape
          view.invalidate if view
          return
        end

        return if handle_typed_length_key(key, view)
      end

      def draw(view)
        start = active_route_start_point
        return unless start

        raw_point = preview_raw_point(view, start)
        return unless raw_point

        snapped_port = typed_length_active? ? nil : current_preview_snapped_port(view, raw_point)

        draw_point =
          if typed_length_active?
            typed_length_preview_point(start, raw_point)
          elsif snapped_port
            snapped_port.point
          else
            pending_build_point(start, raw_point)
          end

        return unless draw_point
        return if start.distance(draw_point) < PREVIEW_MIN_LENGTH

        draw_preview_centerline(view, start, draw_point, snapped_port)
        draw_ghost_duct_preview(view, start, draw_point, snapped_port)
      rescue => error
        puts "Orthogonal duct preview failed: #{error.message}"
      end

      def onLButtonDown(flags, x, y, view)
        if shift_down?(flags)
          @shift_left_orbiting = true
          @orbit_last_x = x
          @orbit_last_y = y
          Sketchup.status_text = "Shift + left drag orbit around active duct point. Release left mouse to continue duct drawing."
          view.invalidate if view
          return true
        end

        if ctrl_down?(flags)
          handle_connector_swing_click(view, x, y)
          view.invalidate if view
          return true
        end

        @last_mouse_x = x
        @last_mouse_y = y

        ip = Sketchup::InputPoint.new
        ip.pick(view, x, y)

        clicked_point = ip.position
        return unless clicked_point

        point = clicked_point

        if @fitting_mode == :end_tee
          handle_end_tee_click(view, x, y, clicked_point)
          view.invalidate
          return
        end

        if @fitting_mode == :end_cross
          handle_end_cross_click(view, x, y, clicked_point)
          view.invalidate
          return
        end

        if @fitting_mode == :end_wye
          handle_end_wye_click(view, x, y, clicked_point)
          view.invalidate
          return
        end

        if @fitting_mode == :end_reducer
          handle_end_reducer_click(view, x, y, clicked_point)
          view.invalidate
          return
        end

        if @fitting_mode == :tee
          handle_manual_tee_click(view, x, y, clicked_point)
          view.invalidate
          return
        end

        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: clicked_point
        )

        snapped_port = snap&.port

        if snapped_port
          Services::TeeInsertService.remove_cap_for_port(snapped_port)
          point = snapped_port.point
          copy_dimensions_from_port(snapped_port)
          puts "Orthogonal DuctTool snapped to #{snapped_port.piece.type} port at #{snapped_port.point}"
        else
          puts "Orthogonal DuctTool found no open external port snap."
        end

        if @last_port || @start_point
          Services::TeeInsertService.remove_cap_for_port(@last_port) if @last_port

          route_start = active_route_start_point
          build_point = point

          if route_start && !snapped_port
            raw_click = click_route_point(view, x, y, route_start, clicked_point)
            build_point =
              if typed_length_active?
                typed_length_preview_point(route_start, raw_click) || pending_build_point(route_start, raw_click)
              else
                pending_build_point(route_start, raw_click)
              end
          end

          if snapped_port && snapped_port != @last_port
            result = connect_to_target_port(snapped_port)

            if result
              finish_connection(view, "Connected into open port.")
              return
            end
          end

          auto_tee_result = nil

          unless snapped_port
            unless @last_port && @last_port.piece && @last_port.piece.type == :tee
              auto_tee_result = try_auto_tee_target(view, x, y, clicked_point)
            end
          end

          if auto_tee_result && auto_tee_result[:branch_port]
            result = connect_to_target_port(auto_tee_result[:branch_port])

            if result
              finish_connection(view, "Connected into duct with tee.")
              return
            end

            build_point = auto_tee_result[:branch_port].point
            copy_dimensions_from_port(auto_tee_result[:branch_port])
          end

          steps = Services::RoutePlanner.plan(
            network: @network,
            start_port: @last_port,
            start_point: @start_point,
            target_point: build_point,
            diameter: @current_diameter,
            shape: @duct_shape,
            width: @current_width,
            height: @current_height,
            fitting_mode: @fitting_mode
          )

          result = Services::GeometryExecutor.execute(
            Sketchup.active_model,
            steps,
            @network
          )

          if result
            @last_port = result[:last_port]
            @start_point = nil
          end

          reset_typed_length
          @orthogonal_axis_lock = nil
          @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
        else
          if snapped_port
            @last_port = snapped_port
            @start_point = nil
            @orthogonal_axis_lock = nil
            reset_typed_length
            copy_dimensions_from_port(snapped_port)

            Sketchup.status_text =
              "Snapped to open #{snapped_port.piece.type} port. Click next orthogonal point."
          else
            @start_point = clicked_point
            @last_port = nil
            @orthogonal_axis_lock = nil
            reset_typed_length
          end
        end

        view.invalidate
      end

      def onLButtonUp(flags, x, y, view)
        if @shift_left_orbiting
          @shift_left_orbiting = false
          @orbit_last_x = nil
          @orbit_last_y = nil
          update_status_for_current_shape
          view.invalidate if view
          return true
        end

        false
      end

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

      def handle_typed_length_key(key, view)
        key_code = key.to_i

        case key_code
        when KEY_RETURN, KEY_ENTER
          return false unless typed_length_active?

          commit_typed_length(view)
          return true
        when KEY_BACK
          return false unless typed_length_active?

          @typed_length_buffer = @typed_length_buffer[0...-1].to_s
          update_typed_length_status(view)
          view.invalidate if view
          return true
        when KEY_DELETE, KEY_ESCAPE
          return false unless typed_length_active?

          reset_typed_length
          update_status_for_current_shape
          view.invalidate if view
          return true
        end

        character = typed_length_character_for_key(key_code)
        return false unless character

        return true unless active_route_start_point
        return true unless typed_length_character_allowed?(character)

        @typed_length_buffer << character
        update_typed_length_status(view)
        view.invalidate if view
        true
      rescue => error
        puts "Typed length key failed: #{error.message}"
        false
      end

      def typed_length_character_for_key(key_code)
        if key_code >= 48 && key_code <= 57
          return (key_code - 48).to_s
        end

        if key_code >= 96 && key_code <= 105
          return (key_code - 96).to_s
        end

        case key_code
        when 39, 222
          "'"
        when 190, 110
          "."
        else
          nil
        end
      end

      def typed_length_character_allowed?(character)
        buffer = @typed_length_buffer.to_s

        case character
        when "'"
          !buffer.include?("'")
        when "."
          current_part = buffer.include?("'") ? buffer.split("'", 2)[1].to_s : buffer
          !current_part.include?(".")
        else
          true
        end
      end

      def typed_length_active?
        !@typed_length_buffer.to_s.empty?
      end

      def reset_typed_length
        @typed_length_buffer = ""
      end

      def typed_length_total_inches
        buffer = @typed_length_buffer.to_s.strip
        return nil if buffer.empty?

        if buffer.include?("'")
          feet_text, inch_text = buffer.split("'", 2)
          feet = feet_text.to_s.empty? ? 0.0 : feet_text.to_f
          inches = inch_text.to_s.empty? ? 0.0 : inch_text.to_f
          total = (feet * 12.0) + inches
        else
          total = buffer.to_f * 12.0
        end

        total > 0.0 ? total : nil
      rescue
        nil
      end

      def typed_length_preview_point(start_point, raw_point)
        length = typed_length_total_inches
        return nil unless start_point && raw_point && length

        direction = typed_length_direction(start_point, raw_point)
        return nil unless direction

        start_point.offset(direction, length)
      end

      def typed_length_direction(start_point, raw_point)
        vector = start_point.vector_to(raw_point)

        if vector.length < PREVIEW_MIN_LENGTH
          vector = fallback_typed_length_direction
        end

        return nil unless vector
        return nil if vector.length == 0

        direction = vector.clone
        direction.normalize!

        if @orthogonal_axis_lock
          forced_axis_direction(direction)
        else
          nearest_allowed_route_direction(direction)
        end
      rescue
        nil
      end

      def fallback_typed_length_direction
        if @last_port && @last_port.respond_to?(:outward_vector) && @last_port.outward_vector
          vector = @last_port.outward_vector.clone
          return vector if vector.length > 0
        end

        if @last_port && @last_port.respond_to?(:vector) && @last_port.vector
          vector = @last_port.vector.clone
          return vector if vector.length > 0
        end

        Geom::Vector3d.new(1, 0, 0)
      rescue
        Geom::Vector3d.new(1, 0, 0)
      end

      def typed_length_status_text
        total = typed_length_total_inches
        return @typed_length_buffer.to_s unless total

        "#{@typed_length_buffer} = #{format_length_increment(total)}"
      end

      def update_typed_length_status(view)
        if view && @last_mouse_x && @last_mouse_y
          update_length_status(view, @last_mouse_x, @last_mouse_y)
        else
          update_status_for_current_shape
        end
      end

      def commit_typed_length(view)
        start = active_route_start_point
        return false unless start

        raw_point = preview_raw_point(view, start)
        raw_point ||= start.offset(fallback_typed_length_direction, 1.0)

        build_point = typed_length_preview_point(start, raw_point)
        return false unless build_point
        return false if start.distance(build_point) < PREVIEW_MIN_LENGTH

        Services::TeeInsertService.remove_cap_for_port(@last_port) if @last_port

        steps = Services::RoutePlanner.plan(
          network: @network,
          start_port: @last_port,
          start_point: @start_point,
          target_point: build_point,
          diameter: @current_diameter,
          shape: @duct_shape,
          width: @current_width,
          height: @current_height,
          fitting_mode: @fitting_mode
        )

        result = Services::GeometryExecutor.execute(
          Sketchup.active_model,
          steps,
          @network
        )

        if result
          @last_port = result[:last_port]
          @start_point = nil
        end

        reset_typed_length
        @orthogonal_axis_lock = nil
        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
        update_status_for_current_shape
        view.invalidate if view
        true
      rescue => error
        puts "Typed length commit failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def connect_to_target_port(target_port)
        return nil unless target_port

        Services::PortToPortRouteService.connect(
          model: Sketchup.active_model,
          network: @network,
          source_port: @last_port,
          source_point: @start_point,
          target_port: target_port,
          diameter: @current_diameter,
          shape: @duct_shape,
          width: @current_width,
          height: @current_height,
          fitting_mode: @fitting_mode
        )
      end

      def finish_connection(view, message)
        @last_port = nil
        @start_point = nil
        @orthogonal_axis_lock = nil
        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
        Sketchup.status_text = message
        view.invalidate if view
      end

      def active_route_start_point
        if @last_port
          @last_port.point
        elsif @start_point
          @start_point
        else
          nil
        end
      end

      def preview_raw_point(view, start_point)
        if @last_mouse_x && @last_mouse_y
          projected = mouse_projected_point(view, @last_mouse_x, @last_mouse_y, start_point)
          return projected if projected
        end

        return @current_ip.position if @current_ip.valid?

        nil
      end

      def click_route_point(view, x, y, start_point, fallback_point)
        projected = mouse_projected_point(view, x, y, start_point)
        projected || fallback_point
      rescue => error
        puts "Click route point failed: #{error.message}"
        fallback_point
      end

      def current_preview_snapped_port(view, raw_point)
        return nil unless view
        return nil unless @last_mouse_x && @last_mouse_y
        return nil unless raw_point

        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: @last_mouse_x,
          y: @last_mouse_y,
          point: raw_point
        )

        snap&.port
      rescue => error
        puts "Preview snap check failed: #{error.message}"
        nil
      end

      def pending_build_point(start_point, raw_point)
        return raw_point unless start_point
        return raw_point unless raw_point

        snapped = orthogonal_snap_point(start_point, raw_point)
        quantize_point_from_start(start_point, snapped)
      end

      def orthogonal_snap_point(start_point, raw_point)
        vector = start_point.vector_to(raw_point)
        return raw_point if vector.length == 0

        length = vector.length
        direction = vector.clone
        direction.normalize!

        snapped_direction =
          if @orthogonal_axis_lock
            forced_axis_direction(direction)
          else
            nearest_allowed_route_direction(direction)
          end

        return raw_point unless snapped_direction

        start_point.offset(snapped_direction, length)
      end

      def nearest_allowed_route_direction(direction)
        direction = normalized_vector(direction)
        return nil unless direction

        candidates = allowed_route_directions

        best = candidates.max_by do |candidate|
          candidate.dot(direction)
        end

        best && best.clone
      end

      def allowed_route_directions
        @allowed_route_directions ||= begin
          directions = []

          x_axis = Geom::Vector3d.new(1, 0, 0)
          y_axis = Geom::Vector3d.new(0, 1, 0)
          z_axis = Geom::Vector3d.new(0, 0, 1)

          add_direction_pair(directions, x_axis)
          add_direction_pair(directions, y_axis)
          add_direction_pair(directions, z_axis)

          add_plane_45_directions(directions, :xy)
          add_plane_45_directions(directions, :xz)
          add_plane_45_directions(directions, :yz)

          unique_directions(directions)
        end
      end

      def add_plane_45_directions(directions, plane)
        c = Math.cos(45.degrees)
        s = Math.sin(45.degrees)

        [-1, 1].each do |a_sign|
          [-1, 1].each do |b_sign|
            case plane
            when :xy
              directions << normalized_vector(Geom::Vector3d.new(c * a_sign, s * b_sign, 0))
            when :xz
              directions << normalized_vector(Geom::Vector3d.new(c * a_sign, 0, s * b_sign))
            when :yz
              directions << normalized_vector(Geom::Vector3d.new(0, c * a_sign, s * b_sign))
            end
          end
        end
      end

      def add_direction_pair(directions, vector)
        v = normalized_vector(vector)
        return unless v

        directions << v
        directions << v.clone.reverse
      end

      def unique_directions(directions)
        clean = []

        directions.each do |direction|
          next unless direction

          duplicate = clean.any? do |existing|
            existing.angle_between(direction) < 0.001
          end

          clean << direction unless duplicate
        end

        clean
      end

      def quantize_point_from_start(start_point, raw_point)
        vector = start_point.vector_to(raw_point)
        return raw_point if vector.length == 0

        raw_length = vector.length
        rounded_length = round_to_increment(raw_length, @length_increment)

        return start_point if rounded_length <= 0.0

        direction = vector.clone
        direction.normalize!

        start_point.offset(direction, rounded_length)
      end

      def draw_preview_centerline(view, start_point, end_point, snapped_port)
        view.drawing_color = preview_color(snapped_port)
        view.line_width = 2
        view.draw(GL_LINES, [start_point, end_point])
      end

      def draw_ghost_duct_preview(view, start_point, end_point, snapped_port)
        if @duct_shape == :rectangular
          draw_rectangular_ghost_preview(view, start_point, end_point, snapped_port)
        else
          draw_round_ghost_preview(view, start_point, end_point, snapped_port)
        end
      end

      def draw_rectangular_ghost_preview(view, start_point, end_point, snapped_port)
        direction = start_point.vector_to(end_point)
        return if direction.length < PREVIEW_MIN_LENGTH

        direction.normalize!

        width_axis, height_axis = preview_rectangular_axes(direction)
        return unless width_axis && height_axis

        half_width = @current_width.to_f / 2.0
        half_height = @current_height.to_f / 2.0

        start_corners = preview_rectangle_corners(start_point, width_axis, height_axis, half_width, half_height)
        end_corners = preview_rectangle_corners(end_point, width_axis, height_axis, half_width, half_height)

        lines = []

        4.times do |i|
          next_i = (i + 1) % 4

          lines << start_corners[i]
          lines << start_corners[next_i]

          lines << end_corners[i]
          lines << end_corners[next_i]

          lines << start_corners[i]
          lines << end_corners[i]
        end

        view.drawing_color = preview_color(snapped_port)
        view.line_width = 1
        view.draw(GL_LINES, lines)
      end

      def draw_round_ghost_preview(view, start_point, end_point, snapped_port)
        direction = start_point.vector_to(end_point)
        return if direction.length < PREVIEW_MIN_LENGTH

        direction.normalize!

        axis_a, axis_b = preview_round_axes(direction)
        return unless axis_a && axis_b

        radius = @current_diameter.to_f / 2.0
        start_ring = []
        end_ring = []

        PREVIEW_ROUND_SEGMENTS.times do |index|
          angle = (Math::PI * 2.0 * index) / PREVIEW_ROUND_SEGMENTS

          radial = Geom::Vector3d.new(
            axis_a.x * Math.cos(angle) + axis_b.x * Math.sin(angle),
            axis_a.y * Math.cos(angle) + axis_b.y * Math.sin(angle),
            axis_a.z * Math.cos(angle) + axis_b.z * Math.sin(angle)
          )

          radial.normalize!

          start_ring << start_point.offset(radial, radius)
          end_ring << end_point.offset(radial, radius)
        end

        lines = []

        PREVIEW_ROUND_SEGMENTS.times do |index|
          next_index = (index + 1) % PREVIEW_ROUND_SEGMENTS

          lines << start_ring[index]
          lines << start_ring[next_index]

          lines << end_ring[index]
          lines << end_ring[next_index]

          if index.even?
            lines << start_ring[index]
            lines << end_ring[index]
          end
        end

        view.drawing_color = preview_color(snapped_port)
        view.line_width = 1
        view.draw(GL_LINES, lines)
      end

      def preview_color(snapped_port)
        if snapped_port
          "green"
        elsif @orthogonal_axis_lock
          "orange"
        elsif typed_length_active?
          "blue"
        else
          "red"
        end
      end

      def preview_rectangle_corners(center, width_axis, height_axis, half_width, half_height)
        [
          center.offset(width_axis, half_width).offset(height_axis, half_height),
          center.offset(width_axis.clone.reverse, half_width).offset(height_axis, half_height),
          center.offset(width_axis.clone.reverse, half_width).offset(height_axis.clone.reverse, half_height),
          center.offset(width_axis, half_width).offset(height_axis.clone.reverse, half_height)
        ]
      end

      def preview_rectangular_axes(direction)
        preferred_width_axis =
          if @last_port && @last_port.respond_to?(:width_axis)
            @last_port.width_axis
          else
            nil
          end

        preferred_height_axis =
          if @last_port && @last_port.respond_to?(:height_axis)
            @last_port.height_axis
          else
            nil
          end

        width_axis = perpendicularized_to_axis(preferred_width_axis, direction)
        width_axis ||= perpendicularized_to_axis(preferred_height_axis, direction)

        unless width_axis
          reference = preview_reference_axis(direction)
          width_axis = direction.cross(reference)
          return nil if width_axis.length == 0
          width_axis.normalize!
        end

        height_axis = direction.cross(width_axis)
        return nil if height_axis.length == 0

        height_axis.normalize!

        [width_axis, height_axis]
      end

      def preview_round_axes(direction)
        reference = preview_reference_axis(direction)

        axis_a = direction.cross(reference)
        return nil if axis_a.length == 0
        axis_a.normalize!

        axis_b = direction.cross(axis_a)
        return nil if axis_b.length == 0
        axis_b.normalize!

        [axis_a, axis_b]
      end

      def preview_reference_axis(direction)
        z_axis = Geom::Vector3d.new(0, 0, 1)

        if direction.dot(z_axis).abs < 0.95
          z_axis
        else
          Geom::Vector3d.new(1, 0, 0)
        end
      end

      def mouse_projected_point(view, x, y, start_point)
        ray = view.pickray(x, y)
        return nil unless ray

        ray_origin = ray[0]
        ray_vector = ray[1]

        return nil unless ray_origin
        return nil unless ray_vector
        return nil if ray_vector.length == 0

        camera_direction = view.camera.direction
        return nil unless camera_direction
        return nil if camera_direction.length == 0

        Geom.intersect_line_plane(
          [ray_origin, ray_vector],
          [start_point, camera_direction]
        )
      rescue => error
        puts "Mouse projected point failed: #{error.message}"
        nil
      end

      def update_length_status(view, x, y)
        start = active_route_start_point

        unless start && @current_ip.valid?
          update_status_for_current_shape
          return
        end

        raw_point = click_route_point(view, x, y, start, @current_ip.position)
        return unless raw_point

        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: raw_point
        )

        snapped_port = typed_length_active? ? nil : snap&.port

        build_point =
          if typed_length_active?
            typed_length_preview_point(start, raw_point)
          elsif snapped_port
            snapped_port.point
          else
            pending_build_point(start, raw_point)
          end

        return unless build_point

        length = start.distance(build_point)

        shape_text =
          if @duct_shape == :rectangular
            "Rectangular #{@current_width}\" x #{@current_height}\""
          else
            "Round #{@current_diameter}\""
          end

        increment_text = increment_label(@length_increment)
        axis_lock_text = orthogonal_axis_lock_label

        snap_text =
          if typed_length_active?
            " | typed: #{typed_length_status_text} | Enter to draw, Backspace to edit, Esc to clear"
          elsif snapped_port
            " | snapping to port"
          elsif axis_lock_text
            " | Orthogonal Snap + #{increment_text} rounded | #{axis_lock_text}"
          else
            " | Orthogonal Snap + #{increment_text} rounded"
          end

        Sketchup.status_text =
          "#{shape_text} | pending length: #{format_length_increment(length)}#{snap_text}"
      rescue => error
        puts "Length status failed: #{error.message}"
      end

      def handle_connector_swing_click(view, x, y)
        result = Services::ConnectorSwingService.swing_at_click(
          model: Sketchup.active_model,
          network: @network,
          view: view,
          x: x,
          y: y
        )

        case result[:status]
        when :ok
          @last_port = nil
          @start_point = nil
          @orthogonal_axis_lock = nil

          @network.rebuild_index! if @network.respond_to?(:rebuild_index!)

          angle_text = result[:angle_degrees] ? "#{result[:angle_degrees].round} degrees" : "90 degrees"
          Sketchup.status_text = "Connector swung #{angle_text} around its connected pipe."
        when :no_piece
          Sketchup.status_text = "Ctrl-click a tee, cross, or wye to swing it."
        when :no_valid_angle
          ::UI.messagebox(
            "This rectangular connector cannot swing to a clean orientation here.\n\n" \
            "For rectangular duct, the connected face must keep the same width/height orientation. Try a 180-degree opposite-side swing, disconnect more branches, or use a square duct size."
          )
        when :too_many_connections
          ::UI.messagebox(
            "This connector has too many attached ducts to swing safely.\n\n" \
            "Disconnect the side branch first, then Ctrl-click the connector again."
          )
        when :not_swingable
          Sketchup.status_text = "Only tees, crosses, and wyes can be swung right now."
        else
          ::UI.messagebox("Could not swing this connector. Check the Ruby Console for details.")
        end
      rescue => error
        puts "DuctTool.handle_connector_swing_click failed: #{error.message}"
        puts error.backtrace.join("\n")
        ::UI.messagebox("Could not swing this connector. Check the Ruby Console for details.")
      end

      def handle_end_tee_click(view, x, y, point)
        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: point
        )

        snapped_port = snap&.port

        unless snapped_port
          ::UI.messagebox("End Tee mode: click an open end port.")
          return
        end

        side_vector = choose_branch_direction_for_end_tee(snapped_port)

        result = Services::EndTeeInsertService.insert_at_port(
          model: Sketchup.active_model,
          network: @network,
          stem_port: snapped_port,
          side_vector: side_vector
        )

        if result
          @last_port = nil
          @start_point = nil
          @orthogonal_axis_lock = nil
          copy_dimensions_from_port(snapped_port)
          @fitting_mode = :elbow

          @network.rebuild_index! if @network.respond_to?(:rebuild_index!)

          Sketchup.status_text = "End tee inserted. Click either open tee end to continue."
        else
          ::UI.messagebox("Could not insert end tee here.")
        end
      end

      def handle_end_cross_click(view, x, y, point)
        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: point
        )

        snapped_port = snap&.port

        unless snapped_port
          ::UI.messagebox("End Cross mode: click an open end port.")
          return
        end

        side_vector = choose_branch_direction_for_end_tee(snapped_port)

        result = Services::EndCrossInsertService.insert_at_port(
          model: Sketchup.active_model,
          network: @network,
          stem_port: snapped_port,
          side_vector: side_vector
        )

        if result
          @last_port = nil
          @start_point = nil
          @orthogonal_axis_lock = nil
          copy_dimensions_from_port(snapped_port)
          @fitting_mode = :elbow

          @network.rebuild_index! if @network.respond_to?(:rebuild_index!)

          Sketchup.status_text = "End cross inserted. Click any open cross end to continue."
        else
          ::UI.messagebox("Could not insert end cross here.")
        end
      end

      def handle_end_wye_click(view, x, y, point)
        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: point
        )

        snapped_port = snap&.port

        unless snapped_port
          ::UI.messagebox("End Wye mode: click an open end port.")
          return
        end

        side_vector = choose_branch_direction_for_end_wye(snapped_port)

        result = Services::EndWyeInsertService.insert_at_port(
          model: Sketchup.active_model,
          network: @network,
          stem_port: snapped_port,
          side_vector: side_vector
        )

        if result
          @last_port = nil
          @start_point = nil
          @orthogonal_axis_lock = nil
          copy_dimensions_from_port(snapped_port)
          @fitting_mode = :elbow

          @network.rebuild_index! if @network.respond_to?(:rebuild_index!)

          Sketchup.status_text = "End wye inserted. Click either open wye end to continue."
        else
          ::UI.messagebox("Could not insert end wye here.")
        end
      end

      def handle_end_reducer_click(view, x, y, point)
        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: point
        )

        snapped_port = snap&.port

        unless snapped_port
          ::UI.messagebox("End Increaser / Reducer mode: click an open end port.")
          return
        end

        input = prompt_for_reducer_size(snapped_port)
        return unless input

        result = Services::EndReducerInsertService.insert_at_port(
          model: Sketchup.active_model,
          network: @network,
          stem_port: snapped_port,
          new_diameter: input[:diameter],
          new_width: input[:width],
          new_height: input[:height],
          length: input[:length]
        )

        if result
          @last_port = nil
          @start_point = nil
          @orthogonal_axis_lock = nil

          new_port = result[:new_port]
          copy_dimensions_from_port(new_port) if new_port

          @fitting_mode = :elbow

          @network.rebuild_index! if @network.respond_to?(:rebuild_index!)

          Sketchup.status_text = "Increaser / reducer inserted. Click the new open end to continue."
        else
          ::UI.messagebox("Could not insert increaser / reducer here.")
        end
      rescue => error
        puts "DuctTool.handle_end_reducer_click failed: #{error.message}"
        puts error.backtrace.join("\n")
        ::UI.messagebox("Could not insert increaser / reducer. Check the Ruby Console for details.")
      end

      def handle_manual_tee_click(view, x, y, point)
        pipe_piece = Services::SnapService.picked_pipe_piece(
          network: @network,
          view: view,
          x: x,
          y: y
        )

        unless pipe_piece
          ::UI.messagebox("Add Tee mode: click an existing duct pipe.")
          return
        end

        dimensions =
          if pipe_piece.ports && pipe_piece.ports[0]
            Model::Port.dimensions_from_params({}, pipe_piece.ports[0])
          else
            { shape: @duct_shape }
          end

        branch_direction =
          if dimensions[:shape] == :rectangular
            choose_branch_direction_from_click(pipe_piece, point)
          else
            choose_round_tee_branch_direction(pipe_piece, point, view)
          end

        result = Services::TeeInsertService.insert_tee_on_pipe(
          model: Sketchup.active_model,
          network: @network,
          pipe_piece: pipe_piece,
          tap_point: point,
          branch_direction: branch_direction
        )

        unless result
          ::UI.messagebox("Could not insert tee here. Try clicking farther from the pipe ends.")
          return
        end

        @last_port = result[:branch_port]
        @start_point = nil
        @orthogonal_axis_lock = nil
        copy_dimensions_from_port(@last_port)
        @fitting_mode = :elbow

        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)

        Sketchup.status_text = "Tee inserted. Click next orthogonal point to draw branch."
      end

      def try_auto_tee_target(view, x, y, clicked_point)
        return nil unless @last_port || @start_point

        pipe_piece = Services::SnapService.picked_pipe_piece(
          network: @network,
          view: view,
          x: x,
          y: y
        )

        return nil unless pipe_piece

        start = active_route_start_point
        return nil unless start

        requested_branch_direction =
          if @last_port && @last_port.respond_to?(:outward_vector)
            @last_port.outward_vector
          else
            start.vector_to(clicked_point)
          end

        Services::PipeTargetConnectionService.insert_smart_tee_target(
          model: Sketchup.active_model,
          network: @network,
          target_pipe_piece: pipe_piece,
          click_point: clicked_point,
          active_start_point: start,
          active_start_port: @last_port,
          requested_branch_direction: requested_branch_direction
        )
      end

      def choose_round_tee_branch_direction(pipe_piece, click_point, view)
        main_vector = pipe_piece.ports[0].point.vector_to(pipe_piece.ports[1].point)
        return choose_branch_direction(pipe_piece) if main_vector.length == 0

        main_vector.normalize!

        requested =
          case @round_tee_side_mode
          when :positive_z
            Geom::Vector3d.new(0, 0, 1)
          when :negative_z
            Geom::Vector3d.new(0, 0, -1)
          when :positive_x
            Geom::Vector3d.new(1, 0, 0)
          when :negative_x
            Geom::Vector3d.new(-1, 0, 0)
          when :positive_y
            Geom::Vector3d.new(0, 1, 0)
          when :negative_y
            Geom::Vector3d.new(0, -1, 0)
          when :toward_camera
            camera_direction = view && view.camera ? view.camera.direction : nil
            camera_direction ? camera_direction.clone.reverse : nil
          when :away_from_camera
            camera_direction = view && view.camera ? view.camera.direction : nil
            camera_direction ? camera_direction.clone : nil
          else
            return choose_branch_direction_from_click(pipe_piece, click_point)
          end

        side = perpendicularized_to_axis(requested, main_vector)

        side || choose_branch_direction_from_click(pipe_piece, click_point)
      end

      def choose_branch_direction(pipe_piece)
        main_vector = pipe_piece.ports[0].point.vector_to(pipe_piece.ports[1].point)
        return Geom::Vector3d.new(1, 0, 0) if main_vector.length == 0

        main_vector.normalize!

        z_axis = Geom::Vector3d.new(0, 0, 1)
        branch = main_vector.cross(z_axis)

        if branch.length == 0
          branch = main_vector.cross(Geom::Vector3d.new(1, 0, 0))
        end

        branch.normalize!
        branch
      end

      def choose_branch_direction_from_click(pipe_piece, click_point)
        main_vector = pipe_piece.ports[0].point.vector_to(pipe_piece.ports[1].point)
        return choose_branch_direction(pipe_piece) if main_vector.length == 0

        main_vector.normalize!

        pipe_start = pipe_piece.ports[0].point
        from_start = pipe_start.vector_to(click_point)
        distance_along = from_start.dot(main_vector)
        closest_on_pipe = pipe_start.offset(main_vector, distance_along)

        side_vector = closest_on_pipe.vector_to(click_point)
        return choose_branch_direction(pipe_piece) if side_vector.length == 0

        side_vector = perpendicularized_to_axis(side_vector, main_vector)
        side_vector || choose_branch_direction(pipe_piece)
      end

      def choose_branch_direction_for_end_tee(stem_port)
        stem = stem_port.outward_vector.clone
        return Geom::Vector3d.new(1, 0, 0) if stem.length == 0

        stem.normalize!

        z_axis = Geom::Vector3d.new(0, 0, 1)
        side = stem.cross(z_axis)

        if side.length == 0
          side = stem.cross(Geom::Vector3d.new(1, 0, 0))
        end

        side.normalize!
        side
      end

      def choose_branch_direction_for_end_wye(stem_port)
        # Reuse the same side-selection basis as end tees/crosses. The actual
        # wye branch angle is created inside WyeBuilder, so this side vector only
        # decides which side the 45-degree branch leans toward.
        choose_branch_direction_for_end_tee(stem_port)
      end

      def perpendicularized_to_axis(vector, axis)
        return nil unless vector
        return nil unless axis

        side = vector.clone
        main = axis.clone

        return nil if side.length == 0
        return nil if main.length == 0

        side.normalize!
        main.normalize!

        dot = side.dot(main)

        result = Geom::Vector3d.new(
          side.x - main.x * dot,
          side.y - main.y * dot,
          side.z - main.z * dot
        )

        return nil if result.length == 0

        result.normalize!
        result
      rescue
        nil
      end

      def toggle_orthogonal_axis_lock(lock)
        if @orthogonal_axis_lock == lock
          @orthogonal_axis_lock = nil
        else
          @orthogonal_axis_lock = lock
        end
      end

      def forced_axis_direction(raw_direction)
        case @orthogonal_axis_lock
        when :positive_z
          Geom::Vector3d.new(0, 0, 1)
        when :negative_z
          Geom::Vector3d.new(0, 0, -1)
        when :x
          raw_direction.x >= 0 ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(-1, 0, 0)
        when :y
          raw_direction.y >= 0 ? Geom::Vector3d.new(0, 1, 0) : Geom::Vector3d.new(0, -1, 0)
        else
          nil
        end
      end

      def orthogonal_axis_lock_label
        case @orthogonal_axis_lock
        when :positive_z
          "Up/+Z locked"
        when :negative_z
          "Down/-Z locked"
        when :x
          "X axis locked"
        when :y
          "Y axis locked"
        else
          nil
        end
      end

      def set_round_tee_side_mode(mode)
        @round_tee_side_mode = mode
        @@last_round_tee_side_mode = mode
        Sketchup.status_text = "Round tee side: #{round_tee_side_label(mode)}."
      end

      def round_tee_side_label(mode)
        case mode
        when :positive_z
          "Up / +Z"
        when :negative_z
          "Down / -Z"
        when :positive_x
          "+X"
        when :negative_x
          "-X"
        when :positive_y
          "+Y"
        when :negative_y
          "-Y"
        when :toward_camera
          "Toward Camera"
        when :away_from_camera
          "Away From Camera"
        else
          "From Click"
        end
      end

      def normalized_vector(vector)
        return nil unless vector

        clone = vector.clone
        return nil if clone.length == 0

        clone.normalize!
        clone
      end

      def round_to_increment(value, increment)
        increment = increment.to_f
        increment = DEFAULT_LENGTH_INCREMENT if increment <= 0.0

        (value.to_f / increment).round * increment
      end

      def format_length_increment(length)
        inches = round_to_increment(length.to_f.abs, @length_increment)

        feet = (inches / 12.0).floor
        remaining_inches = inches - feet * 12.0

        if feet > 0
          "#{feet}' #{format_inches_increment(remaining_inches)}\""
        else
          "#{format_inches_increment(remaining_inches)}\""
        end
      end

      def format_inches_increment(inches)
        increment = @length_increment.to_f

        if increment == 1.0
          return inches.round.to_s
        end

        whole_inches = inches.floor
        fraction = inches - whole_inches

        if increment == 0.5
          halves = (fraction / 0.5).round

          if halves >= 2
            whole_inches += 1
            halves = 0
          end

          fraction_text =
            case halves
            when 0 then ""
            when 1 then " 1/2"
            else ""
            end

          if whole_inches == 0 && !fraction_text.empty?
            fraction_text.strip
          else
            "#{whole_inches}#{fraction_text}"
          end
        else
          quarters = (fraction / 0.25).round

          if quarters >= 4
            whole_inches += 1
            quarters = 0
          end

          fraction_text =
            case quarters
            when 0 then ""
            when 1 then " 1/4"
            when 2 then " 1/2"
            when 3 then " 3/4"
            else ""
            end

          if whole_inches == 0 && !fraction_text.empty?
            fraction_text.strip
          else
            "#{whole_inches}#{fraction_text}"
          end
        end
      end

      def copy_dimensions_from_port(port)
        return unless port

        @duct_shape = port.shape
        @current_diameter = port.diameter
        @current_width = port.width
        @current_height = port.height

        if @duct_shape == :round
          @current_width = @current_diameter
          @current_height = @current_diameter
        end
      end

      def shape_label(shape)
        shape == :rectangular ? "Rectangular" : "Round"
      end

      def normalize_shape(value)
        value = value.to_s.downcase.strip

        case value
        when "rectangular", "rectangle", "rect", "r"
          :rectangular
        else
          :round
        end
      end

      def normalize_increment(value)
        text = value.to_s.downcase.strip

        case text
        when "1 inch", "1", "1.0", "one inch"
          1.0
        when "1/2 inch", "1/2", "0.5", ".5", "half inch"
          0.5
        else
          0.25
        end
      end

      def increment_label(value)
        case value.to_f
        when 1.0
          "1 inch"
        when 0.5
          "1/2 inch"
        else
          "1/4 inch"
        end
      end


      def prompt_for_reducer_size(port)
        dimensions = Model::Port.dimensions_from_params({}, port)

        if dimensions[:shape] == :rectangular
          prompt_for_rectangular_reducer_size(dimensions)
        else
          prompt_for_round_reducer_size(dimensions)
        end
      end

      def prompt_for_round_reducer_size(dimensions)
        default_length = Geometry::ReducerBuilder.default_length(
          dimensions,
          {
            shape: :round,
            diameter: @@last_reducer_round_diameter
          }
        )

        prompts = [
          "Current Diameter:",
          "New Diameter:",
          "Transition Length:"
        ]

        defaults = [
          dimensions[:diameter].to_s,
          @@last_reducer_round_diameter.to_s,
          reducer_length_default(default_length)
        ]

        input = ::UI.inputbox(
          prompts,
          defaults,
          [],
          "Round Increaser / Reducer"
        )

        return nil unless input

        new_diameter = positive_number_or_nil(input[1])
        length = positive_number(input[2], 0.0)

        unless new_diameter
          ::UI.messagebox("Please enter a valid new diameter.")
          return nil
        end

        if (new_diameter - dimensions[:diameter].to_f).abs <= 0.001
          ::UI.messagebox("The new diameter must be different from the current diameter.")
          return nil
        end

        @@last_reducer_round_diameter = new_diameter
        @@last_reducer_length = length

        {
          diameter: new_diameter,
          width: new_diameter,
          height: new_diameter,
          length: length
        }
      end

      def prompt_for_rectangular_reducer_size(dimensions)
        default_length = Geometry::ReducerBuilder.default_length(
          dimensions,
          {
            shape: :rectangular,
            width: @@last_reducer_rectangular_width,
            height: @@last_reducer_rectangular_height
          }
        )

        prompts = [
          "Current Width:",
          "Current Height:",
          "New Width:",
          "New Height:",
          "Transition Length:"
        ]

        defaults = [
          dimensions[:width].to_s,
          dimensions[:height].to_s,
          @@last_reducer_rectangular_width.to_s,
          @@last_reducer_rectangular_height.to_s,
          reducer_length_default(default_length)
        ]

        input = ::UI.inputbox(
          prompts,
          defaults,
          [],
          "Rectangular Increaser / Reducer"
        )

        return nil unless input

        new_width = positive_number_or_nil(input[2])
        new_height = positive_number_or_nil(input[3])
        length = positive_number(input[4], 0.0)

        unless new_width && new_height
          ::UI.messagebox("Please enter a valid new width and height.")
          return nil
        end

        width_changed = (new_width - dimensions[:width].to_f).abs > 0.001
        height_changed = (new_height - dimensions[:height].to_f).abs > 0.001

        unless width_changed || height_changed
          ::UI.messagebox("The new width or height must be different from the current size.")
          return nil
        end

        @@last_reducer_rectangular_width = new_width
        @@last_reducer_rectangular_height = new_height
        @@last_reducer_length = length

        {
          diameter: [new_width, new_height].max,
          width: new_width,
          height: new_height,
          length: length
        }
      end

      def reducer_length_default(default_length)
        if @@last_reducer_length && @@last_reducer_length.to_f > 0.0
          @@last_reducer_length.to_s
        else
          default_length.round(2).to_s
        end
      end

      def positive_number_or_nil(value)
        number = value.to_f
        number > 0.0 ? number : nil
      rescue
        nil
      end

      def positive_number(value, fallback)
        number = value.to_f
        number > 0 ? number : fallback.to_f
      rescue
        fallback.to_f
      end

      def update_status_for_current_shape
        increment_text = increment_label(@length_increment)
        axis_lock_text = orthogonal_axis_lock_label
        lock_suffix = axis_lock_text ? " #{axis_lock_text}." : ""
        typed_suffix = typed_length_active? ? " Typed length: #{typed_length_status_text}. Press Enter to draw, Backspace to edit, Esc to clear." : ""

        mode_text =
          case @fitting_mode
          when :straight
            "Straight Only"
          when :tee
            "Add Tee"
          when :end_tee
            "End Tee"
          when :end_cross
            "End Cross"
          when :end_wye
            "End Wye"
          when :end_reducer
            "End Increaser / Reducer"
          when :vent
            "Add Vent"
          else
            "Auto-Elbow"
          end

        if @duct_shape == :rectangular
          Sketchup.status_text =
            "Rectangular orthogonal duct: #{@current_width}\" x #{@current_height}\". #{mode_text}; #{increment_text} rounded.#{lock_suffix}#{typed_suffix}"
        else
          Sketchup.status_text =
            "Round orthogonal duct: #{@current_diameter}\" diameter. #{mode_text}; #{increment_text} rounded.#{lock_suffix}#{typed_suffix}"
        end
      end
    end
  end
end
