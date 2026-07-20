module DuctExtension
  module Tool
    class DuctTool
      @@vent_repeat_enabled = false unless class_variable_defined?(:@@vent_repeat_enabled)
      @@vent_repeat_direction = :right unless class_variable_defined?(:@@vent_repeat_direction)
      @@vent_repeat_interval = 24.0 unless class_variable_defined?(:@@vent_repeat_interval)

      unless method_defined?(:duct_tool_original_on_lbutton_down_before_vents)
        alias_method :duct_tool_original_on_lbutton_down_before_vents, :onLButtonDown
      end

      unless method_defined?(:duct_tool_original_get_menu_before_vent_repeat)
        alias_method :duct_tool_original_get_menu_before_vent_repeat, :getMenu
      end

      def getMenu(menu, flags, x, y, view)
        duct_tool_original_get_menu_before_vent_repeat(menu, flags, x, y, view)
        add_vent_repeat_menu(menu)
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

        duct_tool_original_on_lbutton_down_before_vents(flags, x, y, view)
      end

      private

      def add_vent_repeat_menu(menu)
        menu.add_separator

        repeat_menu = menu.add_submenu("Vent Repeat")

        repeat_state = @@vent_repeat_enabled ? "On" : "Off"
        repeat_menu.add_item("Repeat: #{repeat_state}") {
          @@vent_repeat_enabled = !@@vent_repeat_enabled
          Sketchup.status_text = "Vent repeat #{@@vent_repeat_enabled ? 'on' : 'off'}."
        }

        repeat_menu.add_separator

        repeat_menu.add_item("Off") {
          @@vent_repeat_enabled = false
          Sketchup.status_text = "Vent repeat off."
        }

        repeat_menu.add_item("On") {
          @@vent_repeat_enabled = true
          Sketchup.status_text = vent_repeat_status_text
        }

        direction_menu = repeat_menu.add_submenu("Direction")

        direction_menu.add_item("Right") {
          @@vent_repeat_direction = :right
          Sketchup.status_text = vent_repeat_status_text
        }

        direction_menu.add_item("Left") {
          @@vent_repeat_direction = :left
          Sketchup.status_text = vent_repeat_status_text
        }

        interval_menu = repeat_menu.add_submenu("Interval")

        [12.0, 18.0, 24.0, 30.0, 36.0, 48.0].each do |interval|
          interval_menu.add_item("#{format_number(interval)} inches") {
            @@vent_repeat_interval = interval
            Sketchup.status_text = vent_repeat_status_text
          }
        end

        interval_menu.add_separator

        interval_menu.add_item("Custom...") {
          prompt_for_vent_repeat_interval
        }
      rescue => error
        puts "DuctTool.add_vent_repeat_menu failed: #{error.message}"
      end

      def vent_repeat_status_text
        direction = @@vent_repeat_direction == :left ? "left" : "right"
        "Vent repeat #{@@vent_repeat_enabled ? 'on' : 'off'}: #{format_number(@@vent_repeat_interval)} inches to the #{direction}."
      rescue
        "Vent repeat updated."
      end

      def prompt_for_vent_repeat_interval
        input = ::UI.inputbox(
          ["Repeat Interval (Inches):"],
          [format_number(@@vent_repeat_interval)],
          [],
          "Vent Repeat Interval"
        )

        return unless input

        interval = positive_number(input[0], @@vent_repeat_interval)
        @@vent_repeat_interval = interval
        @@vent_repeat_enabled = true
        Sketchup.status_text = vent_repeat_status_text
      rescue => error
        puts "DuctTool.prompt_for_vent_repeat_interval failed: #{error.message}"
      end

      def handle_vent_click(view, x, y, clicked_point)
        pipe_piece = Services::SnapService.picked_pipe_piece(
          network: @network,
          view: view,
          x: x,
          y: y
        )

        pipe_piece ||= nearest_pipe_piece_for_vent_click(clicked_point)

        unless pipe_piece
          ::UI.messagebox("Add Vent mode: click an existing duct pipe. Click near the end for an end cover, or click the side for a register.")
          return
        end

        unless pipe_piece.ports && pipe_piece.ports.length >= 2
          ::UI.messagebox("Add Vent mode: vents can be placed on duct pipes.")
          return
        end

        dimensions = Model::Port.dimensions_from_params({}, pipe_piece.ports.first)

        input = prompt_for_vent(dimensions)
        return unless input

        result = Services::VentInsertService.insert_on_piece(
          model: Sketchup.active_model,
          network: @network,
          duct_piece: pipe_piece,
          click_point: clicked_point,
          register_width: input[:register_width],
          register_height: input[:register_height],
          register_bumped_out: input[:register_bumped_out],
          cover_diameter: input[:cover_diameter],
          cover_width: input[:cover_width],
          cover_height: input[:cover_height],
          repeat_enabled: @@vent_repeat_enabled,
          repeat_direction: @@vent_repeat_direction,
          repeat_interval: @@vent_repeat_interval,
          view: view
        )

        if result
          @last_port = nil
          @start_point = nil
          @orthogonal_axis_lock = nil
          @fitting_mode = :vent

          if result[:vent_type] == :side_register_repeat
            Sketchup.status_text = "#{result[:count]} vents inserted. Still in Add Vent mode."
          else
            Sketchup.status_text = "Vent inserted. Still in Add Vent mode: click another pipe end or side."
          end
        else
          ::UI.messagebox("Could not insert vent here. Try clicking closer to the side or end of a duct pipe.")
        end
      rescue => error
        puts "DuctTool.handle_vent_click failed: #{error.message}"
        puts error.backtrace.join("\n")
        ::UI.messagebox("Could not insert vent. Check the Ruby Console for details.")
      end

      def nearest_pipe_piece_for_vent_click(clicked_point)
        return nil unless @network && @network.respond_to?(:pieces)

        best_piece = nil
        best_distance = nil

        @network.pieces.each do |piece|
          next unless piece
          next unless piece.type == :pipe
          next unless piece.group && piece.group.valid?
          next unless piece.ports && piece.ports.length >= 2

          port_a = piece.ports[0]
          port_b = piece.ports[1]

          next unless port_a && port_b && port_a.point && port_b.point

          closest = closest_point_on_segment_for_vent(
            port_a.point,
            port_b.point,
            clicked_point
          )

          next unless closest

          distance = closest.distance(clicked_point)
          dimensions = Model::Port.dimensions_from_params({}, port_a)

          tolerance = [
            dimensions[:diameter].to_f,
            dimensions[:width].to_f,
            dimensions[:height].to_f,
            6.0
          ].max * 1.8

          next if distance > tolerance

          if best_distance.nil? || distance < best_distance
            best_distance = distance
            best_piece = piece
          end
        end

        best_piece
      rescue => error
        puts "DuctTool.nearest_pipe_piece_for_vent_click failed: #{error.message}"
        nil
      end

      def closest_point_on_segment_for_vent(start_point, end_point, point)
        axis = start_point.vector_to(end_point)
        return nil if axis.length <= 0.0

        length = axis.length
        axis.normalize!

        amount = start_point.vector_to(point).dot(axis)
        amount = [[amount, 0.0].max, length].min

        start_point.offset(axis, amount)
      rescue
        nil
      end

      def prompt_for_vent(dimensions)
        if dimensions[:shape] == :rectangular
          prompt_for_rectangular_vent(dimensions)
        else
          prompt_for_round_vent(dimensions)
        end
      end

      def prompt_for_round_vent(dimensions)
        diameter = dimensions[:diameter].to_f

        prompts = [
          "Side Register Plate Width:",
          "Side Register Plate Height:",
          "Register Bumped Out?",
          "End Cover Diameter:"
        ]

        defaults = [
          format_number(diameter * 1.35),
          format_number(diameter * 0.55),
          "Yes",
          format_number(diameter * 1.22)
        ]

        lists = [
          "",
          "",
          "Yes|No",
          ""
        ]

        input = ::UI.inputbox(
          prompts,
          defaults,
          lists,
          "Round Duct Vent"
        )

        return nil unless input

        {
          register_width: positive_number(input[0], diameter * 1.35),
          register_height: positive_number(input[1], diameter * 0.55),
          register_bumped_out: yes_value?(input[2]),
          cover_diameter: positive_number(input[3], diameter * 1.22),
          cover_width: nil,
          cover_height: nil
        }
      end

      def prompt_for_rectangular_vent(dimensions)
        width = dimensions[:width].to_f
        height = dimensions[:height].to_f
        largest = [width, height].max

        prompts = [
          "Side Register Plate Width:",
          "Side Register Plate Height:",
          "Register Bumped Out?",
          "End Cover Width:",
          "End Cover Height:"
        ]

        defaults = [
          format_number(largest * 1.10),
          format_number(largest * 0.45),
          "Yes",
          format_number(width * 1.22),
          format_number(height * 1.22)
        ]

        lists = [
          "",
          "",
          "Yes|No",
          "",
          ""
        ]

        input = ::UI.inputbox(
          prompts,
          defaults,
          lists,
          "Rectangular Duct Vent"
        )

        return nil unless input

        {
          register_width: positive_number(input[0], largest * 1.10),
          register_height: positive_number(input[1], largest * 0.45),
          register_bumped_out: yes_value?(input[2]),
          cover_diameter: nil,
          cover_width: positive_number(input[3], width * 1.22),
          cover_height: positive_number(input[4], height * 1.22)
        }
      end

      def yes_value?(value)
        text = value.to_s.strip.downcase
        text == "yes" || text == "y" || text == "true" || text == "1"
      rescue
        true
      end

      def positive_number(value, fallback)
        number = value.to_f
        number > 0.0 ? number : fallback.to_f
      rescue
        fallback.to_f
      end

      def format_number(value)
        number = value.to_f
        rounded = number.round(3)

        if (rounded - rounded.round).abs < 0.001
          rounded.round.to_s
        else
          rounded.to_s
        end
      rescue
        value.to_s
      end
    end
  end
end
