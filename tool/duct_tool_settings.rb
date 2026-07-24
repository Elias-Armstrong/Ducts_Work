module DuctExtension
  module Tool
    module DuctToolSettings
      private

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
        set_duct_tool_class_setting(:@@last_round_tee_side_mode, mode)
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
        Geometry::VectorMath.normalized(vector)
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
        ReducerPrompt.prompt_for_port(port)
      end

      # Class-level preferences belong to DuctTool, not to this mixin module.
      # Access them through the receiving class to avoid Ruby class-variable
      # lookup leaking into DuctToolSettings.
      def duct_tool_class_setting(name)
        self.class.class_variable_get(name)
      end

      def set_duct_tool_class_setting(name, value)
        self.class.class_variable_set(name, value)
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
