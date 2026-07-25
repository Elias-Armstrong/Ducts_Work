module DuctExtension
  module Tool
    # Shared DuctTool constants live at the Tool namespace so every mixin
    # resolves the same values. Keeping these inside DuctTool breaks Ruby
    # constant lookup from included modules.
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
    ORBIT_SENSITIVITY = 0.004

    MK_MBUTTON_VALUE = defined?(MK_MBUTTON) ? MK_MBUTTON : 16
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

    class DuctTool
      include DuctToolMenu
      include DuctToolTypedLength
      include DuctToolVents
      include DuctToolFittings
      include DuctToolNavigation
      include DuctToolRoutingPreview
      include DuctToolSettings

      @@last_duct_shape = :round
      @@last_diameter = 8.0
      @@last_width = 12.0
      @@last_height = 8.0
      @@last_length_increment = DEFAULT_LENGTH_INCREMENT
      @@last_round_tee_side_mode = :from_click

      @@vent_repeat_enabled = false unless class_variable_defined?(:@@vent_repeat_enabled)
      @@vent_repeat_direction = :right unless class_variable_defined?(:@@vent_repeat_direction)
      @@vent_repeat_interval = 24.0 unless class_variable_defined?(:@@vent_repeat_interval)


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
        @connector_swing_session = nil

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
        @current_diameter = InputHelpers.positive_number(input[1], @current_diameter)
        @current_width = InputHelpers.positive_number(input[2], @current_width)
        @current_height = InputHelpers.positive_number(input[3], @current_height)
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
        @connector_swing_session = nil
        reset_typed_length

        update_status_for_current_shape
      end

      def getMenu(menu, flags, x, y, view)
        populate_duct_tool_menu(menu, flags, x, y, view)
      end

      def onCancel(reason, view)
        cancel_connector_swing_drag(view) if @connector_swing_session

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

        if @connector_swing_session
          update_connector_swing_drag(view, x, y)
          return
        end

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
        if @fitting_mode == :vent
          @last_mouse_x = x
          @last_mouse_y = y

          ip = Sketchup::InputPoint.new
          ip.pick(view, x, y)

          clicked_point = ip.position
          return unless clicked_point

          handle_vent_click(view, x, y, clicked_point)
          view.invalidate if view
          return
        end

        if shift_down?(flags)
          @shift_left_orbiting = true
          @orbit_last_x = x
          @orbit_last_y = y
          Sketchup.status_text = "Shift + left drag orbit around active duct point. Release left mouse to continue duct drawing."
          view.invalidate if view
          return true
        end

        if ctrl_down?(flags)
          begin_connector_swing_drag(view, x, y)
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

        if dispatch_special_fitting_click(view, x, y, clicked_point)
          view.invalidate if view
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
          Services::PortCapService.remove(snapped_port)
          point = snapped_port.point
          puts "Orthogonal DuctTool snapped to #{snapped_port.piece.type} port at #{snapped_port.point}"
        else
          puts "Orthogonal DuctTool found no open external port snap."
        end

        if @last_port || @start_point
          Services::PortCapService.remove(@last_port) if @last_port

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
        if @connector_swing_session
          finish_connector_swing_drag(view)
          return true
        end

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

      def deactivate(view)
        cancel_connector_swing_drag(view) if @connector_swing_session
      end

      private

    end
  end
end
