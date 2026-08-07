# ===== Consolidated from: tool/input_helpers.rb =====
module DuctExtension
  module Tool
    # Small shared parser/formatter for SketchUp input boxes.
    # Keeping this here prevents each tool/prompt from growing its own slightly
    # different number and Yes/No handling.
    module InputHelpers
      module_function

      def positive_number(value, fallback = nil)
        Model::DuctDimensions.positive_number(value, fallback)
      rescue
        fallback
      end

      def yes?(value, default: true)
        text = value.to_s.strip.downcase
        return true if %w[yes y true 1].include?(text)
        return false if %w[no n false 0].include?(text)

        default
      rescue
        default
      end

      def format_number(value, precision: 3)
        number = value.to_f
        rounded = number.round(precision)
        return rounded.round.to_s if (rounded - rounded.round).abs < (10.0**-precision)

        rounded.to_s
      rescue
        value.to_s
      end
    end
  end
end

# ===== Consolidated from: tool/duct_tool_menu.rb =====
module DuctExtension
  module Tool
    module DuctToolMenu
      private

      def populate_duct_tool_menu(menu, _flags = nil, _x = nil, _y = nil, _view = nil)
        catalog_active = Catalog::Manager.active?(Sketchup.active_model)

        menu.add_item("Catalog: #{Catalog::Manager.active_name(Sketchup.active_model)}...") {
          key = Catalog::Manager.prompt_set_catalog(Sketchup.active_model)
          Sketchup.active_model.select_tool(self.class.new) if key
        }

        if catalog_active
          menu.add_item("Switch to Base / Generic Mode") {
            Catalog::Manager.set_active(Sketchup.active_model, Catalog::Manager::BASE_KEY)
            Sketchup.active_model.select_tool(self.class.new)
          }
          menu.add_item("Browse Master Flow Catalog...") {
            Catalog::Manager.show_catalog_browser(Sketchup.active_model)
          }
          menu.add_item("Options for Current Size...") { show_current_catalog_options }
          menu.add_item("Choose Current Duct / Elbow Products...") { choose_catalog_products_from_menu }
        end

        menu.add_separator
        add_mode_menu_items(menu)
        menu.add_separator
        add_component_menu(menu)
        menu.add_separator
        add_axis_lock_menu(menu)
        add_length_increment_menu(menu)
        add_vent_repeat_menu(menu) unless catalog_active
      rescue => error
        puts "DuctToolMenu.populate_duct_tool_menu failed: #{error.message}"
      end

      def add_mode_menu_items(menu)
        if Catalog::Manager.active?(Sketchup.active_model)
          menu.add_item("Placement: Catalog Elbow / Straight → Run") {
            @fitting_mode = :elbow
            update_catalog_status
          }

          if @last_port && respond_to?(:catalog_phase, true) && catalog_phase == :elbow
            menu.add_item("Next Connection: Continue Straight (No Elbow)") {
              @catalog_phase = :run
              @orthogonal_axis_lock = nil
              reset_typed_length
              update_catalog_status
            }
          end
          return
        end

        menu.add_item("Mode: Auto-Elbow") { select_fitting_mode(:elbow) }
        menu.add_item("Mode: Straight Only") { select_fitting_mode(:straight) }
      end

      def add_component_menu(menu)
        components_menu = menu.add_submenu("New Components")

        if Catalog::Manager.active?(Sketchup.active_model)
          dims = current_dimensions
          tees = Catalog::Manager.junction_products(dims, :tee, Sketchup.active_model)
          wyes = Catalog::Manager.junction_products(dims, :wye, Sketchup.active_model)
          transitions = Catalog::Manager.transition_targets(dims, Sketchup.active_model)
          cover = Catalog::Manager.end_cover_product(dims, Sketchup.active_model)

          if tees.empty?
            components_menu.add_item("Tee — none for current size") { show_current_catalog_options }
          else
            components_menu.add_item("Add Tee — #{tees.map(&:sku).join(' / ')}") {
              select_fitting_mode(:tee, round_tee_from_click: true)
            }
            components_menu.add_item("End Tee — #{tees.map(&:sku).join(' / ')}") {
              select_fitting_mode(:end_tee, round_tee_from_click: true)
            }
          end

          if wyes.empty?
            components_menu.add_item("Wye — none for current size") { show_current_catalog_options }
          else
            components_menu.add_item("End Wye — #{wyes.map(&:sku).join(' / ')}") {
              select_fitting_mode(:end_wye)
            }
          end

          if transitions.empty?
            components_menu.add_item("Reducer / Converter — none from current size") { show_current_catalog_options }
          else
            components_menu.add_item("End Reducer / Converter...") {
              select_fitting_mode(:end_reducer)
            }
          end

          if cover
            components_menu.add_item("End Cover — #{cover.sku}") {
              select_fitting_mode(
                :vent,
                status: "Master Flow end-cover mode: click the open end of a compatible catalog duct."
              )
            }
          else
            components_menu.add_item("End Cover — none for current size") { show_current_catalog_options }
          end

          # Master Flow RESMF164 has no close catalog equivalent for the base
          # cross or generic side-register primitive. Deliberately omit them here
          # instead of offering a command that can only fail or create a fake SKU.
          return
        end

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

# ===== Consolidated from: tool/duct_tool_typed_length.rb =====
module DuctExtension
  module Tool
    module DuctToolTypedLength
      private

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

        if catalog_workflow_active? && catalog_phase != :run
          Sketchup.status_text = "Place the selected catalog elbow first. Length entry applies to the following straight run."
          return true
        end

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
        return commit_catalog_typed_length(view) if catalog_workflow_active?

        start = active_route_start_point
        return false unless start

        raw_point = preview_raw_point(view, start)
        raw_point ||= start.offset(fallback_typed_length_direction, 1.0)

        build_point = typed_length_preview_point(start, raw_point)
        return false unless build_point
        return false if start.distance(build_point) < PREVIEW_MIN_LENGTH

        Services::PortCapService.remove(@last_port) if @last_port

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

    end
  end
end
