module DuctExtension
  module Tool
    module DuctToolMenu
      private

      def populate_duct_tool_menu(menu, _flags, _x, _y, _view)
        add_mode_menu_items(menu)
        menu.add_separator
        add_component_menu(menu)
        menu.add_separator
        add_axis_lock_menu(menu)
        add_length_increment_menu(menu)
        add_vent_repeat_menu(menu)
      rescue => error
        puts "DuctToolMenu.populate_duct_tool_menu failed: #{error.message}"
      end

      def add_mode_menu_items(menu)
        menu.add_item("Mode: Auto-Elbow") { select_fitting_mode(:elbow) }
        menu.add_item("Mode: Straight Only") { select_fitting_mode(:straight) }
      end

      def add_component_menu(menu)
        components_menu = menu.add_submenu("New Components")

        components_menu.add_item("Add Tee") {
          select_fitting_mode(:tee, round_tee_from_click: true)
        }

        components_menu.add_item("End Tee") {
          select_fitting_mode(:end_tee, round_tee_from_click: true)
        }

        components_menu.add_item("End Cross") {
          select_fitting_mode(:end_cross)
        }

        components_menu.add_item("End Wye") {
          select_fitting_mode(:end_wye)
        }

        components_menu.add_item("End Increaser / Reducer") {
          select_fitting_mode(:end_reducer)
        }

        components_menu.add_item("Add Vent") {
          select_fitting_mode(
            :vent,
            status: "Add Vent mode: click near a pipe end for a cover, or click the side for a register."
          )
        }
      end

      def add_axis_lock_menu(menu)
        axis_menu = menu.add_submenu("Lock Axis")

        axis_menu.add_item("Clear") {
          @orthogonal_axis_lock = nil
          update_status_for_current_shape
        }

        {
          "Up / +Z" => :positive_z,
          "Down / -Z" => :negative_z,
          "X" => :x,
          "Y" => :y
        }.each do |label, lock|
          axis_menu.add_item(label) {
            toggle_orthogonal_axis_lock(lock)
            update_status_for_current_shape
          }
        end
      end

      def add_length_increment_menu(menu)
        length_menu = menu.add_submenu("Length Increment")

        {
          "1/4 inch" => 0.25,
          "1/2 inch" => 0.5,
          "1 inch" => 1.0
        }.each do |label, increment|
          length_menu.add_item(label) {
            @length_increment = increment
            set_duct_tool_class_setting(:@@last_length_increment, @length_increment)
            update_status_for_current_shape
          }
        end
      end

      def add_vent_repeat_menu(menu)
        menu.add_separator
        repeat_menu = menu.add_submenu("Vent Repeat")

        repeat_state = duct_tool_class_setting(:@@vent_repeat_enabled) ? "On" : "Off"
        repeat_menu.add_item("Repeat: #{repeat_state}") {
          set_duct_tool_class_setting(:@@vent_repeat_enabled, !duct_tool_class_setting(:@@vent_repeat_enabled))
          Sketchup.status_text = "Vent repeat #{duct_tool_class_setting(:@@vent_repeat_enabled) ? 'on' : 'off'}."
        }

        repeat_menu.add_separator

        repeat_menu.add_item("Off") {
          set_duct_tool_class_setting(:@@vent_repeat_enabled, false)
          Sketchup.status_text = "Vent repeat off."
        }

        repeat_menu.add_item("On") {
          set_duct_tool_class_setting(:@@vent_repeat_enabled, true)
          Sketchup.status_text = vent_repeat_status_text
        }

        direction_menu = repeat_menu.add_submenu("Direction")

        direction_menu.add_item("Right") {
          set_duct_tool_class_setting(:@@vent_repeat_direction, :right)
          Sketchup.status_text = vent_repeat_status_text
        }

        direction_menu.add_item("Left") {
          set_duct_tool_class_setting(:@@vent_repeat_direction, :left)
          Sketchup.status_text = vent_repeat_status_text
        }

        interval_menu = repeat_menu.add_submenu("Interval")

        [12.0, 18.0, 24.0, 30.0, 36.0, 48.0].each do |interval|
          interval_menu.add_item("#{InputHelpers.format_number(interval)} inches") {
            set_duct_tool_class_setting(:@@vent_repeat_interval, interval)
            Sketchup.status_text = vent_repeat_status_text
          }
        end

        interval_menu.add_separator
        interval_menu.add_item("Custom...") { prompt_for_vent_repeat_interval }
      rescue => error
        puts "DuctToolMenu.add_vent_repeat_menu failed: #{error.message}"
      end

      def select_fitting_mode(mode, round_tee_from_click: false, status: nil)
        @fitting_mode = mode

        if round_tee_from_click
          @round_tee_side_mode = :from_click
          set_duct_tool_class_setting(:@@last_round_tee_side_mode, @round_tee_side_mode)
        end

        update_status_for_current_shape
        Sketchup.status_text = status if status
      end

      def vent_repeat_status_text
        direction = duct_tool_class_setting(:@@vent_repeat_direction) == :left ? "left" : "right"
        "Vent repeat #{duct_tool_class_setting(:@@vent_repeat_enabled) ? 'on' : 'off'}: #{InputHelpers.format_number(duct_tool_class_setting(:@@vent_repeat_interval))} inches to the #{direction}."
      rescue
        "Vent repeat updated."
      end

      def prompt_for_vent_repeat_interval
        input = ::UI.inputbox(
          ["Repeat Interval (Inches):"],
          [InputHelpers.format_number(duct_tool_class_setting(:@@vent_repeat_interval))],
          [],
          "Vent Repeat Interval"
        )

        return unless input

        set_duct_tool_class_setting(
          :@@vent_repeat_interval,
          InputHelpers.positive_number(input[0], duct_tool_class_setting(:@@vent_repeat_interval))
        )
        set_duct_tool_class_setting(:@@vent_repeat_enabled, true)
        Sketchup.status_text = vent_repeat_status_text
      rescue => error
        puts "DuctToolMenu.prompt_for_vent_repeat_interval failed: #{error.message}"
      end
    end
  end
end
